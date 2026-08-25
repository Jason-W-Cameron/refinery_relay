module RefineryRelay
  class Engine < ::Rails::Engine
    isolate_namespace RefineryRelay

    initializer "refinery_relay.source_route" do |app|
      app.routes.prepend do
        get "/refinery_relay/api/relay/documents",
            to: "refinery_relay/api/relay/documents#index"
        get "/refinery_relay/admin/settings",
            to: "refinery_relay/admin/settings#show"
      end
    end

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

      unless ::Refinery::Core.javascripts.include?("refinery_relay/admin")
        ::Refinery::Core.config.register_javascript("refinery_relay/admin")
      end
      unless ::Refinery::Core.config.stylesheets.any? { |stylesheet| stylesheet.path == "refinery_relay/admin" }
        ::Refinery::Core.config.register_stylesheet("refinery_relay/admin")
      end
    end

    config.to_prepare do
      RefineryRelay::PodRegistration.install!

      if defined?(::Refinery::Pods::Admin::PodsController)
        controller = ::Refinery::Pods::Admin::PodsController
        unless controller.ancestors.include?(RefineryRelay::PodsAdminController)
          controller.prepend(RefineryRelay::PodsAdminController)
        end
      end
    end
  end
end
