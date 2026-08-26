# frozen_string_literal: true

require "test_helper"

if defined?(ActionCable::Channel::TestCase)
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
else
  class RefineryRelayChatChannelTest < ActiveSupport::TestCase
    test "loads the Relay chat channel on Rails versions without channel test support" do
      assert RefineryRelay::RelayChatChannel < ActionCable::Channel::Base
    end
  end
end
