# frozen_string_literal: true

require "test_helper"

class RefineryRelayAdminInterfaceTest < ActiveSupport::TestCase
  test "registers the Relay admin JavaScript with Refinery" do
    assert_includes ::Refinery::Core.javascripts, "refinery_relay/admin"
    assert ::Refinery::Core.config.stylesheets.any? { |stylesheet| stylesheet.path == "refinery_relay/admin" }
    assert_includes Rails.application.config.assets.precompile, "refinery_relay/admin.js"
    assert_includes Rails.application.config.assets.precompile, "refinery_relay/admin.css"
  end

  test "settings endpoint remains available to authenticated Refinery admins" do
    callback = RefineryRelay::Admin::SettingsController._process_action_callbacks.find do |candidate|
      candidate.kind == :before && candidate.filter == :restrict_controller
    end

    assert callback
    skip_filter = callback.instance_variable_get(:@unless).first
    assert_includes skip_filter.instance_variable_get(:@actions), "show"
  end

  test "makes the admin JavaScript available through the asset pipeline" do
    asset = Rails.application.assets.find_asset("refinery_relay/admin.js")

    assert asset
    assert_includes asset.source, "Styling"
    assert_includes asset.source, "all LLM Chat Pods on this website"
    assert_includes asset.source, "refinery-relay-chat__suggestion-list"
    assert_includes asset.source, '$(".previews").first'
    assert_includes asset.source, 'podExample.children("div").first'
    assert_includes asset.source, "Re-enable the LLM Chat Pod Example"
    assert_includes asset.source, "currentPodId"
  end

  test "makes the admin preview stylesheet available through the asset pipeline" do
    asset = Rails.application.assets.find_asset("refinery_relay/admin.css")

    assert asset
    assert_includes asset.source, ".refinery-relay-chat"
  end

  test "precompiles the standalone frontend chat JavaScript" do
    assert_includes Rails.application.config.assets.precompile, "refinery_relay/chat.js"
    assert Rails.application.assets.find_asset("refinery_relay/chat.js")
  end

  test "packages the frontend stylesheet through an engine entrypoint" do
    assert_includes Rails.application.config.assets.precompile, "refinery_relay/application.css"

    asset = Rails.application.assets.find_asset("refinery_relay/application.css")
    assert asset
    assert_includes asset.source, ".refinery-relay-chat"
    assert_includes asset.source, "font-size:0.9375rem"
    assert_includes asset.source, "font-weight:400"
  end
end
