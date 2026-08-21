# frozen_string_literal: true

module RefineryRelay
  class RelayChatChannel < ActionCable::Channel::Base
    def subscribed
      stream_from RefineryRelay::CreditAvailability.stream_name
    end
  end
end
