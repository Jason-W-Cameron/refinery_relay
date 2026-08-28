module RefineryRelay
  class Engine < ::Rails::Engine
    isolate_namespace RefineryRelay

    initializer "refinery_relay.source_route" do |app|
      app.routes.prepend do
        get "/refinery_relay/api/relay/documents",
            to: "refinery_relay/api/relay/documents#index"

        scope "/#{::Refinery::Core.backend_route}" do
          get "relay_settings", to: "refinery_relay/admin/relay_settings#edit", as: :refinery_relay_settings
          patch "relay_settings", to: "refinery_relay/admin/relay_settings#update"
          post "relay_settings/generate_bearer_token", to: "refinery_relay/admin/relay_settings#generate_bearer_token",
               as: :refinery_relay_generate_bearer_token
        end
      end
    end

    initializer "refinery_relay.register_settings_plugin" do
      ::Refinery::Plugin.register do |plugin|
        plugin.name = "relay_settings"
        plugin.pathname = root
        plugin.always_allow_access = true
        plugin.menu_match = %r{\Arefinery_relay/relay_settings\z}
        plugin.url = proc { Rails.application.routes.url_helpers.refinery_relay_settings_path }
      end
    end

    config.to_prepare do
      RefineryRelay::PodRegistration.install!
      RefineryRelay::PodRendering.install!
      RefineryRelay::Engine.install_source_sync_callbacks!
    end

    def self.install_source_sync_callbacks!
      install_callback(::Refinery::Page, RefineryRelay::PageSourceSyncCallbacks) if defined?(::Refinery::Page)

      [
        "Refinery::PagePart",
        "Refinery::Pods::Pod"
      ].each do |name|
        model = name.safe_constantize
        install_callback(model, RefineryRelay::SourceSyncCallbacks) if model
      end

      [
        "Refinery::Blog::Post",
        "Refinery::Copywritings::Copywriting",
        "Refinery::Faqs::Faq",
        "Refinery::InfoCentres::InfoCentre",
        "Refinery::OfficeLocations::OfficeLocation",
        "Refinery::Products::Product",
        "Refinery::Projects::Project",
        "Refinery::Testimonials::Testimonial",
        "Refinery::Varieties::Variety",
        "Refinery::VideoLibraries::VideoLibrary"
      ].each do |name|
        model = name.safe_constantize
        install_callback(model, RefineryRelay::SourceTombstoneCallbacks) if model
      end
    end

    def self.install_callback(model, callback)
      model.include(callback) unless model.ancestors.include?(callback)
    end
  end
end
