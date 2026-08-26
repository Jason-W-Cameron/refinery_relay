# frozen_string_literal: true

require "pathname"
require "rails/generators"

module RefineryRelay
  module Generators
    class InstallGenerator < Rails::Generators::Base
      JAVASCRIPT_DIRECTIVE = "//= require refinery_relay/chat"
      STYLESHEET_DIRECTIVE = "*= require refinery_relay/application"
      CHAT_ROUTE = "/refinery_relay/api/relay/chat"
      AVAILABILITY_ROUTE = "#{CHAT_ROUTE}/availability"
      DOCUMENTS_ROUTE = "/refinery_relay/api/relay/documents"
      ADMIN_SETTINGS_ROUTE = "/refinery_relay/admin/settings"
      CABLE_MOUNT = 'mount ActionCable.server => "/cable"'
      REQUIRED_ENVIRONMENT_VARIABLES = %w[
        REDIS_URL
        RELAY_CHAT_BASE_URL
        RELAY_CHAT_TOKEN
        RELAY_PUBLIC_BASE_URL
      ].freeze

      source_root File.expand_path("templates", __dir__)

      def self.exit_on_failure?
        true
      end

      def ensure_host_application
        return unless Pathname.new(destination_root).expand_path == RefineryRelay::Engine.root.expand_path

        raise Thor::Error,
          "Run refinery_relay:install from the consuming Refinery application, not from the refinery_relay gem directory."
      end

      # Stop before changing the host when its required integration points are
      # missing. A successful generator run must result in a usable chat Pod,
      # rather than a partially installed engine that fails later at runtime.
      def preflight
        failures = preflight_failures
        return if failures.empty?

        raise Thor::Error, <<~MESSAGE
          Refinery Relay cannot be installed:\n\n#{failures.map { |failure| "  - #{failure}" }.join("\n")}

          Fix the listed requirements and run `bin/rails generate refinery_relay:install` again.
        MESSAGE
      end

      def create_initializer
        path = "config/initializers/refinery_relay.rb"
        return say_status(:skip, "#{path} already exists (host configuration preserved)") if destination_file?(path)

        template "initializer.rb", path
      end

      def install_routes
        path = "config/routes.rb"
        unless destination_file?(path)
          say_status :warning, "#{path} not found; add the Refinery Relay chat routes manually"
          return
        end

        content = destination_content(path)
        availability_installed = route_installed?(content, "get", AVAILABILITY_ROUTE)
        chat_installed = route_installed?(content, "post", CHAT_ROUTE)
        documents_installed = route_installed?(content, "get", DOCUMENTS_ROUTE)
        admin_settings_installed = route_installed?(content, "get", ADMIN_SETTINGS_ROUTE)
        cable_installed = cable_mount_installed?(content)
        if availability_installed && chat_installed && documents_installed && admin_settings_installed && cable_installed
          say_status :identical, path
          return
        end

        routes = [ "# Niimble Relay chat routes use direct host routes for Refinery routing-filter compatibility." ]
        unless availability_installed
          routes << <<~RUBY.chomp
            get "#{AVAILABILITY_ROUTE}",
                to: "refinery_relay/api/relay/chats#availability"
          RUBY
        end
        unless chat_installed
          routes << <<~RUBY.chomp
            post "#{CHAT_ROUTE}",
                 to: "refinery_relay/api/relay/chats#create"
          RUBY
        end
        unless documents_installed
          routes << <<~RUBY.chomp
            get "#{DOCUMENTS_ROUTE}",
                to: "refinery_relay/api/relay/documents#index"
          RUBY
        end
        unless admin_settings_installed
          routes << <<~RUBY.chomp
            get "#{ADMIN_SETTINGS_ROUTE}",
                to: "refinery_relay/admin/settings#show"
          RUBY
        end
        routes << CABLE_MOUNT unless cable_installed

        route routes.join("\n")
      end

      def install_javascript_asset
        path = first_existing(JAVASCRIPT_MANIFESTS)
        unless path
          say_status :warning, "No Sprockets JavaScript manifest found; add `#{JAVASCRIPT_DIRECTIVE}` manually"
          return
        end

        install_javascript_directive(path)
      end

      def install_stylesheet_asset
        path = first_existing(STYLESHEET_MANIFESTS)
        unless path
          say_status :warning, "No Sprockets stylesheet manifest found; add `#{STYLESHEET_DIRECTIVE}` manually"
          return
        end

        install_stylesheet_directive(path)
      end

      def install_site_settings_migration
        return if Dir.glob(destination_path("db/migrate/*_create_refinery_relay_site_settings.rb")).any?

        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file "create_refinery_relay_site_settings.rb",
                  "db/migrate/#{timestamp}_create_refinery_relay_site_settings.rb"
      end

      def install_pod_settings_migration
        return if Dir.glob(destination_path("db/migrate/*_create_refinery_relay_pod_settings.rb")).any?

        timestamp = (Time.now.utc + 1).strftime("%Y%m%d%H%M%S")
        copy_file "create_refinery_relay_pod_settings.rb",
                  "db/migrate/#{timestamp}_create_refinery_relay_pod_settings.rb"
      end

      def install_footer_logo_settings_migration
        return if Dir.glob(destination_path("db/migrate/*_add_footer_logo_settings_to_refinery_relay_pod_settings.rb")).any?

        timestamp = (Time.now.utc + 2).strftime("%Y%m%d%H%M%S")
        copy_file "add_footer_logo_settings_to_refinery_relay_pod_settings.rb",
                  "db/migrate/#{timestamp}_add_footer_logo_settings_to_refinery_relay_pod_settings.rb"
      end

      def install_terms_link_migration
        return if Dir.glob(destination_path("db/migrate/*_add_terms_link_to_refinery_relay_pod_settings.rb")).any?

        timestamp = (Time.now.utc + 3).strftime("%Y%m%d%H%M%S")
        copy_file "add_terms_link_to_refinery_relay_pod_settings.rb",
                  "db/migrate/#{timestamp}_add_terms_link_to_refinery_relay_pod_settings.rb"
      end

      def install_information_image_migration
        return if Dir.glob(destination_path("db/migrate/*_add_information_image_to_refinery_relay_pod_settings.rb")).any?

        timestamp = (Time.now.utc + 4).strftime("%Y%m%d%H%M%S")
        copy_file "add_information_image_to_refinery_relay_pod_settings.rb",
                  "db/migrate/#{timestamp}_add_information_image_to_refinery_relay_pod_settings.rb"
      end

      def install_assistant_response_color_migration
        return if Dir.glob(destination_path("db/migrate/*_add_assistant_response_color_to_refinery_relay_site_settings.rb")).any?

        timestamp = (Time.now.utc + 5).strftime("%Y%m%d%H%M%S")
        copy_file "add_assistant_response_color_to_refinery_relay_site_settings.rb",
                  "db/migrate/#{timestamp}_add_assistant_response_color_to_refinery_relay_site_settings.rb"
      end

      def show_post_install_steps
        readme "POST_INSTALL"
      end

      private

      JAVASCRIPT_MANIFESTS = %w[
        app/assets/javascripts/application.js
        app/assets/javascripts/application.js.erb
      ].freeze

      STYLESHEET_MANIFESTS = %w[
        app/assets/stylesheets/application.scss
        app/assets/stylesheets/application.css
        app/assets/stylesheets/application.sass
        app/assets/stylesheets/application.css.scss
      ].freeze

      def destination_path(path)
        File.expand_path(path, destination_root)
      end

      def destination_file?(path)
        File.file?(destination_path(path))
      end

      def destination_content(path)
        File.read(destination_path(path))
      end

      def preflight_failures
        failures = []
        failures << "config/routes.rb is missing" unless destination_file?("config/routes.rb")
        failures << "the refinerycms-pods gem (~> 1.0) is not installed" unless pods_gem_installed?
        failures << "the installed refinerycms-pods gem does not expose Refinery::Pods::Pod::POD_TYPES" unless pods_api_available?
        failures << "the installed refinerycms-pods gem does not expose Refinery::Pods::Admin::PodsController" unless pods_admin_controller_available?
        failures << "no Sprockets JavaScript manifest was found (expected #{JAVASCRIPT_MANIFESTS.join(", ")})" unless first_existing(JAVASCRIPT_MANIFESTS)
        failures << "no Sprockets stylesheet manifest was found (expected #{STYLESHEET_MANIFESTS.join(", ")})" unless first_existing(STYLESHEET_MANIFESTS)

        missing_environment = REQUIRED_ENVIRONMENT_VARIABLES.select { |name| ENV[name].to_s.strip.empty? }
        unless missing_environment.empty?
          failures << "required environment variables are missing: #{missing_environment.join(", ")}"
        end

        failures
      end

      def pods_gem_installed?
        specification = Gem.loaded_specs["refinerycms-pods"]
        specification && Gem::Requirement.new("~> 1.0").satisfied_by?(specification.version)
      end

      def pods_api_available?
        pod_class = "Refinery::Pods::Pod".safe_constantize
        pod_class&.const_defined?(:POD_TYPES, false)
      end

      def pods_admin_controller_available?
        "Refinery::Pods::Admin::PodsController".safe_constantize.present?
      end

      def first_existing(paths)
        paths.find { |path| destination_file?(path) }
      end

      def route_installed?(content, verb, path)
        content.match?(%r{^\s*#{verb}\s+["']#{Regexp.escape(path)}["']})
      end

      def cable_mount_installed?(content)
        content.match?(/^\s*mount\s+ActionCable\.server\s*=>\s*["']\/cable["']/)
      end

      def install_javascript_directive(path)
        content = destination_content(path)
        return say_status(:identical, path) if content.include?(JAVASCRIPT_DIRECTIVE)

        directive_lines = content.lines.grep(%r{^\s*//=\s*require\b})
        if directive_lines.any?
          insert_into_file path, "#{JAVASCRIPT_DIRECTIVE}\n", after: directive_lines.last
        else
          prepend_to_file path, "#{JAVASCRIPT_DIRECTIVE}\n"
        end
      end

      def install_stylesheet_directive(path)
        content = destination_content(path)
        return say_status(:identical, path) if content.include?(STYLESHEET_DIRECTIVE)

        directive_lines = content.lines.grep(/^\s*\*=\s*require\b/)
        if directive_lines.any?
          insert_into_file path, " #{STYLESHEET_DIRECTIVE}\n", after: directive_lines.last
        elsif content.start_with?("/*") && content.include?("*/")
          insert_into_file path, " #{STYLESHEET_DIRECTIVE}\n", before: "*/"
        else
          prepend_to_file path, "/*\n #{STYLESHEET_DIRECTIVE}\n */\n"
        end
      end
    end
  end
end
