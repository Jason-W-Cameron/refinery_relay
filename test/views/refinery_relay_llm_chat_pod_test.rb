# frozen_string_literal: true

require "test_helper"

class RefineryRelayLlmChatPodTest < ActionView::TestCase
  PodItem = Data.define(:title, :position)
  Pod = Data.define(:id, :system_name, :title, :subtitle, :body, :pod_items)

  class PodItems < Array
    def order(attribute)
      sort_by(&attribute)
    end
  end

  test "renders configured chat content and ordered suggested questions" do
    pod = build_pod(
      title: "Ask Simon",
      subtitle: "What would you like to know?",
      body: "<p>Answers come from this website.</p><script>alert('unsafe')</script>",
      pod_items: PodItems.new([
        PodItem.new(title: "Second question", position: 2),
        PodItem.new(title: "First question", position: 1),
        PodItem.new(title: "", position: 3)
      ])
    )

    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: pod }

    assert_select "section#refinery-relay-chat-42[data-refinery-relay-chat]" do
      assert_select "h2", text: "Ask Simon", count: 2
      assert_select ".refinery-relay-chat__welcome", text: "What would you like to know?"
      assert_select ".refinery-relay-chat__introduction p", text: "Answers come from this website."
      assert_select "script", count: 0
      assert_select "button[data-refinery-relay-suggestion]", 2
      assert_select "button[data-refinery-relay-suggestion]:nth-of-type(1)", text: "First question"
      assert_select "button[data-refinery-relay-suggestion]:nth-of-type(2)", text: "Second question"
    end
  end

  test "renders stable endpoints, forms, and accessible live regions" do
    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: build_pod }

    assert_select "[data-refinery-relay-chat][data-chat-url='/refinery_relay/api/relay/chat']"
    assert_select "[data-refinery-relay-chat][data-availability-url='/refinery_relay/api/relay/chat/availability']"
    assert_select "form[data-refinery-relay-form]", 2
    assert_select "textarea[data-refinery-relay-input][maxlength='4000']", 2
    assert_select "[data-refinery-relay-messages][role='log'][aria-live='polite']"
    assert_select "[data-refinery-relay-error][role='alert'][hidden]"
    assert_select "[data-refinery-relay-unavailable][role='status'][hidden]"
  end

  test "leaves globally installed frontend assets out of the Pod partial" do
    render inline: <<~ERB, locals: { first_pod: build_pod, second_pod: build_pod(id: 43) }
      <%= render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: first_pod } %>
      <%= render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: second_pod } %>
    ERB

    assert_select "link[href*='refinery_relay']", count: 0
    assert_select "script[src*='refinery_relay']", count: 0
    assert_equal 2, css_select("[data-refinery-relay-chat]").length
  end

  test "uses contract defaults and omits an empty suggestions section" do
    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: build_pod(title: nil, subtitle: nil) }

    assert_select "h2", text: "Ask us a question", count: 2
    assert_select ".refinery-relay-chat__welcome", text: "How can I help?"
    assert_select ".refinery-relay-chat__suggestions", count: 0
  end

  private

  def build_pod(**overrides)
    attributes = {
      id: 42,
      system_name: "llm_chat",
      title: "Ask us a question",
      subtitle: "How can I help?",
      body: nil,
      pod_items: PodItems.new
    }.merge(overrides)

    Pod.new(**attributes)
  end
end
