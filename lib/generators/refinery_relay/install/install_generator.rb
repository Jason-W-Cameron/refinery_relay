# frozen_string_literal: true

require "pathname"
require "rails/generators"

module RefineryRelay
  module Generators
    class InstallGenerator < Rails::Generators::Base
      CHAT_ROUTE = "/refinery_relay/api/relay/chat"
      AVAILABILITY_ROUTE = "#{CHAT_ROUTE}/availability"
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
      # missing. A successful generator run must result in a usable backend
      # integration, rather than a partially installed engine that fails later.
      def preflight
        failures = preflight_failures
        return if failures.empty?

        raise Thor::Error, <<~MESSAGE
          Refinery Relay cannot be installed:\n\n#{failures.map { |failure| "  - #{failure}" }.join("\n")}

          Fix the listed requirements and run `bin/rails generate refinery_relay:install` again.
        MESSAGE
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
        if availability_installed && chat_installed
          say_status :identical, path
          return
        end

        routes = [ "# Niimble Relay API routes use direct host routes for Refinery routing-filter compatibility." ]
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
        route routes.join("\n")
      end

      def install_source_tombstones_migration
        return if Dir.glob(destination_path("db/migrate/*_create_refinery_relay_source_tombstones.rb")).any?

        timestamp = next_migration_timestamp
        copy_file "create_refinery_relay_source_tombstones.rb",
                  "db/migrate/#{timestamp}_create_refinery_relay_source_tombstones.rb"
      end

      def install_relay_settings_migration
        return if Dir.glob(destination_path("db/migrate/*_create_refinery_relay_settings.rb")).any?

        timestamp = next_migration_timestamp
        copy_file "create_refinery_relay_settings.rb",
                  "db/migrate/#{timestamp}_create_refinery_relay_settings.rb"
      end

      def install_widget_markup_migration
        return if Dir.glob(destination_path("db/migrate/*_add_widget_markup_to_refinery_relay_settings.rb")).any?

        timestamp = next_migration_timestamp
        copy_file "add_widget_markup_to_refinery_relay_settings.rb",
                  "db/migrate/#{timestamp}_add_widget_markup_to_refinery_relay_settings.rb"
      end

      def install_source_types_migration
        return if Dir.glob(destination_path("db/migrate/*_add_source_types_to_refinery_relay_settings.rb")).any?

        timestamp = next_migration_timestamp
        copy_file "add_source_types_to_refinery_relay_settings.rb",
                  "db/migrate/#{timestamp}_add_source_types_to_refinery_relay_settings.rb"
      end

      def show_post_install_steps
        readme "POST_INSTALL"
      end

      private

      def destination_path(path)
        File.expand_path(path, destination_root)
      end

      def destination_file?(path)
        File.file?(destination_path(path))
      end

      def destination_content(path)
        File.read(destination_path(path))
      end

      def next_migration_timestamp
        used_timestamps = Dir.glob(destination_path("db/migrate/*.rb")).filter_map do |path|
          File.basename(path)[/\A(\d{14})_/, 1]
        end
        timestamp = Time.now.utc
        timestamp += 1.second while used_timestamps.include?(timestamp.strftime("%Y%m%d%H%M%S"))
        timestamp.strftime("%Y%m%d%H%M%S")
      end

      def preflight_failures
        failures = []
        failures << "config/routes.rb is missing" unless destination_file?("config/routes.rb")
        failures << "the refinerycms-pods gem (~> 1.0) is not installed" unless pods_gem_installed?
        failures << "the installed refinerycms-pods gem does not expose Refinery::Pods::Pod::POD_TYPES" unless pods_api_available?

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

      def route_installed?(content, verb, path)
        content.match?(%r{^\s*#{verb}\s+["']#{Regexp.escape(path)}["']})
      end

    end
  end
end
