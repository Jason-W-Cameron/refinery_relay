# frozen_string_literal: true

require "base64"
require "digest"
require "i18n"
require "json"
require "nokogiri"
require "time"
require "uri"

module RefineryRelay
  # Builds Relay documents directly from Refinery records. This deliberately
  # avoids the optional /nlweb/rss endpoint: that route is not part of a
  # normal Refinery installation and cannot represent all source types or a
  # page's associated Pods reliably.
  class DocumentFeed
    DEFAULT_PAGE_SIZE = 25
    MAX_PAGE_SIZE = 100
    POD_TEXT_FIELDS = %w[body body2 body3 hidden_body].freeze
    SOURCE_OPTIONS = [
      { key: "pages", label: "Pages" },
      { key: "blog_posts", label: "Blog posts" },
      { key: "works", label: "Works" },
      { key: "expertises", label: "Expertises" },
      { key: "faqs", label: "FAQs" },
      { key: "industries", label: "Industries" },
      { key: "local_businesses", label: "Local businesses" },
      { key: "brands", label: "Brands" }
    ].freeze
    SOURCE_TYPES = SOURCE_OPTIONS.map { |source| source.fetch(:key) }.freeze
    SOURCE_DEFINITIONS = {
      "pages" => { model: "Refinery::Page" },
      "blog_posts" => {
        model: "Refinery::Blog::Post", title: :title,
        fields: %i[short_description custom_teaser body], path: "/blog/posts"
      },
      "works" => {
        model: "Refinery::Works::Work", title: :title,
        fields: %i[industry short_description jumbo body_title body_subtitle body_description quote url],
        path: "/works"
      },
      "expertises" => {
        model: "Refinery::Expertises::Expertise", title: :title,
        fields: %i[banner_text short_subtitle short_description jumbo quote url seo_title seo_description],
        path: "/expertises"
      },
      "faqs" => {
        model: "Refinery::Faqs::Faq", title: :question, fields: %i[answer], path: "/faqs"
      },
      "industries" => {
        model: "Refinery::Industries::Industry", title: :name, fields: [], path: "/industries"
      },
      "local_businesses" => {
        model: "Refinery::LocalBusinesses::LocalBusiness", title: :name,
        fields: %i[street_address address_locality address_region postal_code address_country telephone website_url description],
        path: "/local_businesses"
      },
      "brands" => {
        model: "Refinery::Brands::Brand", title: :title, fields: %i[year url], path: "/brands"
      }
    }.freeze

    def self.source_type_for(model)
      model_name = model.respond_to?(:name) ? model.name.to_s : model.to_s
      SOURCE_DEFINITIONS.find { |_source_type, definition| definition.fetch(:model) == model_name }&.first
    end

    class InvalidCursor < StandardError; end

    def self.call(cursor:, public_base_url:)
      new(cursor: cursor, public_base_url: public_base_url).call
    end

    def initialize(cursor:, public_base_url:, page_size: DEFAULT_PAGE_SIZE, source_types: nil, route_helpers: nil)
      @cursor = decode_cursor(cursor)
      @public_base_url = public_base_url.to_s.sub(%r{/+\z}, "")
      @page_size = [[page_size.to_i, 1].max, MAX_PAGE_SIZE].min
      @source_types = normalize_source_types(source_types || RelaySetting.current.source_types)
      @route_helpers = route_helpers
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

    attr_reader :cursor, :public_base_url, :page_size, :source_types

    def cursor_state
      return tombstone_state if cursor.blank? || cursor["mode"] == "complete"

      mode = cursor["mode"] == "snapshot" ? "pages" : cursor["mode"]
      if mode == "pages"
        return source_state(0, cursor.fetch("last_id"))
      end
      raise InvalidCursor unless %w[tombstones sources].include?(mode)

      if cursor.key?("source_types") && normalize_source_types(cursor["source_types"]) != source_types
        return tombstone_state
      end

      return tombstone_state if mode == "tombstones"

      last_id = Integer(cursor.fetch("last_id"))
      raise InvalidCursor if last_id.negative?

      source_index = Integer(cursor.fetch("source_index"))
      raise InvalidCursor if source_index.negative?

      source_state(source_index, last_id)
    rescue KeyError, ArgumentError, TypeError
      raise InvalidCursor
    end

    def documents_for(state)
      if state.fetch("mode") == "tombstones"
        tombstones, more_tombstones = tombstone_batch(state.fetch("last_id"))
        return [ tombstones.map { |tombstone| deleted_document(tombstone) }, tombstone_state(tombstones.last.id) ] if more_tombstones

        remaining = page_size - tombstones.length
        documents, next_state = source_documents(0, 0, remaining)
        return [ tombstones.map { |tombstone| deleted_document(tombstone) } + documents, next_state ]
      end

      source_documents(state.fetch("source_index"), state.fetch("last_id"), page_size)
    end

    def source_documents(source_index, last_id, limit)
      documents = []
      while limit.positive? && source_index < source_types.length
        source_type = source_types.fetch(source_index)
        records, more_records = source_batch(source_type, last_id, limit)
        documents.concat(records.map { |record| document_for_source(record, source_type) })
        limit -= records.length

        if more_records
          return [ documents, source_state(source_index, records.last.id) ]
        end

        source_index += 1
        last_id = 0
      end

      [ documents, complete_state ]
    end

    def source_batch(source_type, last_id, limit)
      return [ [], false ] if limit <= 0

      scope = source_scope(source_type, last_id)
      return [ [], false ] unless scope

      records = scope.limit(limit + 1).to_a
      [ records.first(limit), records.length > limit ]
    rescue ActiveRecord::StatementInvalid, NameError, NoMethodError
      [ [], false ]
    end

    def tombstone_batch(last_id)
      return [ [], false ] if source_types.empty?

      tombstone_model = RefineryRelay::SourceTombstone
      return [ [], false ] unless tombstone_model.available?

      records = []
      cursor_id = last_id
      loop do
        batch = tombstone_model.where("id > ?", cursor_id).order("id ASC").limit(page_size + 1).to_a
        break if batch.empty?

        cursor_id = batch.last.id
        records.concat(batch.select { |record| tombstone_matches_source?(record) })
        break if records.length > page_size || batch.length <= page_size
      end
      [ records.first(page_size), records.length > page_size ]
    rescue NameError
      [ [], false ]
    end

    def tombstone_matches_source?(tombstone)
      source_types.any? { |source_type| tombstone.external_id.to_s.start_with?("#{source_type}:") }
    end

    def deleted_document(tombstone)
      { "external_id" => tombstone.external_id, "deleted" => true }
    end

    def source_scope(source_type, last_id)
      return page_scope(last_id) if source_type == "pages"

      definition = SOURCE_DEFINITIONS.fetch(source_type)
      model = definition.fetch(:model).safe_constantize
      return unless model

      relation = model.respond_to?(:live) ? model.live : model.all
      relation.where(model.arel_table[:id].gt(last_id)).order(id: :asc)
    end

    def page_scope(last_id)
      ::Refinery::Page.live.where("refinery_pages.id > ?", last_id).order("refinery_pages.id ASC")
    end

    def tombstone_state(last_id = 0)
      { "mode" => "tombstones", "last_id" => last_id, "source_types" => source_types }
    end

    def source_state(source_index, last_id)
      { "mode" => "sources", "source_index" => source_index, "last_id" => Integer(last_id), "source_types" => source_types }
    end

    def complete_state
      { "mode" => "complete", "source_types" => source_types }
    end

    def normalize_source_types(values)
      Array(values).map(&:to_s).intersection(SOURCE_TYPES)
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

    def document_for_source(record, source_type)
      return document_for(record) if source_type == "pages"

      definition = SOURCE_DEFINITIONS.fetch(source_type)
      title = plain_text(record.public_send(definition.fetch(:title))).presence || "Untitled #{source_type.humanize.downcase}"
      fields = definition.fetch(:fields).filter_map do |field|
        next unless record.respond_to?(field)

        text = plain_text(record.public_send(field))
        [ field.to_s.humanize, text ] if text.present?
      end
      pods = source_type.in?(%w[works expertises]) ? page_pods(record) : []
      content = ([ "Title: #{title}" ] + fields.map { |label, text| "#{label}: #{text}" } + pod_content(pods)).join("\n\n")
      updated_at = ([ record.updated_at, record.respond_to?(:published_at) ? record.published_at : nil ] + pods.map(&:updated_at)).compact.max || Time.current
      metadata = {
        "source" => "refinery",
        "source_type" => source_type,
        "record_id" => record.id
      }
      document = {
        "external_id" => "#{source_type}:#{record.id}",
        "title" => title,
        "url" => source_url(record, definition.fetch(:path)),
        "content" => content,
        "content_type" => source_type.singularize,
        "language" => ::I18n.locale.to_s.presence || "en",
        "updated_at" => updated_at.utc.iso8601,
        "content_blocks" => source_content_blocks(title, fields, pods),
        "metadata" => metadata
      }
      document["content_hash"] = Digest::SHA256.hexdigest(JSON.generate(canonicalize(document.except("updated_at"))))
      document
    end

    def source_content_blocks(title, fields, pods)
      blocks = [ { "kind" => "heading", "level" => 1, "text" => title } ]
      fields.each do |label, value|
        blocks << { "kind" => "heading", "level" => 2, "text" => label }
        blocks.concat(html_blocks(value).presence || [ { "kind" => "paragraph", "text" => value } ])
      end
      blocks + pod_blocks(pods)
    end

    def source_url(record, collection_path)
      # FriendlyId's custom_url is the record's parameter, not the public
      # route itself. Resolve the route through Refinery so mounted paths,
      # extension namespaces, and route customizations are respected.
      path = route_path_for(record)
      unless path.present?
        slug = record.respond_to?(:slug) && record.slug.present? ? record.slug : record.id
        path = "#{collection_path}/#{slug}"
      end
      candidate = path.match?(%r{\Ahttps?://}i) ? path : "#{public_base_url}#{path.start_with?("/") ? path : "/#{path}"}"
      normalized_http_url(candidate) || public_base_url
    end

    def route_path_for(record)
      return unless defined?(Refinery) && Refinery.respond_to?(:route_for_model)

      helper_name = Refinery.route_for_model(record.class, admin: false)
      helpers = refinery_route_helpers
      return unless helpers&.respond_to?(helper_name)

      helpers.public_send(helper_name, record)
    rescue ArgumentError, NoMethodError, NameError
      nil
    end

    def refinery_route_helpers
      return @route_helpers if @route_helpers
      return unless defined?(Rails) && Rails.application

      mounted_helpers = Rails.application.routes.mounted_helpers
      return mounted_helpers.refinery if mounted_helpers.respond_to?(:refinery)

      return unless defined?(Refinery::Core::Engine)

      Refinery::Core::Engine.routes.url_helpers
    rescue NoMethodError
      nil
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
      route_path = route_path_for(page)
      if route_path.present?
        candidate = route_path.match?(%r{\Ahttps?://}i) ? route_path : "#{public_base_url}#{route_path.start_with?("/") ? route_path : "/#{route_path}"}"
        normalized = normalized_http_url(candidate)
        return normalized if normalized.present?
      end

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
