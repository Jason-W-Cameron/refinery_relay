# frozen_string_literal: true

require "test_helper"

class RefineryRelayDocumentsControllerTest < ActionDispatch::IntegrationTest
  DOCUMENTS_PATH = "/refinery_relay/api/relay/documents"

  setup do
    RefineryRelay.configure do |config|
      config.source_token = "source-token"
      config.public_base_url = "https://refinery.example/"
    end
  end

  teardown do
    RefineryRelay.reset_configuration!
  end

  test "the gem automatically provides an authenticated direct documents endpoint" do
    payload = { "documents" => [], "cursor" => "checkpoint", "next_cursor" => nil }

    feed = ->(cursor:, public_base_url:) do
      assert_nil cursor
      assert_equal "https://refinery.example", public_base_url
      payload
    end

    stub_class_method(RefineryRelay::DocumentFeed, :call, feed) do
      get DOCUMENTS_PATH, headers: { "Authorization" => "Bearer source-token" }
    end

    assert_response :success
    assert_equal payload, response.parsed_body
  end

  test "rejects requests without the source token" do
    get DOCUMENTS_PATH

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.fetch("error")
  end

  test "stays unavailable until the source token is configured" do
    RefineryRelay.configuration.source_token = ""

    get DOCUMENTS_PATH, headers: { "Authorization" => "Bearer source-token" }

    assert_response :service_unavailable
    assert_equal "source_not_configured", response.parsed_body.fetch("error")
  end

  test "rejects an invalid direct-feed cursor" do
    failure = ->(**) { raise RefineryRelay::DocumentFeed::InvalidCursor }

    stub_class_method(RefineryRelay::DocumentFeed, :call, failure) do
      get DOCUMENTS_PATH, headers: { "Authorization" => "Bearer source-token" }
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_cursor", response.parsed_body.fetch("error")
  end
end
