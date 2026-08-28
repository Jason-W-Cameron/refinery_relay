# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "generators/refinery_relay/install/install_generator"

class RefineryRelayDisposableHostInstallTest < ActiveSupport::TestCase
  test "generator output boots in an independent Rails host" do
    temporary_parent = RefineryRelay::Engine.root.join("tmp")
    FileUtils.mkdir_p(temporary_parent)

    Dir.mktmpdir("refinery-relay-host-", temporary_parent) do |temporary_root|
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
  end

  def write_host_file(host_root, path, content)
    absolute_path = File.join(host_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end

  def assert_generated_host_files(host_root)
    routes = File.read(File.join(host_root, "config/routes.rb"))
    assert_not_includes routes, "/refinery_relay/api/relay/chat"
    assert_not_includes routes, "ActionCable"
    assert_empty Dir.glob(File.join(host_root, "config/initializers/refinery_relay.rb"))
    assert Dir.glob(File.join(host_root, "db/migrate/*_create_refinery_relay_settings.rb")).any?
  end

  def assert_host_boots(host_root)
    script = <<~RUBY
      settings = Rails.application.routes.recognize_path(
        "/refinery/relay_settings",
        method: :get
      )
      raise "settings route missing" unless settings[:controller] == "refinery_relay/admin/relay_settings"
      raise "Relay settings plugin missing" unless Refinery::Plugins.registered.names.include?("relay_settings")
      puts "disposable host boot: OK"
    RUBY
    environment = {
      "BUNDLE_GEMFILE" => RefineryRelay::Engine.root.join("Gemfile").to_s,
      "RAILS_ENV" => "test"
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
