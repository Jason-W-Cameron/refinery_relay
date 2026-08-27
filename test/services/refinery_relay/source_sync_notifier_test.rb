# frozen_string_literal: true

require "test_helper"
require "net/http"

class RefineryRelaySourceSyncNotifierTest < ActiveSupport::TestCase
  setup do
    RefineryRelay::RelaySetting.delete_all
    RefineryRelay::RelaySetting.create!(
      chat_base_url: "https://relay.example/",
      sync_token: "sync-token",
      sync_source_id: "source uuid"
    )
  end

  teardown do
    RefineryRelay::RelaySetting.delete_all
  end

  test "notifies Relay with the sync credential after source content changes" do
    request = nil
    response = Net::HTTPAccepted.new("1.1", "202", "Accepted")
    client = Object.new
    client.define_singleton_method(:request) do |value|
      request = value
      response
    end

    stub_class_method(Net::HTTP, :start, ->(*_arguments, &block) { block.call(client) }) do
      assert RefineryRelay::SourceSyncNotifier.call!
    end

    assert_equal "/api/v1/sources/source+uuid/sync", request.path
    assert_equal "Bearer sync-token", request["Authorization"]
    assert_equal "application/json", request["Accept"]
  end

  test "does not queue a notification until Relay source-sync settings are present" do
    RefineryRelay::RelaySetting.current.update!(sync_token: nil)

    refute RefineryRelay::SourceSyncNotifier.enqueue
  end
end
