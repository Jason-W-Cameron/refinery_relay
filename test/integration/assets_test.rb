# frozen_string_literal: true

require "test_helper"

class RefineryRelayAssetsTest < ActionDispatch::IntegrationTest
  test "serves the compiled Relay browser assets" do
    javascript = Rails.application.assets.find_asset("refinery_relay/chat.js")
    stylesheet = Rails.application.assets.find_asset("refinery_relay/application.css")
    logo = Rails.application.assets.find_asset("refinery_relay/niimble-logo-light-tp.png")

    assert logo

    get "/assets/#{javascript.digest_path}"
    assert_response :success
    assert_includes response.body, "RefineryRelayChat"

    get "/assets/#{stylesheet.digest_path}"
    assert_response :success
    assert_includes response.body, ".refinery-relay-chat"
  end
end
