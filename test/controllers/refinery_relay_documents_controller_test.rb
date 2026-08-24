# frozen_string_literal: true

require "test_helper"

class RefineryRelayDocumentsControllerTest < ActionDispatch::IntegrationTest
  DOCUMENTS_PATH = "/refinery_relay/api/relay/documents"

  setup do
    RefineryRelay.configure do |config|
      config.source_token = "source-token"
      config.rss_feed_url = "https://refinery.example/nlweb/rss"
    end
  end

  teardown do
    RefineryRelay.reset_configuration!
  end

  test "the gem automatically provides an authenticated documents endpoint" do
    payload = { "documents" => [], "cursor" => "checkpoint", "next_cursor" => nil }

    stub_class_method(RefineryRelay::RssDocumentFeed, :call, ->(**) { payload }) do
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

  test "stays unavailable until the RSS feed is configured" do
    RefineryRelay.configuration.rss_feed_url = ""

    get DOCUMENTS_PATH, headers: { "Authorization" => "Bearer source-token" }

    assert_response :service_unavailable
    assert_equal "source_not_configured", response.parsed_body.fetch("error")
  end

  test "returns a controlled error when the RSS feed cannot be fetched" do
    failure = ->(**) { raise RefineryRelay::RssDocumentFeed::Error, "feed timed out" }

    stub_class_method(RefineryRelay::RssDocumentFeed, :call, failure) do
      get DOCUMENTS_PATH, headers: { "Authorization" => "Bearer source-token" }
    end

    assert_response :bad_gateway
    assert_equal "rss_feed_unavailable", response.parsed_body.fetch("error")
  end
end
