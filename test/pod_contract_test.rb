# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodContractTest < ActiveSupport::TestCase
  PodItem = Data.define(:title, :position)
  Pod = Data.define(:system_name, :title, :subtitle, :body, :pod_items)

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
      subtitle: "What would you like to know?",
      body: "Answers are based on this website.",
      pod_items: PodItems.new([
        PodItem.new(title: "Second question", position: 2),
        PodItem.new(title: "First question", position: 1),
        PodItem.new(title: "", position: 3)
      ])
    )

    assert_equal "Chat with Simon", RefineryRelay::PodContract.heading(pod)
    assert_equal "What would you like to know?", RefineryRelay::PodContract.welcome_message(pod)
    assert_equal "Answers are based on this website.", RefineryRelay::PodContract.intro_content(pod)
    assert_equal [ "First question", "Second question" ], RefineryRelay::PodContract.suggested_questions(pod)
  end

  test "uses safe copy defaults when optional fields are blank" do
    pod = build_pod(title: nil, subtitle: "")

    assert_equal "Ask us a question", RefineryRelay::PodContract.heading(pod)
    assert_equal "How can I help?", RefineryRelay::PodContract.welcome_message(pod)
  end

  private

  def build_pod(**overrides)
    attributes = {
      system_name: "llm_chat",
      title: nil,
      subtitle: nil,
      body: nil,
      pod_items: PodItems.new
    }.merge(overrides)

    Pod.new(**attributes)
  end
end
