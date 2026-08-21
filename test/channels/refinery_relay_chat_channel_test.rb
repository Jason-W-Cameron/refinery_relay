# frozen_string_literal: true

require "test_helper"

class RefineryRelayChatChannelTest < ActionCable::Channel::TestCase
  tests RefineryRelay::RelayChatChannel

  test "streams credit availability events for the configured tenant" do
    RefineryRelay.configure { |config| config.chat_tenant_key = "refinery-site" }

    subscribe

    assert_has_stream RefineryRelay::CreditAvailability.stream_name
  ensure
    RefineryRelay.reset_configuration!
  end
end
