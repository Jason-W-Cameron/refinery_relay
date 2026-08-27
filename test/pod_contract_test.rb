# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodContractTest < ActiveSupport::TestCase
  Pod = Data.define(:system_name)

  test "recognizes the llm chat pod type" do
    assert RefineryRelay::PodContract.chat_pod?(build_pod)
    assert_not RefineryRelay::PodContract.chat_pod?(build_pod(system_name: "content"))
  end

  test "exposes the stable retained pod type" do
    assert_equal "llm_chat", RefineryRelay::PodContract::POD_TYPE
  end

  private

  def build_pod(**overrides)
    attributes = {
      system_name: "llm_chat"
    }.merge(overrides)

    Pod.new(**attributes)
  end
end
