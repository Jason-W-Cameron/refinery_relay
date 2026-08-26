module RefineryRelay
  class Engine < ::Rails::Engine
    isolate_namespace RefineryRelay

    initializer "refinery_relay.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.precompile += %w[
        refinery_relay/admin.js
        refinery_relay/admin.css
        refinery_relay/chat.js
        refinery_relay/application.css
        refinery_relay/niimble-logo-light-tp.png
      ]
    end

    config.after_initialize do
      next unless defined?(::Refinery::Core)

      if ::Refinery::Core.respond_to?(:javascripts) &&
          !::Refinery::Core.javascripts.include?("refinery_relay/admin")
        ::Refinery::Core.config.register_javascript("refinery_relay/admin")
      end

      stylesheets = ::Refinery::Core.config.respond_to?(:stylesheets) ? ::Refinery::Core.config.stylesheets : []
      unless stylesheets.any? { |stylesheet| stylesheet.respond_to?(:path) && stylesheet.path == "refinery_relay/admin" }
        ::Refinery::Core.config.register_stylesheet("refinery_relay/admin")
      end
    end

    config.to_prepare do
      RefineryRelay::PodRegistration.install!
      RefineryRelay::Engine.install_source_sync_callbacks!

      # `to_prepare` may run before classic Rails autoloading has loaded the
      # Pods admin controller. Resolve it by name so registration works on a
      # cold boot as well as after a development reload.
      if (controller = "Refinery::Pods::Admin::PodsController".safe_constantize)
        unless controller.ancestors.include?(RefineryRelay::PodsAdminController)
          controller.prepend(RefineryRelay::PodsAdminController)
        end
      end
    end

    def self.install_source_sync_callbacks!
      install_callback(::Refinery::Page, RefineryRelay::PageSourceSyncCallbacks) if defined?(::Refinery::Page)

      [
        "Refinery::PagePart",
        "Refinery::Pods::Pod",
        "Refinery::Image",
        "Refinery::Resource"
      ].each do |name|
        model = name.safe_constantize
        install_callback(model, RefineryRelay::SourceSyncCallbacks) if model
      end
    end

    def self.install_callback(model, callback)
      model.include(callback) unless model.ancestors.include?(callback)
    end
  end
end
