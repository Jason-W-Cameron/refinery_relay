require "test_helper"

class RefineryRelayConfigurationTest < ActiveSupport::TestCase
  setup do
    RefineryRelay.reset_configuration!
  end

  teardown do
    RefineryRelay.reset_configuration!
  end

  test "loads Relay configuration from environment variables" do
    env = {
      "RELAY_SOURCE_TOKEN" => "source-token",
      "RELAY_PUBLIC_BASE_URL" => "https://refinery.example/",
      "RELAY_CHAT_BASE_URL" => "https://relay.example/",
      "RELAY_CHAT_TOKEN" => "chat-token",
      "RELAY_CHAT_TENANT_KEY" => "refinery-site",
      "RELAY_CHAT_OPEN_TIMEOUT_SECONDS" => "8",
      "RELAY_CHAT_READ_TIMEOUT_SECONDS" => "60"
    }

    configuration = RefineryRelay.configure_from_env!(env)

    assert_equal "source-token", configuration.source_token
    assert_equal "https://refinery.example", configuration.public_base_url
    assert_equal "https://relay.example", configuration.chat_base_url
    assert_equal "chat-token", configuration.chat_token
    assert_equal "refinery-site", configuration.chat_tenant_key
    assert_equal 8, configuration.chat_open_timeout_seconds
    assert_equal 60, configuration.chat_read_timeout_seconds
  end

  test "supports explicit configuration overrides" do
    RefineryRelay.configure do |configuration|
      configuration.chat_base_url = "https://override.example/"
    end

    assert_equal "https://override.example", RefineryRelay.configuration.chat_base_url
  end

  test "uses a generic Refinery tenant key by default" do
    configuration = RefineryRelay::Configuration.from_env({})

    assert_equal "refinery", configuration.chat_tenant_key
  end

  test "supports explicit Redis and Action Cable dependencies" do
    redis = Object.new
    broadcaster = Object.new

    RefineryRelay.configure do |config|
      config.redis = redis
      config.broadcaster = broadcaster
    end

    assert_same redis, RefineryRelay.configuration.redis
    assert_same broadcaster, RefineryRelay.configuration.broadcaster
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
