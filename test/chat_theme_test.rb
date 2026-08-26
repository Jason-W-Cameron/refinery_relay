# frozen_string_literal: true

require "test_helper"

class RefineryRelayChatThemeTest < ActiveSupport::TestCase
  setup do
    RefineryRelay.reset_configuration!
  end

  teardown do
    RefineryRelay::SiteSettings.delete_all if ActiveRecord::Base.connection.data_source_exists?("refinery_relay_site_settings")
    RefineryRelay.reset_configuration!
  end

  test "uses the five minimal site theme defaults" do
    theme = RefineryRelay::ChatTheme.current

    assert_equal "#fbbf24", theme.accent_color
    assert_equal "#101010", theme.background_color
    assert_equal "#181818", theme.surface_color
    assert_equal "#f5f5f5", theme.text_color
    assert_equal "#dedede", theme.assistant_response_color
  end

  test "derives supporting colors from the five site values" do
    RefineryRelay.configure do |config|
      config.chat_accent_color = "#2563eb"
      config.chat_background_color = "#ffffff"
      config.chat_surface_color = "#f8fafc"
      config.chat_text_color = "#111827"
      config.chat_assistant_response_color = "#374151"
    end

    theme = RefineryRelay::ChatTheme.current

    assert_includes theme.css_variables, "--refinery-relay-accent: #2563eb"
    assert_includes theme.css_variables, "--refinery-relay-accent-soft: rgba(37, 99, 235, 0.09)"
    assert_includes theme.css_variables, "--refinery-relay-accent-text: #ffffff"
    assert_includes theme.css_variables, "--refinery-relay-background: #ffffff"
    assert_includes theme.css_variables, "--refinery-relay-assistant-response: #374151"
    assert_includes theme.css_variables, "--refinery-relay-surface-raised-hover: rgba(17, 24, 39, 0.12)"
    assert_includes theme.css_variables, "--refinery-relay-text-muted: rgba(17, 24, 39, 0.68)"
    assert_includes theme.css_variables, "--refinery-relay-danger-soft: rgba(185, 28, 28, 0.11)"
  end

  test "falls back to defaults for invalid configured colors" do
    RefineryRelay.configure do |config|
      config.chat_accent_color = "red"
    end

    assert_equal "#fbbf24", RefineryRelay::ChatTheme.current.accent_color
  end

  test "uses saved site-wide admin colors" do
    RefineryRelay::SiteSettings.save_colors(
      accent_color: "#2563eb",
      background_color: "#ffffff",
      surface_color: "#f8fafc",
      text_color: "#111827",
      assistant_response_color: "#374151"
    )

    assert_equal "#2563eb", RefineryRelay::ChatTheme.current.accent_color
    assert_equal "#ffffff", RefineryRelay::ChatTheme.current.background_color
    assert_equal "#374151", RefineryRelay::ChatTheme.current.assistant_response_color
  end
end
