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
      CABLE_MOUNT = 'mount ActionCable.server => "/cable"'

      source_root File.expand_path("templates", __dir__)

      def self.exit_on_failure?
        true
      end

      def ensure_host_application
        return unless Pathname.new(destination_root).expand_path == RefineryRelay::Engine.root.expand_path

        raise Thor::Error,
          "Run refinery_relay:install from the consuming Refinery application, not from the refinery_relay gem directory."
      end

      def create_initializer
        path = "config/initializers/refinery_relay.rb"
        return say_status(:skip, "#{path} already exists (host configuration preserved)") if destination_file?(path)

        template "initializer.rb", path
      end

      def install_migrations
        return if Dir.glob(destination_path("db/migrate/*_create_refinery_relay_document_changes.rb")).any?

        filename = "db/migrate/#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_create_refinery_relay_document_changes.rb"
        source = File.join(self.class.source_root, "db/migrate/create_refinery_relay_document_changes.rb")
        create_file filename, File.read(source)
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
        cable_installed = cable_mount_installed?(content)
        if availability_installed && chat_installed && cable_installed
          say_status :identical, path
          return
        end

        routes = [ "# Niimble Relay routes use direct host routes for Refinery routing-filter compatibility." ]
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
        unless route_installed?(content, "get", DOCUMENTS_ROUTE)
          routes << <<~RUBY.chomp
            get "#{DOCUMENTS_ROUTE}",
                to: "refinery_relay/api/relay/documents#index"
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
