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
      Column = Struct.new(:name, :type)

      def self.table_exists?
        true
      end

      def self.all
        self
      end

      def self.column_names
        %w[id name description public_notes api_token created_at updated_at]
      end

      def self.columns
        [
          Column.new("id", :integer),
          Column.new("name", :string),
          Column.new("description", :text),
          Column.new("public_notes", :text),
          Column.new("api_token", :string),
          Column.new("created_at", :datetime),
          Column.new("updated_at", :datetime)
        ]
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

  module VirtualContent
    class Article
      Column = Struct.new(:name, :type)

      def self.columns
        [ Column.new("title", :string), Column.new("source_url", :string) ]
      end

      def body; end
      def custom_teaser; end
      def tag_list; end
    end
  end
end

class RefineryRelaySourceRegistryTest < ActiveSupport::TestCase
  Plugin = Struct.new(:name, :url, :title)

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

  test "rediscovers engines registered after an early lookup" do
    plugin = Plugin.new("plugin_detected", "/refinery/plugin_detected", "Plugin detected")

    stub_class_method(Refinery::Plugins, :registered, []) do
      assert_equal [ "pages" ], RefineryRelay::SourceRegistry.keys
    end

    stub_class_method(Refinery::Plugins, :registered, { "plugin_detected" => plugin }) do
      stub_class_method(Refinery, :route_for_model, ->(*) { "plugin_detected_path" }) do
        route_helpers = Object.new
        route_helpers.define_singleton_method(:plugin_detected_path) { |record = nil| record ? "/plugin-detected/1" : "/plugin-detected" }
        stub_class_method(RefineryRelay::SourceRegistry, :refinery_route_helpers, route_helpers) do
          assert_includes RefineryRelay::SourceRegistry.keys, "plugin_detected"
        end
      end
    end
  end

  test "discovers one conventional source from Refinery's plugin registry" do
    plugin = Plugin.new(
      "plugin_detected",
      "/refinery/plugin_detected",
      "Translation missing: en.refinery.plugins.plugin_detected.title"
    )
    route_helpers = Object.new
    route_helpers.define_singleton_method(:plugin_detected_path) { |record = nil| record ? "/plugin-detected/1" : "/plugin-detected" }
    endpoint = RefineryRelay::PublicEndpointValidator::Result.new(available: true, path: "/plugin-detected")

    stub_class_method(Refinery::Plugins, :registered, { "plugin_detected" => plugin }) do
      stub_class_method(Refinery, :route_for_model, ->(*) { "plugin_detected_path" }) do
        stub_class_method(RefineryRelay::SourceRegistry, :refinery_route_helpers, route_helpers) do
          stub_class_method(RefineryRelay::PublicEndpointValidator, :call, endpoint) do
            source = RefineryRelay::SourceRegistry.known.find { |item| item.key == "plugin_detected" }

            assert source
            assert_equal "Plugin detected", source.label
            assert_equal "Plugin detected content", source.description
            assert_equal "Refinery::PluginDetected::PluginDetected", source.model_name
            assert_equal :name, source.title
            assert_equal [ :description ], source.fields
            assert_equal %i[description public_notes], source.field_options
            assert_equal :record_or_collection, source.citation_strategy
            assert_equal "/plugin-detected", source.collection_path
            assert_equal :all, source.scope
            assert_includes RefineryRelay::SourceRegistry.options.map(&:key), "plugin_detected"
            refute_includes RefineryRelay::SourceRegistry.keys, "plugin_detected_supporting_records"
          end
        end
      end
    end
  end

  test "uses a plugin root route as a collection-path fallback" do
    route_helpers = Object.new
    route_helpers.define_singleton_method(:blog_root_path) { "/blog" }

    stub_class_method(RefineryRelay::SourceRegistry, :refinery_route_helpers, route_helpers) do
      assert_equal "/blog", RefineryRelay::SourceRegistry.send(:public_collection_path_for, "blog", "blog_posts")
    end
  end

  test "offers translated and tag-list virtual content fields" do
    fields = RefineryRelay::SourceRegistry.send(
      :selectable_fields_for,
      Refinery::VirtualContent::Article,
      "title"
    )

    assert_includes fields, "body"
    assert_includes fields, "custom_teaser"
    assert_includes fields, "tag_list"
    refute_includes fields, "title"
  end

  test "keeps a source with a declared public route selectable" do
    RefineryRelay::SourceRegistry.register(
      key: "relay_detected",
      model: "Refinery::RelayDetected::Entry",
      title: :title,
      fields: [ :body ],
      field_options: [ :body ],
      path: "/relay-detected",
      scope: :live,
      route: :relay_detected_path
    )
    route_helpers = Object.new
    route_helpers.define_singleton_method(:relay_detected_path) { |_record| "/relay-detected/1" }
    stub_class_method(RefineryRelay::SourceRegistry, :refinery_route_helpers, route_helpers) do
      status = RefineryRelay::SourceRegistry.source_status(RefineryRelay::SourceRegistry.fetch("relay_detected"), host: "sit.example", protocol: "https")

      assert_predicate status, :ingestible?
      assert_includes RefineryRelay::SourceRegistry.options.map(&:key), "relay_detected"
    end
  end

  test "allows an unusual custom engine to declare its source explicitly" do
    RefineryRelay::SourceRegistry.register(
      plugin: "relay_detected",
      model: "Refinery::RelayDetected::Entry",
      title: :title,
      fields: [ :body ],
      field_options: [ :body, :summary ],
      scope: :live,
      route: :relay_detected_path
    )

    source = RefineryRelay::SourceRegistry.fetch("relay_detected")

    assert source
    assert_equal "Refinery::RelayDetected::Entry", source.model_name
    assert_equal %i[body summary], source.field_options
    assert_includes RefineryRelay::SourceRegistry.available_keys, "relay_detected"
  end

  test "normalizes selected fields against each source's declared options" do
    RefineryRelay::SourceRegistry.register(
      plugin: "relay_detected",
      model: "Refinery::RelayDetected::Entry",
      title: :title,
      fields: [ :body ],
      field_options: [ :body, :summary ]
    )

    mappings = RefineryRelay::SourceRegistry.normalize_field_mappings(
      "relay_detected" => [ "summary", "body", "summary", "unknown" ],
      "missing_source" => [ "body" ]
    )

    assert_equal({ "relay_detected" => %w[summary body] }, mappings)
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
