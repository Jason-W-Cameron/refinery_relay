# frozen_string_literal: true

require "test_helper"

class RefineryRelayDocumentsControllerTest < ActionDispatch::IntegrationTest
  DOCUMENTS_PATH = "/refinery_relay/api/relay/documents"

  setup do
    RefineryRelay::RelaySetting.delete_all
    RefineryRelay::RelaySetting.create!(
      source_token: "source-token",
      public_base_url: "https://refinery.example/"
    )
  end

  teardown do
    RefineryRelay::RelaySetting.delete_all
  end

  test "the gem automatically provides an authenticated direct documents endpoint" do
    payload = { "documents" => [], "cursor" => "checkpoint", "next_cursor" => nil }
    test_case = self

    feed = ->(cursor:, public_base_url:) do
      test_case.assert_nil cursor
      test_case.assert_equal "https://refinery.example", public_base_url
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
    RefineryRelay::RelaySetting.current.update!(source_token: "")

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

  test "builds an absolute local base URL when no public URL is configured" do
    RefineryRelay::RelaySetting.current.update!(public_base_url: "")
    test_case = self
    feed = ->(cursor:, public_base_url:) do
      test_case.assert_nil cursor
      test_case.assert_equal "http://localhost:3002", public_base_url
      { "documents" => [], "cursor" => "checkpoint" }
    end

    stub_class_method(RefineryRelay::DocumentFeed, :call, feed) do
      get DOCUMENTS_PATH,
          headers: { "Authorization" => "Bearer source-token", "Host" => "localhost:3002" }
    end

    assert_response :success
  end
end
