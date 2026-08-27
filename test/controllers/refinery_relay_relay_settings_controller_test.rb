# frozen_string_literal: true

require "test_helper"

class RefineryRelayRelaySettingsControllerTest < ActionDispatch::IntegrationTest
  SETTINGS_PATH = "/refinery/relay_settings"

  setup do
    RefineryRelay::RelaySetting.delete_all
  end

  teardown do
    RefineryRelay::RelaySetting.delete_all
  end

  test "shows the single Relay settings page in the Refinery admin" do
    get SETTINGS_PATH

    assert_response :success
    assert_select "h2", "Relay Settings"
    assert_select "input[value='pages']"
    assert_select "input[value='faqs']"
    assert_select "input[type='hidden'][name='relay_setting[source_types][]'][value='']"
    assert_select "code#relay-feed-endpoint", /refinery_relay\/api\/relay\/documents/
    assert_select "button[data-rr-copy='relay-feed-endpoint']", "Copy endpoint"
    assert_select "form button", "Generate bearer token"
    assert_select "textarea[name='relay_setting[widget_markup]']"
    assert_select "input[name='relay_setting[redis_url]']", count: 0
    assert_select "input[name='relay_setting[sync_token]']", count: 0
    assert_select "input[name='relay_setting[chat_base_url]']", count: 0
    assert_select "input[name='relay_setting[chat_token]']", count: 0
    assert_select "input[name='relay_setting[public_base_url]']", count: 0
    assert_equal "Relay Settings", Refinery::Plugins.registered["relay_settings"].title
  end

  test "saves source types and widget markup without exposing chat credentials" do
    setting = RefineryRelay::RelaySetting.create!(source_token: "existing-source-token")

    patch SETTINGS_PATH, params: {
      relay_setting: {
        source_types: [ "pages", "faqs", "not-a-source" ],
        widget_markup: '<script src="https://relay.example/widget.js"></script><div data-relay-widget></div>'
      }
    }

    assert_redirected_to SETTINGS_PATH
    setting.reload
    assert_equal "existing-source-token", setting.source_token
    assert_equal %w[pages faqs], setting.source_types
    assert_equal '<script src="https://relay.example/widget.js"></script><div data-relay-widget></div>', setting.widget_markup
  end

  test "allows all sources to be disabled" do
    patch SETTINGS_PATH, params: { relay_setting: { source_types: [] } }

    assert_redirected_to SETTINGS_PATH
    assert_equal [], RefineryRelay::RelaySetting.current.source_types
  end

  test "generates a bearer token and displays it once for copying" do
    post "/refinery/relay_settings/generate_bearer_token"

    assert_redirected_to "#{SETTINGS_PATH}#relay-generated-token-panel"
    token = RefineryRelay::RelaySetting.current.source_token
    assert_predicate token, :present?

    follow_redirect!
    assert_select "#relay-generated-token-panel"
    assert_select "#relay-generated-token[value='#{token}']"
    assert_select "button[data-rr-copy='relay-generated-token']", "Copy token"

    get SETTINGS_PATH
    assert_select "#relay-generated-token-panel", count: 0
  end
end
