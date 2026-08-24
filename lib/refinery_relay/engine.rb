module RefineryRelay
  class Engine < ::Rails::Engine
    isolate_namespace RefineryRelay

    initializer "refinery_relay.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.precompile += %w[
        refinery_relay/admin.js
        refinery_relay/chat.js
        refinery_relay/application.css
      ]
    end

    config.after_initialize do
      next unless defined?(::Refinery::Core)
      next if ::Refinery::Core.javascripts.include?("refinery_relay/admin")

      ::Refinery::Core.config.register_javascript("refinery_relay/admin")
    end

    config.to_prepare do
      RefineryRelay::PodRegistration.install!
      RefineryRelay::PageChangeTracking.install!
    end
  end
end
