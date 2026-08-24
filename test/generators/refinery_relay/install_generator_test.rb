# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/refinery_relay/install/install_generator"

class RefineryRelayInstallGeneratorTest < Rails::Generators::TestCase
  tests RefineryRelay::Generators::InstallGenerator
  destination RefineryRelay::Engine.root.join("tmp/install_generator_test")

  setup do
    prepare_destination
    write_host_file("config/routes.rb", "Rails.application.routes.draw do\nend\n")
    write_host_file(
      "app/assets/javascripts/application.js",
      "//= require jquery3\n//= require_self\n\nwindow.hostApplication = true;\n"
    )
    write_host_file(
      "app/assets/stylesheets/application.scss",
      "/*\n *= require bootstrap\n *= require_self\n */\n\n@import 'pods';\n"
    )
  end

  test "installs the Refinery Relay host integration" do
    run_generator

    assert_file "config/initializers/refinery_relay.rb" do |content|
      assert_includes content, 'require "redis"'
      assert_includes content, "RefineryRelay.configure"
      assert_includes content, 'ENV.fetch("REDIS_URL")'
      assert_not_includes content, "RELAY_CHAT_TOKEN ="
    end

    assert_file "config/routes.rb" do |content|
      assert_includes content, 'get "/refinery_relay/api/relay/chat/availability"'
      assert_includes content, 'post "/refinery_relay/api/relay/chat"'
      assert_includes content, 'get "/refinery_relay/api/relay/documents"'
      assert_includes content, 'to: "refinery_relay/api/relay/chats#create"'
      assert_includes content, RefineryRelay::Generators::InstallGenerator::CABLE_MOUNT
    end

    assert Dir.glob(File.join(destination_root, "db/migrate/*_create_refinery_relay_document_changes.rb")).any?

    assert_file "app/assets/javascripts/application.js" do |content|
      assert_includes content, RefineryRelay::Generators::InstallGenerator::JAVASCRIPT_DIRECTIVE
      assert_operator content.index("refinery_relay/chat"), :<, content.index("window.hostApplication")
    end

    assert_file "app/assets/stylesheets/application.scss" do |content|
      assert_includes content, RefineryRelay::Generators::InstallGenerator::STYLESHEET_DIRECTIVE
      assert_operator content.index("refinery_relay/application"), :<, content.index("*/")
    end
  end

  test "can be run twice without duplicate routes or asset directives" do
    run_generator
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan('get "/refinery_relay/api/relay/chat/availability"').length
      assert_equal 1, content.scan('post "/refinery_relay/api/relay/chat"').length
      assert_equal 1, content.scan('get "/refinery_relay/api/relay/documents"').length
      assert_equal 1, content.scan(RefineryRelay::Generators::InstallGenerator::CABLE_MOUNT).length
    end

    assert_file "app/assets/javascripts/application.js" do |content|
      assert_equal 1, content.scan("//= require refinery_relay/chat").length
    end

    assert_file "app/assets/stylesheets/application.scss" do |content|
      assert_equal 1, content.scan("*= require refinery_relay/application").length
    end
  end

  test "adds only the missing route when one Relay route already exists" do
    write_host_file(
      "config/routes.rb",
      <<~RUBY
        Rails.application.routes.draw do
          post "/refinery_relay/api/relay/chat",
               to: "refinery_relay/api/relay/chats#create"
        end
      RUBY
    )

    run_generator

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan('get "/refinery_relay/api/relay/chat/availability"').length
      assert_equal 1, content.scan('post "/refinery_relay/api/relay/chat"').length
      assert_equal 1, content.scan(RefineryRelay::Generators::InstallGenerator::CABLE_MOUNT).length
    end
  end

  test "preserves an existing host initializer" do
    custom_initializer = "# Host-owned Relay configuration\n"
    write_host_file("config/initializers/refinery_relay.rb", custom_initializer)

    run_generator

    assert_file "config/initializers/refinery_relay.rb", custom_initializer
  end

  test "generated initializer loads Redis before configuring its connection" do
    run_generator
    previous_redis_url = ENV["REDIS_URL"]
    ENV["REDIS_URL"] = "redis://127.0.0.1:6379/15"
    RefineryRelay.reset_configuration!

    load File.join(destination_root, "config/initializers/refinery_relay.rb")

    assert_instance_of Redis, RefineryRelay.configuration.redis
  ensure
    ENV["REDIS_URL"] = previous_redis_url
    RefineryRelay.reset_configuration!
  end

  test "supports a plain CSS host manifest" do
    FileUtils.rm_f(File.join(destination_root, "app/assets/stylesheets/application.scss"))
    write_host_file("app/assets/stylesheets/application.css", "body { color: black; }\n")

    run_generator

    assert_file "app/assets/stylesheets/application.css" do |content|
      assert content.start_with?("/*\n *= require refinery_relay/application\n */")
      assert_includes content, "body { color: black; }"
    end
  end

  test "refuses a destination that is the gem source directory" do
    generator = RefineryRelay::Generators::InstallGenerator.new(
      [],
      {},
      destination_root: RefineryRelay::Engine.root.to_s
    )

    error = assert_raises(Thor::Error) { generator.ensure_host_application }

    assert_includes error.message, "consuming Refinery application"
  end

  private

  def write_host_file(path, content)
    absolute_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end
end
