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
  end

  test "installs only the backend Relay integration" do
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_not_includes content, "/refinery_relay/api/relay/chat"
      assert_not_includes content, "ActionCable"
    end

    assert_not File.exist?(File.join(destination_root, "app/assets/javascripts/application.js"))
    assert_not File.exist?(File.join(destination_root, "app/assets/stylesheets/application.css"))
    settings_migration = Dir.glob(File.join(destination_root, "db/migrate/*_create_refinery_relay_settings.rb")).first
    widget_migration = Dir.glob(File.join(destination_root, "db/migrate/*_add_widget_markup_to_refinery_relay_settings.rb")).first
    tombstones_migration = Dir.glob(File.join(destination_root, "db/migrate/*_create_refinery_relay_source_tombstones.rb")).first
    source_types_migration = Dir.glob(File.join(destination_root, "db/migrate/*_add_source_types_to_refinery_relay_settings.rb")).first
    source_field_mappings_migration = Dir.glob(File.join(destination_root, "db/migrate/*_add_source_field_mappings_to_refinery_relay_settings.rb")).first
    pod_type_migration = Dir.glob(File.join(destination_root, "db/migrate/*_rename_llm_chat_pod_type_to_relay_chat.rb")).first
    assert settings_migration
    assert widget_migration
    assert tombstones_migration
    assert source_types_migration
    assert source_field_mappings_migration
    assert pod_type_migration
    refute_equal File.basename(settings_migration).first(14), File.basename(tombstones_migration).first(14)
    refute_equal File.basename(widget_migration).first(14), File.basename(tombstones_migration).first(14)
    assert_includes File.read(settings_migration), "create_table :refinery_relay_settings"
    assert_includes File.read(settings_migration), "table.text :widget_markup"
    assert_includes File.read(pod_type_migration), "SET pod_type = 'relay_chat'"
  end

  test "can be run twice without adding chat proxy routes" do
    run_generator
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_equal 0, content.scan('/refinery_relay/api/relay/chat').length
    end
  end

  test "does not create a host initializer" do
    run_generator

    assert_not File.exist?(File.join(destination_root, "config/initializers/refinery_relay.rb"))
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

  test "does not require Sprockets manifests" do
    assert_empty install_generator.send(:preflight_failures)
  end

  private

  def install_generator
    RefineryRelay::Generators::InstallGenerator.new([], {}, destination_root: destination_root)
  end

  def write_host_file(path, content)
    absolute_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end
end
