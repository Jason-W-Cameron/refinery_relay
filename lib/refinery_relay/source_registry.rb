# frozen_string_literal: true

module RefineryRelay
  # Builds Relay sources from Refinery's registered engines. This deliberately
  # works at plugin level: a Refinery plugin is one installed engine, while an
  # engine can contain many supporting models that must not become duplicate
  # Relay sources.
  class SourceRegistry
    Source = Struct.new(
      :key, :label, :description, :model_name, :title, :fields, :field_options, :path, :plugin_name, :scope, :route,
      :citation_strategy, :collection_path, :citation_anchor,
      keyword_init: true
    ) do
      def model
        model_name.to_s.safe_constantize
      end

      def available?
        klass = model
        klass && klass.respond_to?(:table_exists?) && klass.table_exists?
      rescue StandardError
        false
      end

      def definition
        {
          model: model_name,
          title: title,
          fields: Array(fields),
          field_options: Array(field_options),
          path: path,
          scope: scope,
          route: route,
          citation_strategy: citation_strategy,
          collection_path: collection_path,
          citation_anchor: citation_anchor
        }
      end
    end

    SourceStatus = Struct.new(:source, :ingestible, :reason, keyword_init: true) do
      def ingestible?
        ingestible
      end
    end

    CORE_PLUGIN_NAMES = %w[core pages pods settings relay_settings].freeze
    TITLE_FIELDS = %w[title name question subject headline].freeze
    CONTENT_FIELDS = %w[body content description summary short_description teaser custom_teaser answer details].freeze
    VIRTUAL_CONTENT_FIELDS = %w[
      body content description summary short_description teaser custom_teaser answer details tag_list
    ].freeze
    TEXT_COLUMN_TYPES = %i[string text].freeze
    NON_CONTENT_FIELD_NAMES = %w[
      id created_at updated_at deleted_at published_at unpublished_at position lock_version
      type slug permalink friendly_id
    ].freeze
    SENSITIVE_FIELD_PATTERN = /(?:\A|_)(?:api|access|auth|credential|encrypted|password|secret|token|digest|salt|reset|confirmation)(?:\z|_)/i

    class << self
      # Custom engines with non-standard routes/models can declare exactly what
      # Relay may ingest. Example:
      #
      # RefineryRelay.register_source(
      #   plugin: "works", key: "works", model: "Refinery::Works::Work",
      #   title: :title, fields: %i[summary body],
      #   field_options: %i[summary body seo_description],
      #   scope: :live, route: :work_path,
      #   citation_strategy: :record
      #
      # Collection-only engines can keep citations on their visitor-facing
      # landing page without hardcoding a client-specific source in the gem:
      #
      #   citation_strategy: :collection_anchor,
      #   collection_path: "/faqs",
      #   citation_anchor: ->(faq) { "faq-#{faq.id}" }
      # )
      def register(attributes)
        source = build_source(attributes)
        registered_sources[source.key] = source
        reset!
        source
      end

      def known
        # Refinery registers host engines during application preparation. Do
        # not cache a partial list created before that work finishes: it would
        # leave a plugged-in Relay installation permanently showing only Pages.
        sources = { "pages" => page_source }
        registered_sources.each_value { |source| sources[source.key] = source }
        plugin_sources.each { |source| sources[source.key] ||= source }
        sources.values.sort_by { |source| [ source.key == "pages" ? 0 : 1, source.key ] }
      end

      def available
        known.select(&:available?)
      end

      def keys
        known.map(&:key)
      end

      def available_keys
        available.map(&:key)
      end

      # Installed sources stay visible when their visitor-facing endpoint is
      # broken, so Settings can explain why they cannot be selected.
      def source_statuses(host: nil, protocol: "http")
        available.map { |source| source_status(source, host: host, protocol: protocol) }
      end

      def options(host: nil, protocol: "http")
        source_statuses(host: host, protocol: protocol).select(&:ingestible?).map(&:source)
      end

      def fetch(key)
        known.find { |source| source.key == key.to_s }
      end

      def source_type_for(model)
        model_name = model.respond_to?(:name) ? model.name.to_s : model.to_s
        known.find { |source| source.model_name == model_name }&.key
      end

      def reset!
        # Source discovery is intentionally evaluated on demand; see known.
      end

      # Keep the persisted settings and feed on the exact same source contract.
      # Unknown sources and fields are ignored rather than being trusted from a
      # form submission or an older cursor.
      def normalize_field_mappings(mappings)
        Hash(mappings || {}).each_with_object({}) do |(source_key, fields), normalized|
          source = fetch(source_key)
          next unless source

          allowed_fields = Array(source.field_options).map(&:to_s)
          selected_fields = Array(fields).map(&:to_s).select { |field| allowed_fields.include?(field) }.uniq
          normalized[source.key] = selected_fields if selected_fields.present?
        end
      rescue TypeError
        {}
      end

      private

      def registered_sources
        @registered_sources ||= {}
      end

      def page_source
        build_source(
          key: "pages",
          label: "Pages",
          description: "Published pages and their Pod content",
          model: "Refinery::Page"
        )
      end

      def plugin_sources
        refinery_plugins.each_with_object([]) do |plugin, sources|
          source = source_for_plugin(plugin)
          next unless source
          next if sources.any? { |existing| existing.key == source.key }

          sources << source
        end
      end

      def source_for_plugin(plugin)
        plugin_key = normalized_plugin_name(plugin)
        return if CORE_PLUGIN_NAMES.include?(plugin_key)

        explicit_source_for(plugin, plugin_key) || automatic_source_for(plugin, plugin_key)
      end

      def explicit_source_for(plugin, plugin_key)
        registered_sources.values.find do |source|
          [ plugin.name.to_s, plugin_key ].include?(source.plugin_name.to_s)
        end
      end

      # Standard Refinery engines expose their primary admin resource through
      # plugin.url (for example, /refinery/blog/posts). If that cannot resolve
      # a model, use Refinery's generated engine convention. No descendant or
      # filesystem scan is used, so supporting models cannot create duplicates.
      def automatic_source_for(plugin, plugin_key)
        model = model_for_plugin(plugin, plugin_key)
        return unless model

        generic_source(model, model_source_key(model), plugin)
      end

      def model_for_plugin(plugin, plugin_key)
        model_candidates_for(plugin, plugin_key).each do |model_name|
          model = safe_constantize(model_name)
          return model if model && model.respond_to?(:table_exists?)
        end
        nil
      end

      def model_candidates_for(plugin, plugin_key)
        namespace = plugin_key.camelize
        resource = plugin_resource_name(plugin)
        candidates = []
        candidates << "Refinery::#{namespace}::#{resource.singularize.camelize}" if resource.present?
        candidates << "Refinery::#{namespace}::#{plugin_key.singularize.camelize}"
        candidates.uniq
      end

      def plugin_resource_name(plugin)
        target = plugin.url
        target = target[:controller] if target.is_a?(Hash)
        target.to_s.sub(/[?#].*\z/, "").split("/").reject(&:blank?).last
      rescue StandardError
        nil
      end

      def refinery_plugins
        return [] unless defined?(::Refinery::Plugins)

        registered = ::Refinery::Plugins.registered
        registered.respond_to?(:values) ? registered.values : Array(registered)
      rescue StandardError
        []
      end

      def normalized_plugin_name(plugin)
        plugin.name.to_s.sub(/\Arefinerycms_/, "").sub(/\Arefinery_/, "").underscore
      end

      def model_source_key(model)
        parts = model.name.to_s.sub(/\ARefinery::/, "").split("::")
        return if parts.length < 2

        namespace = parts[0...-1].map(&:underscore).join("_")
        model_name = parts.last.underscore
        return namespace if namespace.singularize == model_name

        "#{namespace}_#{model_name.pluralize}"
      end

      # Automatic sources include only ordinary public-content fields. A custom
      # engine can use register_source to opt into any additional fields or to
      # provide a stricter publication scope than the relation available on the
      # model.
      def generic_source(model, key, plugin)
        plugin_key = normalized_plugin_name(plugin)
        fields = model.respond_to?(:column_names) ? model.column_names.map(&:to_s) : []
        title = TITLE_FIELDS.find { |field| fields.include?(field) }
        title ||= TITLE_FIELDS.find { |field| model.instance_methods.include?(field.to_sym) }
        return unless title

        collection_path = public_collection_path_for(plugin_key, key)
        return unless collection_path

        field_options = selectable_fields_for(model, title)
        content_fields = CONTENT_FIELDS.select { |field| field_options.include?(field) }
        build_source(
          key: key,
          label: plugin_label(plugin, key),
          description: "#{plugin_label(plugin, key)} content",
          model: model.name.to_s,
          title: title.to_sym,
          fields: content_fields.map(&:to_sym),
          field_options: field_options.map(&:to_sym),
          path: collection_path,
          plugin: plugin.name.to_s,
          scope: public_scope_for(model),
          route: public_route_for(model),
          # Prefer a canonical record URL only when the feed can verify it.
          # DocumentFeed falls back to this verified collection page when a
          # legacy engine's individual show route is not safe to cite.
          citation_strategy: :record_or_collection,
          collection_path: collection_path
        )
      rescue StandardError
        nil
      end

      # These are fields an administrator may explicitly choose to send to
      # Relay. Defaults remain deliberately narrower (`CONTENT_FIELDS`) so an
      # upgrade does not change an existing site's indexed content. Only text
      # columns are candidates, and identifiers, routing identifiers, timestamps,
      # associations, and obvious secrets are never selectable.
      def selectable_fields_for(model, title)
        return [] unless model.respond_to?(:columns)

        column_fields = model.columns.map do |column|
          name = column.name.to_s
          next unless TEXT_COLUMN_TYPES.include?(column.type.to_sym)
          next if name == title.to_s
          next if non_content_field?(name)

          name
        end.compact
        (column_fields + selectable_virtual_fields_for(model, title)).uniq
      rescue StandardError
        []
      end

      # Refinery Blog (and several older Refinery extensions) stores its
      # translated content outside the primary model table. These attributes
      # are still safe to index when the model explicitly exposes them.
      def selectable_virtual_fields_for(model, title)
        instance_methods = model.instance_methods.map(&:to_s)
        translated_attributes = model.respond_to?(:translated_attribute_names) ? model.translated_attribute_names.map(&:to_s) : []
        available_attributes = instance_methods + translated_attributes
        VIRTUAL_CONTENT_FIELDS.select do |field|
          field != title.to_s && available_attributes.include?(field)
        end
      rescue StandardError
        []
      end

      def non_content_field?(name)
        NON_CONTENT_FIELD_NAMES.include?(name) ||
          name.end_with?("_id", "_ids") ||
          name.match?(SENSITIVE_FIELD_PATTERN)
      end

      # Refinery engines are not required to define a `.live` scope. Older and
      # custom engines commonly expose public records through their normal
      # relation and enforce visibility in the public controller instead. The
      # public citation route remains a required gate in ingestible?, while
      # explicit registrations can still provide a stricter scope.
      def public_scope_for(model)
        return :live if model.respond_to?(:live)
        return :published if model.respond_to?(:published)
        return :all if model.respond_to?(:all)

        nil
      end

      def plugin_label(plugin, fallback)
        label = plugin.title if plugin.respond_to?(:title)
        label = nil if label.to_s.match?(/\Atranslation missing:/i)
        label.presence || fallback.humanize
      rescue StandardError
        fallback.humanize
      end

      def source_status(source, host:, protocol:)
        return SourceStatus.new(source: source, ingestible: true) if source.key == "pages"
        return unavailable(source, "does not expose a public content scope") unless source.scope.present?
        return unavailable(source, "does not expose a public record route") unless source.route.present?
        return unavailable(source, "uses an admin route") if source.route.to_s.include?("admin")

        collection_path = source.collection_path.to_s
        return unavailable(source, "does not declare a public collection URL") if collection_path.blank?

        helpers = refinery_route_helpers
        return unavailable(source, "does not expose its public route helper") unless helpers&.respond_to?(source.route)

        # A named public route is sufficient to make a source selectable.
        # Rendering an in-process anonymous request here is not reliable on
        # legacy Rails/Refinery hosts (it can fail on unrelated layout code),
        # and must not hide standard sources such as Blog or Hospitals.
        SourceStatus.new(source: source, ingestible: true)
      rescue StandardError => error
        unavailable(source, "could not be checked (#{error.class}: #{error.message})")
      end

      def unavailable(source, reason)
        SourceStatus.new(source: source, ingestible: false, reason: reason)
      end

      public :source_status

      def public_route_for(model)
        return unless defined?(::Refinery) && ::Refinery.respond_to?(:route_for_model)

        ::Refinery.route_for_model(model, admin: false)
      rescue ArgumentError, NameError
        nil
      end

      # The plugin's name is not a URL contract. Prefer its public collection
      # route helper and do not offer an automatically detected source if the
      # host does not expose one. Custom engines can declare collection_path
      # explicitly with register_source.
      def public_collection_path_for(plugin_key, source_key)
        helpers = refinery_route_helpers
        return unless helpers

        [
          "#{plugin_key}_#{plugin_key}_path",
          "#{plugin_key}_#{source_key}_path",
          "#{plugin_key}_path",
          "#{plugin_key}_root_path",
          "#{source_key}_path"
        ].uniq.each do |helper_name|
          next unless helpers.respond_to?(helper_name)

          path = helpers.public_send(helper_name)
          return path if public_collection_path?(path)
        rescue ArgumentError, NoMethodError
          next
        end
        nil
      end

      def public_collection_path?(path)
        path.to_s.start_with?("/") && !path.to_s.start_with?("/#{::Refinery::Core.backend_route}/")
      rescue NameError
        path.to_s.start_with?("/") && !path.to_s.start_with?("/refinery/")
      end

      def refinery_route_helpers
        return unless defined?(Rails) && Rails.application

        mounted_helpers = Rails.application.routes.mounted_helpers
        return mounted_helpers.refinery if mounted_helpers.respond_to?(:refinery)

        return unless defined?(::Refinery::Core::Engine)

        ::Refinery::Core::Engine.routes.url_helpers
      rescue NoMethodError
        nil
      end

      def safe_constantize(name)
        name.to_s.safe_constantize
      rescue NameError, LoadError
        nil
      end

      def build_source(attributes)
        plugin_name = attributes[:plugin].to_s.presence
        key = attributes[:key].to_s.presence || normalized_source_key(plugin_name)
        raise ArgumentError, "A Relay source requires a key or plugin name" unless key

        Source.new(
          key: key,
          label: attributes.fetch(:label, key.humanize),
          description: attributes.fetch(:description, "#{key.humanize} content"),
          model_name: attributes.fetch(:model).to_s,
          title: attributes[:title],
          fields: Array(attributes[:fields]),
          field_options: Array(attributes.fetch(:field_options, attributes[:fields])),
          path: attributes.fetch(:path, "/#{key}"),
          plugin_name: plugin_name,
          scope: attributes[:scope],
          route: attributes[:route],
          citation_strategy: attributes.fetch(:citation_strategy, :record).to_sym,
          collection_path: attributes.fetch(:collection_path, attributes.fetch(:path, "/#{key}")),
          citation_anchor: attributes[:citation_anchor]
        )
      end

      def normalized_source_key(value)
        value.to_s.sub(/\Arefinerycms_/, "").sub(/\Arefinery_/, "").underscore.presence
      end
    end
  end
end
