# frozen_string_literal: true

require "test_helper"

class RefineryRelayAdminInterfaceTest < ActiveSupport::TestCase
  test "registers the Relay admin JavaScript with Refinery" do
    assert_includes ::Refinery::Core.javascripts, "refinery_relay/admin"
    assert_includes Rails.application.config.assets.precompile, "refinery_relay/admin.js"
  end

  test "makes the admin JavaScript available through the asset pipeline" do
    assert Rails.application.assets.find_asset("refinery_relay/admin.js")
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
  end
end
