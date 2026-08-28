require "test_helper"

class RefineryRelayConfigurationTest < ActiveSupport::TestCase
  class FakeFaqSource
    def self.table_exists?
      true
    end

    def self.column_names
      %w[id question answer]
    end
  end

  setup do
    RefineryRelay::SourceRegistry.register(
      key: "faqs",
      model: FakeFaqSource.name,
      title: :question,
      fields: [ :answer ],
      scope: :live,
      route: :faq_path
    )
    RefineryRelay::RelaySetting.delete_all
  end

  teardown do
    RefineryRelay::RelaySetting.delete_all
    registered = RefineryRelay::SourceRegistry.instance_variable_get(:@registered_sources)
    registered.delete("faqs") if registered
    RefineryRelay::SourceRegistry.reset!
  end

  test "loads Relay configuration from the saved Relay settings" do
    RefineryRelay::RelaySetting.create!(
      source_token: "source-token",
      public_base_url: "https://refinery.example/",
      chat_base_url: "https://relay.example/",
      chat_token: "chat-token",
      chat_tenant_key: "refinery-site",
      source_types: %w[pages faqs],
      chat_open_timeout_seconds: 8,
      chat_read_timeout_seconds: 60,
      redis_url: "redis://127.0.0.1:6379/0"
    )

    configuration = RefineryRelay.configuration

    assert_equal "source-token", configuration.source_token
    assert_equal "https://refinery.example", configuration.public_base_url
    assert_equal "https://relay.example", configuration.chat_base_url
    assert_equal "chat-token", configuration.chat_token
    assert_equal "refinery-site", configuration.chat_tenant_key
    assert_equal %w[pages faqs], configuration.source_types
    assert_equal 8, configuration.chat_open_timeout_seconds
    assert_equal 60, configuration.chat_read_timeout_seconds
    assert_equal "redis://127.0.0.1:6379/0", configuration.redis_url
  end

  test "reads changed settings without restarting the application" do
    setting = RefineryRelay::RelaySetting.create!(chat_base_url: "https://first.example")
    assert_equal "https://first.example", RefineryRelay.configuration.chat_base_url

    setting.update!(chat_base_url: "https://second.example")
    assert_equal "https://second.example", RefineryRelay.configuration.chat_base_url
  end

  test "does not expose an RSS feed URL setting" do
    configuration = RefineryRelay::Configuration.new

    refute_respond_to configuration, :rss_feed_url
  end

  test "uses a generic Refinery tenant key by default" do
    configuration = RefineryRelay.configuration

    assert_equal "refinery", configuration.chat_tenant_key
  end

  test "uses safe defaults for invalid numeric configuration" do
    configuration = RefineryRelay::Configuration.new(
      chat_open_timeout_seconds: "invalid",
      chat_read_timeout_seconds: 999
    )

    assert_equal 5, configuration.chat_open_timeout_seconds
    assert_equal 120, configuration.chat_read_timeout_seconds
  end
end
