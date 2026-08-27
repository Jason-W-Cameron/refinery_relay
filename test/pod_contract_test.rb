# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodContractTest < ActiveSupport::TestCase
  Pod = Data.define(:system_name)

  test "recognizes the Relay Chat pod type" do
    assert RefineryRelay::PodContract.chat_pod?(build_pod)
    assert_not RefineryRelay::PodContract.chat_pod?(build_pod(system_name: "content"))
  end

  test "exposes Relay Chat as the canonical pod type" do
    assert_equal "relay_chat", RefineryRelay::PodContract::POD_TYPE
  end

  test "does not recognize the retired pod type" do
    assert_not RefineryRelay::PodContract.chat_pod?(build_pod(system_name: "llm_chat"))
  end

  private

  def build_pod(**overrides)
    attributes = {
      system_name: "relay_chat"
    }.merge(overrides)

    Pod.new(**attributes)
  end
end
