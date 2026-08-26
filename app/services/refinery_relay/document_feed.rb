# frozen_string_literal: true

require "base64"
require "digest"
require "i18n"
require "json"
require "nokogiri"
require "time"
require "uri"

module RefineryRelay
  # Builds Relay documents directly from Refinery's published Page and Pod
  # records. This deliberately avoids the optional /nlweb/rss endpoint: that
  # route is not part of a normal Refinery installation and cannot represent
  # all of a page's associated Pods reliably.
  class DocumentFeed
    DEFAULT_PAGE_SIZE = 25
    MAX_PAGE_SIZE = 100
    POD_TEXT_FIELDS = %w[body body2 body3 hidden_body].freeze
    PAGE_IMAGE_FIELDS = %i[footer_image footer_mobile_image].freeze
    POD_IMAGE_FIELDS = %i[image mobile_image image2 image3 background_image].freeze
    POD_FILE_FIELDS = %i[file file2].freeze

    class InvalidCursor < StandardError; end

    def self.call(cursor:, public_base_url:)
      new(cursor: cursor, public_base_url: public_base_url).call
    end

    def initialize(cursor:, public_base_url:, page_size: DEFAULT_PAGE_SIZE)
      @cursor = decode_cursor(cursor)
      @public_base_url = public_base_url.to_s.sub(%r{/+\z}, "")
      @page_size = [[page_size.to_i, 1].max, MAX_PAGE_SIZE].min
    end

    def call
      state = cursor_state
      documents, next_state = documents_for(state)
      checkpoint = encode_cursor(next_state)
      payload = {
        "documents" => documents,
        "cursor" => checkpoint
      }
      payload["next_cursor"] = checkpoint unless next_state["mode"] == "complete"
      payload
    end

    private

    attr_reader :cursor, :public_base_url, :page_size

    def cursor_state
      return { "mode" => "tombstones", "last_id" => 0 } if cursor.blank? || cursor["mode"] == "complete"
      mode = cursor["mode"] == "snapshot" ? "pages" : cursor["mode"]
      raise InvalidCursor unless %w[tombstones pages].include?(mode)

      last_id = Integer(cursor.fetch("last_id"))
      raise InvalidCursor if last_id.negative?

      { "mode" => mode, "last_id" => last_id }
    rescue KeyError, ArgumentError, TypeError
      raise InvalidCursor
    end

    def documents_for(state)
      if state.fetch("mode") == "tombstones"
        tombstones, more_tombstones = tombstone_batch(state.fetch("last_id"))
        return [ tombstones.map { |tombstone| deleted_document(tombstone) }, { "mode" => "tombstones", "last_id" => tombstones.last.id } ] if more_tombstones

        remaining = page_size - tombstones.length
        pages, more_pages = page_batch(0, remaining)
        next_state = if more_pages
          { "mode" => "pages", "last_id" => pages.last.id }
        else
          { "mode" => "complete" }
        end
        return [ tombstones.map { |tombstone| deleted_document(tombstone) } + pages.map { |page| document_for(page) }, next_state ]
      end

      pages, more_pages = page_batch(state.fetch("last_id"), page_size)
      next_state = more_pages ? { "mode" => "pages", "last_id" => pages.last.id } : { "mode" => "complete" }
      [ pages.map { |page| document_for(page) }, next_state ]
    end

    def page_batch(last_id, limit)
      return [ [], false ] if limit <= 0

      records = page_scope(last_id).limit(limit + 1).to_a
      [ records.first(limit), records.length > limit ]
    end

    def tombstone_batch(last_id)
      tombstone_model = RefineryRelay::SourceTombstone
      return [ [], false ] unless tombstone_model.available?

      records = tombstone_model.where("id > ?", last_id).order("id ASC").limit(page_size + 1).to_a
      [ records.first(page_size), records.length > page_size ]
    rescue NameError
      [ [], false ]
    end

    def deleted_document(tombstone)
      { "external_id" => tombstone.external_id, "deleted" => true }
    end

    def page_scope(last_id)
      ::Refinery::Page.live.where("refinery_pages.id > ?", last_id).order("refinery_pages.id ASC")
    end

    def document_for(page)
      title = page.title.to_s.squish.presence || "Untitled page"
      parts = page_parts(page)
      pods = page_pods(page)
      assets = page_assets(page, pods)
      asset_text = asset_search_text(assets)
      content_blocks = page_content_blocks(title, parts, pods, asset_text)
      content = ([ "Title: #{title}" ] + part_content(parts) + pod_content(pods) + asset_text).join("\n\n")
      updated_at = ([ page.updated_at ] + parts.map(&:updated_at) + pods.map(&:updated_at) + [ asset_updated_at(page, pods) ]).compact.max || Time.current
      metadata = {
        "source" => "refinery",
        "page_id" => page.id,
        "slug" => page.respond_to?(:slug) ? page.slug : nil,
        "pod_types" => pods.map { |pod| pod.respond_to?(:pod_type) ? pod.pod_type.to_s : nil }.compact.uniq.sort,
        "page_part_count" => parts.length,
        "pod_count" => pods.length,
        "assets" => assets.presence
      }.delete_if { |_key, value| value.nil? }
      document = {
        "external_id" => "pages:#{page.id}",
        "title" => title,
        "url" => page_url(page),
        "content" => content,
        "content_type" => "page",
        "language" => ::I18n.locale.to_s.presence || "en",
        "updated_at" => updated_at.utc.iso8601,
        "content_blocks" => content_blocks,
        "metadata" => metadata
      }
      document["content_hash"] = Digest::SHA256.hexdigest(JSON.generate(canonicalize(document.except("updated_at"))))
      document
    end

    def page_parts(page)
      page.parts.to_a.sort_by { |part| [ part.position.to_i, part.id.to_i ] }
    rescue StandardError
      []
    end

    def page_pods(page)
      return [] unless page.respond_to?(:pods)

      page.pods.to_a.sort_by { |pod| [ pod.respond_to?(:position) ? pod.position.to_i : 0, pod.id.to_i ] }
    rescue StandardError
      []
    end

    def part_content(parts)
      parts.map do |part|
        text = plain_text(part.respond_to?(:body) ? part.body : nil)
        next if text.blank?

        heading = part.respond_to?(:title) ? part.title.to_s.squish : "Page section"
        "#{heading.presence || "Page section"}: #{text}"
      end.compact
    end

    def pod_content(pods)
      pods.map do |pod|
        text = pod_text_fields(pod).map { |_field, value| value }.join("\n\n")
        next if text.blank?

        [ pod_heading(pod), pod_subtitle(pod).presence, text ].compact.join(": ")
      end.compact
    end

    # Relay uses structured blocks to retain headings while it creates
    # embeddings. This is the same contract used by the modern Comrades CMS,
    # adapted to Refinery's page parts and legacy Pods records.
    def page_content_blocks(title, parts, pods, asset_text)
      [ { "kind" => "heading", "level" => 1, "text" => title } ] +
        page_part_blocks(parts) + pod_blocks(pods) + asset_blocks(asset_text)
    end

    def asset_blocks(asset_text)
      return [] if asset_text.empty?

      [
        { "kind" => "heading", "level" => 2, "text" => "Related files and images" },
        { "kind" => "list", "items" => asset_text }
      ]
    end

    def page_part_blocks(parts)
      parts.flat_map do |part|
        text = plain_text(part.respond_to?(:body) ? part.body : nil)
        next [] if text.blank?

        heading = part.respond_to?(:title) ? part.title.to_s.squish : ""
        blocks = []
        blocks << { "kind" => "heading", "level" => 2, "text" => heading } if heading.present?
        blocks.concat(html_blocks(part.body))
        blocks = [ { "kind" => "paragraph", "text" => text } ] if blocks.empty?
        blocks
      end
    end

    def pod_blocks(pods)
      pods.flat_map do |pod|
        fields = pod_text_fields(pod)
        next [] if fields.empty?

        blocks = [ { "kind" => "heading", "level" => 2, "text" => pod_heading(pod) } ]
        subtitle = pod_subtitle(pod)
        blocks << { "kind" => "paragraph", "text" => subtitle } if subtitle.present?
        fields.each do |_field, value|
          extracted = html_blocks(value)
          blocks.concat(extracted.presence || [ { "kind" => "paragraph", "text" => value } ])
        end
        blocks
      end
    end

    def pod_text_fields(pod)
      POD_TEXT_FIELDS.map do |field|
        next unless pod.respond_to?(field)

        text = plain_text(pod.public_send(field))
        [ field, text ] if text.present?
      end.compact
    end

    def pod_heading(pod)
      name = pod.respond_to?(:name) ? pod.name.to_s.squish : ""
      return name if name.present?

      pod_type = pod.respond_to?(:pod_type) ? pod.pod_type.to_s.tr("_", " ").squish : ""
      pod_type.present? ? pod_type : "Content section"
    end

    def pod_subtitle(pod)
      return "" unless pod.respond_to?(:sub_title)

      pod.sub_title.to_s.squish
    end

    def page_assets(page, pods)
      records = []
      records.concat(media_records(page, PAGE_IMAGE_FIELDS, "image"))
      pods.each do |pod|
        records.concat(media_records(pod, POD_IMAGE_FIELDS, "image"))
        records.concat(media_records(pod, POD_FILE_FIELDS, "file"))
      end

      records.each_with_object({}) do |(kind, record), assets|
        asset = media_asset(kind, record)
        assets[asset.fetch("external_id")] ||= asset if asset
      end.values
    end

    def asset_updated_at(page, pods)
      records = media_records(page, PAGE_IMAGE_FIELDS, "image")
      pods.each do |pod|
        records.concat(media_records(pod, POD_IMAGE_FIELDS, "image"))
        records.concat(media_records(pod, POD_FILE_FIELDS, "file"))
      end
      records.map { |_kind, record| record.updated_at if record.respond_to?(:updated_at) }.compact.max
    end

    def media_records(record, fields, kind)
      fields.each_with_object([]) do |field, records|
        next unless record.respond_to?(field)

        attachment = record.public_send(field)
        records << [ kind, attachment ] if attachment.present?
      rescue StandardError
        next
      end
    end

    def media_asset(kind, record)
      url = media_url(record)
      return if url.blank?

      attachment = kind == "image" ? :image : :file
      external_id = "#{kind == "image" ? "images" : "files"}:#{record.id}"
      asset = {
        "external_id" => external_id,
        "kind" => kind == "image" ? "image" : media_kind(record),
        "url" => url,
        "mime_type" => media_mime_type(record),
        "content_hash" => media_content_hash(record, attachment),
        "caption" => media_title(record),
        "alt_text" => media_alt_text(record),
        "metadata" => {
          "refinery_id" => record.id,
          "refinery_attachment" => attachment.to_s
        }
      }
      thumbnail_url = media_thumbnail_url(record) if kind == "image"
      asset["thumbnail_url"] = thumbnail_url if thumbnail_url.present?
      asset.delete_if { |_key, value| value.nil? || value == "" }
    rescue StandardError
      nil
    end

    def media_url(record)
      return unless record.respond_to?(:url)

      absolute_http_url(record.url)
    end

    def media_thumbnail_url(record)
      return unless record.respond_to?(:thumbnail)

      absolute_http_url(record.thumbnail(geometry: "480x480>").url)
    rescue StandardError
      nil
    end

    def media_kind(record)
      media_mime_type(record) == "application/pdf" ? "pdf" : "file"
    end

    def media_mime_type(record)
      return record.mime_type.to_s if record.respond_to?(:mime_type) && record.mime_type.present?
      return record.image_mime_type.to_s if record.respond_to?(:image_mime_type) && record.image_mime_type.present?
      return record.file_mime_type.to_s if record.respond_to?(:file_mime_type) && record.file_mime_type.present?

      "application/octet-stream"
    end

    def media_content_hash(record, attachment)
      value = record.public_send(attachment) if record.respond_to?(attachment)
      data = value.data if value.respond_to?(:data)
      return Digest::SHA256.hexdigest(data) if data.is_a?(String)

      Digest::SHA256.hexdigest([
        record.respond_to?(:id) ? record.id : nil,
        record.respond_to?(:updated_at) ? record.updated_at&.utc&.iso8601 : nil,
        record.respond_to?(:size) ? record.size : nil,
        record.respond_to?(:url) ? record.url : nil
      ].join("\u0000"))
    rescue StandardError
      Digest::SHA256.hexdigest(record.id.to_s)
    end

    def media_title(record)
      record.respond_to?(:title) ? record.title.to_s.squish.presence : nil
    end

    def media_alt_text(record)
      return unless record.respond_to?(:alt)

      record.alt.to_s.squish.presence
    end

    def asset_search_text(assets)
      assets.map do |asset|
        [ asset["caption"], asset["alt_text"], "Attached #{asset["kind"]}: #{asset["url"]}" ].compact.uniq.join(" — ")
      end
    end

    def html_blocks(value)
      fragment = Nokogiri::HTML.fragment(value.to_s)
      fragment.css("script, style, template, noscript").remove
      blocks = fragment.css("h1, h2, h3, h4, h5, h6, p, ul, ol, table, pre").map do |node|
        html_block_for(node)
      end.compact
      return blocks if blocks.present?

      text = plain_text(fragment.text)
      text.split(/\n{2,}/).map do |paragraph|
        cleaned = paragraph.squish
        { "kind" => "paragraph", "text" => cleaned } if cleaned.present?
      end.compact
    rescue Nokogiri::XML::SyntaxError
      text = plain_text(value)
      text.present? ? [ { "kind" => "paragraph", "text" => text } ] : []
    end

    def html_block_for(node)
      case node.name
      when /\Ah([1-6])\z/
        text = plain_text(node.to_html)
        text.present? ? { "kind" => "heading", "level" => Regexp.last_match(1).to_i, "text" => text } : nil
      when "p", "pre"
        text = plain_text(node.to_html)
        text.present? ? { "kind" => node.name == "pre" ? "code" : "paragraph", "text" => text } : nil
      when "ul", "ol"
        items = node.element_children.select { |child| child.name == "li" }.map { |child| plain_text(child.to_html) }.reject(&:blank?)
        items.present? ? { "kind" => "list", "items" => items } : nil
      when "table"
        rows = node.css("tr").map do |row|
          row.css("th, td").map { |cell| plain_text(cell.to_html) }.reject(&:blank?).join(" | ")
        end.reject(&:blank?)
        rows.present? ? { "kind" => "table", "text" => rows.join("\n") } : nil
      end
    end

    def page_url(page)
      path = page.respond_to?(:url) ? page.url.to_s : ""
      path = "/" if path.blank?

      candidate = if path =~ %r{\Ahttps?://}i
        path
      else
        "#{public_base_url}#{path.start_with?("/") ? path : "/#{path}"}"
      end
      normalized = normalized_http_url(candidate)
      return normalized if normalized.present?

      fallback = page.respond_to?(:slug) && page.slug.to_s != "home" ? "/#{page.slug}" : "/"
      normalized_http_url("#{public_base_url}#{fallback}") || public_base_url
    end

    def absolute_http_url(value)
      raw_value = value.to_s
      candidate = raw_value =~ %r{\Ahttps?://}i ? raw_value : "#{public_base_url}/#{raw_value.sub(%r{\A/+}, "")}"
      normalized_http_url(candidate)
    end

    def normalized_http_url(value)
      raw_value = value.to_s
      [ raw_value, URI::DEFAULT_PARSER.escape(raw_value) ].uniq.each do |candidate|
        begin
          uri = URI.parse(candidate)
          return uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
        rescue URI::InvalidURIError
          next
        end
      end
      nil
    end

    def plain_text(value)
      fragment = Nokogiri::HTML.fragment(value.to_s)
      fragment.css("script, style, template, noscript").remove
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css("p, div, li, h1, h2, h3, h4, h5, h6, section, article, table, tr").each do |node|
        node.add_previous_sibling("\n")
        node.add_next_sibling("\n")
      end
      fragment.text.gsub(/[ \t\r\f\v]+/, " ").gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
    rescue Nokogiri::XML::SyntaxError
      value.to_s.squish
    end

    def decode_cursor(value)
      return if value.blank?

      # Earlier refinery_relay releases used the RSS body hash as a terminal
      # cursor. Treat it as a completed snapshot so upgrading this endpoint
      # begins a direct-record snapshot without requiring Relay data to be
      # manually reset.
      return { "mode" => "complete", "v" => 1 } if value.to_s =~ /\A[a-f0-9]{64}\z/i

      padded = value.to_s + ("=" * ((4 - value.to_s.length % 4) % 4))
      decoded = JSON.parse(Base64.urlsafe_decode64(padded))
      raise InvalidCursor unless decoded.is_a?(Hash) && decoded["v"] == 1

      decoded
    rescue ArgumentError, JSON::ParserError
      raise InvalidCursor
    end

    def encode_cursor(payload)
      Base64.urlsafe_encode64(JSON.generate(payload.merge("v" => 1)), padding: false)
    end

    def canonicalize(value)
      case value
      when Hash
        Hash[value.to_h.stringify_keys.sort.map { |key, child| [ key, canonicalize(child) ] }]
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end
  end
end
