# frozen_string_literal: true

module RefineryRelay
  # Builds Relay sources from Refinery's registered engines. This deliberately
  # works at plugin level: a Refinery plugin is one installed engine, while an
  # engine can contain many supporting models that must not become duplicate
  # Relay sources.
  class SourceRegistry
    Source = Struct.new(
      :key, :label, :description, :model_name, :title, :fields, :path, :plugin_name, :scope, :route,
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
          path: path,
          scope: scope,
          route: route
        }
      end
    end

    CORE_PLUGIN_NAMES = %w[core pages pods settings relay_settings].freeze
    TITLE_FIELDS = %w[title name question subject headline].freeze
    CONTENT_FIELDS = %w[body content description summary short_description teaser answer details].freeze

    class << self
      # Custom engines with non-standard routes/models can declare exactly what
      # Relay may ingest. Example:
      #
      # RefineryRelay.register_source(
      #   plugin: "works", key: "works", model: "Refinery::Works::Work",
      #   title: :title, fields: %i[summary body],
      #   scope: :live, route: :work_path
      # )
      def register(attributes)
        source = build_source(attributes)
        registered_sources[source.key] = source
        reset!
        source
      end

      def known
        @known ||= begin
          sources = { "pages" => page_source }
          registered_sources.each_value { |source| sources[source.key] = source }
          plugin_sources.each { |source| sources[source.key] ||= source }
          sources.values.sort_by { |source| [ source.key == "pages" ? 0 : 1, source.key ] }
        end
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

      def options
        available.select { |source| ingestible?(source) }
      end

      def fetch(key)
        known.find { |source| source.key == key.to_s }
      end

      def source_type_for(model)
        model_name = model.respond_to?(:name) ? model.name.to_s : model.to_s
        known.find { |source| source.model_name == model_name }&.key
      end

      def reset!
        @known = nil
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
        fields = model.respond_to?(:column_names) ? model.column_names.map(&:to_s) : []
        title = TITLE_FIELDS.find { |field| fields.include?(field) }
        title ||= TITLE_FIELDS.find { |field| model.instance_methods.include?(field.to_sym) }
        return unless title

        content_fields = CONTENT_FIELDS.select { |field| fields.include?(field) && field != title }
        build_source(
          key: key,
          label: plugin_label(plugin, key),
          description: "#{plugin_label(plugin, key)} content",
          model: model.name.to_s,
          title: title.to_sym,
          fields: content_fields.map(&:to_sym),
          path: "/#{key}",
          plugin: plugin.name.to_s,
          scope: public_scope_for(model),
          route: public_route_for(model)
        )
      rescue StandardError
        nil
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
        label = nil if label.to_s.start_with?("translation missing")
        label.presence || fallback.humanize
      rescue StandardError
        fallback.humanize
      end

      def ingestible?(source)
        return true if source.key == "pages"
        return false unless source.scope.present? && source.route.present?
        return false if source.route.to_s.include?("admin")

        helpers = refinery_route_helpers
        helpers && helpers.respond_to?(source.route)
      rescue StandardError
        false
      end

      def public_route_for(model)
        return unless defined?(::Refinery) && ::Refinery.respond_to?(:route_for_model)

        ::Refinery.route_for_model(model, admin: false)
      rescue ArgumentError, NameError
        nil
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
          path: attributes.fetch(:path, "/#{key}"),
          plugin_name: plugin_name,
          scope: attributes[:scope],
          route: attributes[:route]
        )
      end

      def normalized_source_key(value)
        value.to_s.sub(/\Arefinerycms_/, "").sub(/\Arefinery_/, "").underscore.presence
      end
    end
  end
end
