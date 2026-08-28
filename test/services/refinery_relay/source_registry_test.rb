# frozen_string_literal: true

require "test_helper"

module Refinery
  module RelayDetected
    class Entry < ::Refinery::Core::BaseModel
      def self.table_exists?
        true
      end

      def self.column_names
        %w[id title body created_at updated_at]
      end
    end
  end

  module PluginDetected
    class PluginDetected
      def self.table_exists?
        true
      end

      def self.all
        self
      end

      def self.column_names
        %w[id name description api_token created_at updated_at]
      end
    end

    class SupportingRecord
      def self.table_exists?
        true
      end

      def self.column_names
        %w[id name body created_at updated_at]
      end
    end
  end
end

class RefineryRelaySourceRegistryTest < ActiveSupport::TestCase
  Plugin = Struct.new(:name, :url)

  setup do
    RefineryRelay::SourceRegistry.reset!
  end

  teardown do
    registered = RefineryRelay::SourceRegistry.instance_variable_get(:@registered_sources)
    %w[relay_detected missing_engine].each { |key| registered.delete(key) } if registered
    RefineryRelay::SourceRegistry.reset!
  end

  test "does not turn every loaded Refinery model into a source" do
    refute_includes RefineryRelay::SourceRegistry.keys, "relay_detected_entries"
  end

  test "discovers one conventional source from Refinery's plugin registry" do
    plugin = Plugin.new("plugin_detected", "/refinery/plugin_detected")
    route_helpers = Object.new
    route_helpers.define_singleton_method(:plugin_detected_path) { |_record| "/plugin-detected/1" }

    stub_class_method(Refinery::Plugins, :registered, { "plugin_detected" => plugin }) do
      stub_class_method(Refinery, :route_for_model, ->(*) { "plugin_detected_path" }) do
        stub_class_method(RefineryRelay::SourceRegistry, :refinery_route_helpers, route_helpers) do
          source = RefineryRelay::SourceRegistry.known.find { |item| item.key == "plugin_detected" }

          assert source
          assert_equal "Refinery::PluginDetected::PluginDetected", source.model_name
          assert_equal :name, source.title
          assert_equal [ :description ], source.fields
          assert_equal :all, source.scope
          assert_includes RefineryRelay::SourceRegistry.options.map(&:key), "plugin_detected"
          refute_includes RefineryRelay::SourceRegistry.keys, "plugin_detected_supporting_records"
        end
      end
    end
  end

  test "allows an unusual custom engine to declare its source explicitly" do
    RefineryRelay::SourceRegistry.register(
      plugin: "relay_detected",
      model: "Refinery::RelayDetected::Entry",
      title: :title,
      fields: [ :body ],
      scope: :live,
      route: :relay_detected_path
    )

    source = RefineryRelay::SourceRegistry.fetch("relay_detected")

    assert source
    assert_equal "Refinery::RelayDetected::Entry", source.model_name
    assert_includes RefineryRelay::SourceRegistry.available_keys, "relay_detected"
  end

  test "keeps unavailable explicit sources out of settings options" do
    RefineryRelay::SourceRegistry.register(
      key: "missing_engine",
      model: "Refinery::MissingEngine::Record"
    )

    refute_includes RefineryRelay::SourceRegistry.options.map(&:key), "missing_engine"
    assert_includes RefineryRelay::SourceRegistry.keys, "missing_engine"
  end
end
