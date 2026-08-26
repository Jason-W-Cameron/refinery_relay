# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodContractTest < ActiveSupport::TestCase
  PodItem = Struct.new(:title, :position, keyword_init: true)
  Pod = Struct.new(:system_name, :title, :pod_items, keyword_init: true)

  class PodItems < Array
    def order(attribute)
      sort_by(&attribute)
    end
  end

  test "recognizes the llm chat pod type" do
    assert RefineryRelay::PodContract.chat_pod?(build_pod)
    assert_not RefineryRelay::PodContract.chat_pod?(build_pod(system_name: "content"))
  end

  test "translates Refinery pod fields into chat content" do
    pod = build_pod(
      title: "Chat with Simon",
      pod_items: PodItems.new([
        PodItem.new(title: "Second question", position: 2),
        PodItem.new(title: "First question", position: 1),
        PodItem.new(title: "", position: 3)
      ])
    )

    assert_equal "Chat with Simon", RefineryRelay::PodContract.heading(pod)
    assert_equal [ "First question", "Second question" ], RefineryRelay::PodContract.suggested_questions(pod)
  end

  test "uses a safe copy default when the title is blank" do
    pod = build_pod(title: nil)

    assert_equal "Ask us a question", RefineryRelay::PodContract.heading(pod)
  end

  private

  def build_pod(**overrides)
    attributes = {
      system_name: "llm_chat",
      title: nil,
      pod_items: PodItems.new
    }.merge(overrides)

    Pod.new(**attributes)
  end
end
