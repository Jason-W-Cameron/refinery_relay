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
      pages = page_scope(state.fetch("last_id")).limit(page_size + 1).to_a
      batch = pages.first(page_size)
      has_more = pages.length > page_size
      last_id = batch.last ? batch.last.id : state.fetch("last_id")

      checkpoint = encode_cursor(
        has_more ? { "mode" => "snapshot", "last_id" => last_id } : { "mode" => "complete" }
      )
      payload = {
        "documents" => batch.map { |page| document_for(page) }.compact,
        "cursor" => checkpoint
      }
      payload["next_cursor"] = checkpoint if has_more
      payload
    end

    private

    attr_reader :cursor, :public_base_url, :page_size

    def cursor_state
      return { "last_id" => 0 } if cursor.blank? || cursor["mode"] == "complete"
      raise InvalidCursor unless cursor["mode"] == "snapshot"

      last_id = Integer(cursor.fetch("last_id"))
      raise InvalidCursor if last_id.negative?

      { "last_id" => last_id }
    rescue KeyError, ArgumentError, TypeError
      raise InvalidCursor
    end

    def page_scope(last_id)
      ::Refinery::Page.live.where("refinery_pages.id > ?", last_id).order("refinery_pages.id ASC")
    end

    def document_for(page)
      title = page.title.to_s.squish.presence || "Untitled page"
      parts = page_parts(page)
      pods = page_pods(page)
      content_blocks = page_content_blocks(title, parts, pods)
      content = ([ "Title: #{title}" ] + part_content(parts) + pod_content(pods)).join("\n\n")
      updated_at = ([ page.updated_at ] + parts.map(&:updated_at) + pods.map(&:updated_at)).compact.max || Time.current
      metadata = {
        "source" => "refinery",
        "page_id" => page.id,
        "slug" => page.respond_to?(:slug) ? page.slug : nil,
        "pod_types" => pods.map { |pod| pod.respond_to?(:pod_type) ? pod.pod_type.to_s : nil }.compact.uniq.sort,
        "page_part_count" => parts.length,
        "pod_count" => pods.length
      }.delete_if { |_key, value| value.nil? }

      {
        "external_id" => "pages:#{page.id}",
        "title" => title,
        "url" => page_url(page),
        "content" => content,
        "content_type" => "page",
        "language" => ::I18n.locale.to_s.presence || "en",
        "updated_at" => updated_at.utc.iso8601,
        "content_hash" => Digest::SHA256.hexdigest(JSON.generate(canonicalize("content" => content, "content_blocks" => content_blocks, "metadata" => metadata))),
        "content_blocks" => content_blocks,
        "metadata" => metadata
      }
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
    def page_content_blocks(title, parts, pods)
      [ { "kind" => "heading", "level" => 1, "text" => title } ] +
        page_part_blocks(parts) + pod_blocks(pods)
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
