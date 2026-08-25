# frozen_string_literal: true

require "test_helper"

class RefineryRelayLlmChatPodTest < ActionView::TestCase
  PodItem = Data.define(:title, :position)
  Pod = Data.define(:id, :system_name, :title, :pod_items)

  class PodItems < Array
    def order(attribute)
      sort_by(&attribute)
    end
  end

  test "renders configured chat content and ordered suggested questions" do
    pod = build_pod(
      title: "Ask Simon",
      pod_items: PodItems.new([
        PodItem.new(title: "Second question", position: 2),
        PodItem.new(title: "First question", position: 1),
        PodItem.new(title: "", position: 3)
      ])
    )

    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: pod }

    assert_select "section#refinery-relay-chat-42[data-refinery-relay-chat]" do
      assert_select ".refinery-relay-chat__eyebrow", text: "Niimble Relay"
      assert_select ".refinery-relay-chat__initial-aside .refinery-relay-chat__footer-logo[alt='Niimble']", count: 1
      assert_select ".refinery-relay-chat__conversation-footer .refinery-relay-chat__footer-logo[alt='Niimble']", count: 1
      assert_select "h2", text: "Ask Simon", count: 2
      assert_select ".refinery-relay-chat__initial-aside > .refinery-relay-chat__information-card", count: 1
      assert_select ".refinery-relay-chat__initial-aside > .refinery-relay-chat__footer", count: 1
      assert_select ".refinery-relay-chat__initial-aside .refinery-relay-chat__attribution", count: 1
      assert_select ".refinery-relay-chat__initial-aside .refinery-relay-chat__attribution > span", text: "Niimble Relay developed by", count: 1
      assert_select ".refinery-relay-chat__initial-aside .refinery-relay-chat__attribution > a[href='https://www.niimble.io'] img[alt='Niimble']", count: 1
      assert_select ".refinery-relay-chat__initial-aside .refinery-relay-chat__attribution > a > span", count: 0
      assert_select ".refinery-relay-chat__reset svg", count: 1
      assert_select ".refinery-relay-chat__sources-heading-row", count: 1
      assert_select ".refinery-relay-chat__empty-sources-icon", text: "✦", count: 1
      assert_select ".refinery-relay-chat__prompt-icon span", count: 2
      assert_select ".refinery-relay-chat__send-icon", count: 2
      assert_select ".refinery-relay-chat__loading-icon", count: 2
      assert_select ".refinery-relay-chat__form--initial .refinery-relay-chat__send", count: 1
      assert_select ".refinery-relay-chat__form--conversation .refinery-relay-chat__send--conversation", count: 1
      assert_select ".refinery-relay-chat__form--conversation .refinery-relay-chat__send-icon path[d='M5 12h14']", count: 1
      assert_select ".refinery-relay-chat__suggestions-heading", count: 0
      assert_select "button[data-refinery-relay-suggestion]", 2
      assert_select "form.refinery-relay-chat__form--initial > .refinery-relay-chat__suggestions", count: 1
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
    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: build_pod(title: nil) }

    assert_select "h2", text: "Ask us a question", count: 2
    assert_select ".refinery-relay-chat__suggestions", count: 0
  end

  test "uses the configured prompt placeholder" do
    RefineryRelay.configure do |configuration|
      configuration.chat_prompt_placeholder = "Ask Comrades-GPT something"
    end

    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: build_pod }

    assert_select "textarea[data-refinery-relay-input][placeholder='Ask Comrades-GPT something']", count: 1
  ensure
    RefineryRelay.reset_configuration!
  end

  test "uses prompt placeholder and information card copy saved for the pod" do
    RefineryRelay::PodSettings.create!(
      pod_id: 42,
      prompt_placeholder: "Ask SimonSays anything",
      information_text: "A custom description for this assistant.",
      footer_logo_url: "https://example.test/custom-logo.png",
      footer_logo_link: "https://example.test/about"
    )

    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: build_pod }

    assert_select "textarea[data-refinery-relay-input][placeholder='Ask SimonSays anything']", count: 1
    assert_select ".refinery-relay-chat__information-card p", text: "A custom description for this assistant.", count: 1
    assert_select ".refinery-relay-chat__initial-aside .refinery-relay-chat__logo-link[href='https://example.test/about'] > img[src='https://example.test/custom-logo.png']", count: 1
    assert_select ".refinery-relay-chat__conversation-footer .refinery-relay-chat__logo-link[href='https://example.test/about'] > img[src='https://example.test/custom-logo.png']", count: 1
  end

  private

  def build_pod(**overrides)
    attributes = {
      id: 42,
      system_name: "llm_chat",
      title: "Ask us a question",
      pod_items: PodItems.new
    }.merge(overrides)

    Pod.new(**attributes)
  end
end
