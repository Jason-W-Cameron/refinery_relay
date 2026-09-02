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

    def self.source_options
      SourceRegistry.options
    end

    def self.source_types
      SourceRegistry.keys
    end

    def self.source_type_for(model)
      SourceRegistry.source_type_for(model)
    end

    class InvalidCursor < StandardError; end

    def self.call(cursor:, public_base_url:)
      new(cursor: cursor, public_base_url: public_base_url).call
    end

    def initialize(cursor:, public_base_url:, page_size: DEFAULT_PAGE_SIZE, source_types: nil, source_field_mappings: nil, route_helpers: nil)
      @cursor = decode_cursor(cursor)
      @public_base_url = public_base_url.to_s.sub(%r{/+\z}, "")
      @page_size = [[page_size.to_i, 1].max, MAX_PAGE_SIZE].min
      @source_types = normalize_source_types(source_types || RelaySetting.current.source_types)
      @source_field_mappings = normalize_source_field_mappings(source_field_mappings || RelaySetting.current.source_field_mappings)
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

    attr_reader :cursor, :public_base_url, :page_size, :source_types, :source_field_mappings

    def cursor_state
      return tombstone_state if cursor.blank? || cursor["mode"] == "complete"

      mode = cursor["mode"] == "snapshot" ? "pages" : cursor["mode"]
      # Existing cursors predate field mappings. Restarting their snapshot is
      # intentional: Relay needs every document rebuilt with the new field set.
      return tombstone_state unless cursor.key?("source_field_mappings")
      return tombstone_state unless cursor.key?("citation_policies")

      if normalize_source_field_mappings(cursor["source_field_mappings"]) != source_field_mappings
        return tombstone_state
      end

      return tombstone_state unless cursor["citation_policies"] == citation_policies

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
        documents.concat(records.map { |record| document_for_selected_source(record, source_type) }.compact)
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

    def deleted_source_document(record, source_type)
      { "external_id" => "#{source_type}:#{record.id}", "deleted" => true }
    end

    def source_scope(source_type, last_id)
      return page_scope(last_id) if source_type == "pages"

      source = SourceRegistry.fetch(source_type)
      return unless source

      model = source.model
      return unless model

      scope = source.definition.fetch(:scope)
      return unless scope

      relation = scope.respond_to?(:call) ? scope.call(model) : model.public_send(scope)
      relation.where(model.arel_table[:id].gt(last_id)).order(id: :asc)
    end

    def document_for_selected_source(record, source_type)
      return document_for(record) if source_type == "pages"

      return deleted_source_document(record, source_type) unless source_status_for(source_type).ingestible?

      document_for_source(record, source_type)
    end

    def page_scope(last_id)
      ::Refinery::Page.live.where("refinery_pages.id > ?", last_id).order("refinery_pages.id ASC")
    end

    def tombstone_state(last_id = 0)
      {
        "mode" => "tombstones", "last_id" => last_id, "source_types" => source_types,
        "source_field_mappings" => source_field_mappings, "citation_policies" => citation_policies
      }
    end

    def source_state(source_index, last_id)
      {
        "mode" => "sources", "source_index" => source_index, "last_id" => Integer(last_id),
        "source_types" => source_types, "source_field_mappings" => source_field_mappings,
        "citation_policies" => citation_policies
      }
    end

    def complete_state
      {
        "mode" => "complete", "source_types" => source_types,
        "source_field_mappings" => source_field_mappings, "citation_policies" => citation_policies
      }
    end

    def normalize_source_types(values)
      Array(values).map(&:to_s) & SourceRegistry.keys
    end

    def normalize_source_field_mappings(mappings)
      SourceRegistry.normalize_field_mappings(mappings)
    end

    def citation_policies
      @citation_policies ||= source_types.each_with_object({}) do |source_type, policies|
        next if source_type == "pages"

        definition = SourceRegistry.fetch(source_type)&.definition
        next unless definition
        status = source_status_for(source_type)

        policies[source_type] = {
          "strategy" => definition.fetch(:citation_strategy, :record).to_s,
          "collection_path" => definition[:collection_path].to_s,
          "anchor" => definition[:citation_anchor].respond_to?(:call) ? "callable" : definition[:citation_anchor].to_s,
          "endpoint_available" => status.ingestible?
        }
      end
    end

    def source_status_for(source_type)
      @source_statuses ||= {}
      @source_statuses[source_type] ||= SourceRegistry.source_status(
        SourceRegistry.fetch(source_type), host: public_endpoint_host, protocol: public_endpoint_protocol
      )
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

      source = SourceRegistry.fetch(source_type)
      return unless source

      definition = source.definition
      title_attribute = definition[:title]
      title_value = record.public_send(title_attribute) if title_attribute && record.respond_to?(title_attribute)
      title = plain_text(title_value).presence || "Untitled #{source_type.humanize.downcase}"
      fields = fields_for_source(source, definition).each_with_object([]) do |field, values|
        next unless record.respond_to?(field)

        text = plain_text(record.public_send(field))
        values << [ field.to_s.humanize, text ] if text.present?
      end
      pods = []
      url = source_url(record, definition)
      return unless url.present?

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
        "url" => url,
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

    def fields_for_source(source, definition)
      selected_fields = source_field_mappings[source.key]
      return definition.fetch(:fields) if selected_fields.blank?

      selected_fields.map(&:to_sym)
    end

    def source_content_blocks(title, fields, pods)
      blocks = [ { "kind" => "heading", "level" => 1, "text" => title } ]
      fields.each do |label, value|
        blocks << { "kind" => "heading", "level" => 2, "text" => label }
        blocks.concat(html_blocks(value).presence || [ { "kind" => "paragraph", "text" => value } ])
      end
      blocks + pod_blocks(pods)
    end

    def source_url(record, definition)
      # A resource route can exist without being the canonical visitor-facing
      # page. Automatically detected engines therefore cite their public
      # collection page. Explicit source contracts can opt into record routes
      # or a stable collection anchor when the host has one.
      path = citation_path_for(record, definition)
      return unless public_route_path?(path)

      candidate = path.match?(%r{\Ahttps?://}i) ? path : "#{public_base_url}#{path.start_with?("/") ? path : "/#{path}"}"
      normalized_http_url(candidate)
    end

    def citation_path_for(record, definition)
      case definition.fetch(:citation_strategy, :record).to_sym
      when :collection
        definition[:collection_path]
      when :collection_anchor
        collection_path_with_anchor(record, definition)
      when :record_or_collection
        record_path = route_path_for(record, definition[:route])
        return record_path if public_route_path?(record_path) && public_endpoint_available?(record_path)

        definition[:collection_path]
      else
        route_path_for(record, definition[:route]) || definition[:collection_path]
      end
    end

    def collection_path_with_anchor(record, definition)
      path = definition[:collection_path].to_s
      return if path.blank?

      anchor = definition[:citation_anchor]
      anchor = anchor.call(record) if anchor.respond_to?(:call)
      anchor = anchor.to_s.delete_prefix("#")
      anchor.present? ? "#{path}##{anchor}" : path
    end

    def route_path_for(record, route_name = nil)
      return unless defined?(Refinery) && Refinery.respond_to?(:route_for_model)

      helper_name = route_name.presence || Refinery.route_for_model(record.class, admin: false)
      helpers = refinery_route_helpers
      return unless helpers&.respond_to?(helper_name)

      helpers.public_send(helper_name, record)
    rescue ArgumentError, NoMethodError, NameError
      nil
    end

    def public_route_path?(path)
      return false if path.blank?
      return true if path.match?(%r{\Ahttps?://}i)
      return false unless path.start_with?("/")
      return true unless defined?(::Refinery::Core) && ::Refinery::Core.respond_to?(:backend_route)

      backend_path = "/#{::Refinery::Core.backend_route}"
      path != backend_path && !path.start_with?("#{backend_path}/")
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

    def public_endpoint_host
      uri = URI.parse(public_base_url)
      return unless uri.host

      uri.port ? "#{uri.host}:#{uri.port}" : uri.host
    rescue URI::InvalidURIError
      nil
    end

    def public_endpoint_protocol
      URI.parse(public_base_url).scheme
    rescue URI::InvalidURIError
      "http"
    end

    def public_endpoint_available?(path)
      PublicEndpointValidator.call(path: path, host: public_endpoint_host, protocol: public_endpoint_protocol).available?
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
      # Refinery::Page#url contains the host's canonical nested public path.
      # The generic route_for_model fallback resolves to Refinery's technical
      # `/pages/:id` route, which is public but is not necessarily the URL
      # visitors use on the host site.
      path = page.respond_to?(:url) ? page.url.to_s : ""
      path = "/" if path.blank?

      candidate = if path =~ %r{\Ahttps?://}i
        path
      else
        "#{public_base_url}#{path.start_with?("/") ? path : "/#{path}"}"
      end
      normalized = normalized_http_url(candidate)
      return normalized if normalized.present?

      route_path = route_path_for(page)
      if route_path.present?
        candidate = route_path.match?(%r{\Ahttps?://}i) ? route_path : "#{public_base_url}#{route_path.start_with?("/") ? route_path : "/#{route_path}"}"
        normalized = normalized_http_url(candidate)
        return normalized if normalized.present?
      end

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
