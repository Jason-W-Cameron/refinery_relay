# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "generators/refinery_relay/install/install_generator"

class RefineryRelayDisposableHostInstallTest < ActiveSupport::TestCase
  test "generator output boots in an independent Rails host" do
    Dir.mktmpdir("refinery-relay-host-", RefineryRelay::Engine.root.join("tmp")) do |temporary_root|
      host_root = File.join(temporary_root, "host")
      FileUtils.mkdir_p(host_root)
      FileUtils.cp_r("#{dummy_root}/.", host_root)
      prepare_uninstalled_host(host_root)

      RefineryRelay::Generators::InstallGenerator.start([], destination_root: host_root)

      assert_generated_host_files(host_root)
      assert_host_boots(host_root)
    end
  end

  private

  def dummy_root
    RefineryRelay::Engine.root.join("test/dummy")
  end

  def prepare_uninstalled_host(host_root)
    write_host_file(host_root, "config/routes.rb", "Rails.application.routes.draw do\nend\n")
    write_host_file(
      host_root,
      "app/assets/javascripts/application.js",
      "//= require_self\n\nwindow.disposableHostBooted = true;\n"
    )
    write_host_file(
      host_root,
      "app/assets/stylesheets/application.css",
      "/*\n *= require_self\n */\n"
    )
  end

  def write_host_file(host_root, path, content)
    absolute_path = File.join(host_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end

  def assert_generated_host_files(host_root)
    initializer = File.read(File.join(host_root, "config/initializers/refinery_relay.rb"))
    routes = File.read(File.join(host_root, "config/routes.rb"))
    javascript = File.read(File.join(host_root, "app/assets/javascripts/application.js"))
    stylesheet = File.read(File.join(host_root, "app/assets/stylesheets/application.css"))

    assert_includes initializer, 'require "redis"'
    assert_includes routes, 'get "/refinery_relay/api/relay/chat/availability"'
    assert_includes routes, 'post "/refinery_relay/api/relay/chat"'
    assert_includes routes, 'mount ActionCable.server => "/cable"'
    assert_includes javascript, "//= require refinery_relay/chat"
    assert_includes stylesheet, "*= require refinery_relay/application"
  end

  def assert_host_boots(host_root)
    script = <<~RUBY
      availability = Rails.application.routes.recognize_path(
        "/refinery_relay/api/relay/chat/availability",
        method: :get
      )
      chat = Rails.application.routes.recognize_path(
        "/refinery_relay/api/relay/chat",
        method: :post
      )
      raise "availability route missing" unless availability[:controller] == "refinery_relay/api/relay/chats"
      raise "chat route missing" unless chat[:controller] == "refinery_relay/api/relay/chats"
      raise "Redis initializer missing" unless RefineryRelay.configuration.redis.is_a?(Redis)
      raise "chat JavaScript missing" unless Rails.application.assets.find_asset("refinery_relay/chat.js")
      raise "chat stylesheet missing" unless Rails.application.assets.find_asset("refinery_relay/application.css")
      puts "disposable host boot: OK"
    RUBY
    environment = {
      "BUNDLE_GEMFILE" => RefineryRelay::Engine.root.join("Gemfile").to_s,
      "RAILS_ENV" => "test",
      "REDIS_URL" => "redis://127.0.0.1:6379/15"
    }
    stdout, stderr, status = Open3.capture3(
      environment,
      RbConfig.ruby,
      File.join(host_root, "bin/rails"),
      "runner",
      script,
      chdir: host_root
    )

    assert status.success?, "Disposable host failed to boot:\n#{stdout}\n#{stderr}"
    assert_includes stdout, "disposable host boot: OK"
  end
end
