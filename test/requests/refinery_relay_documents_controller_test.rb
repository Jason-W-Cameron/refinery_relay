# frozen_string_literal: true

require "test_helper"

class RefineryRelayDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_source_token = RefineryRelay.configuration.source_token
    RefineryRelay.configuration.source_token = "test-source-token"
  end

  teardown do
    RefineryRelay.configuration.source_token = @previous_source_token
  end

  test "rejects document feed requests without the source token" do
    get "/refinery_relay/api/relay/documents"

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.fetch("error")
  end

  test "rejects invalid cursors after authenticating the source" do
    token = RefineryRelay.configuration.source_token

    get "/refinery_relay/api/relay/documents",
        params: { cursor: "not-a-valid-cursor" },
        headers: { "Authorization" => "Bearer #{token}" }

    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", response.parsed_body.fetch("error")
  end
end
