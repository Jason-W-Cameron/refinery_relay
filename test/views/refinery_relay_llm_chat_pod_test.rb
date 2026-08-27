# frozen_string_literal: true

require "test_helper"

class RefineryRelayLlmChatPodTest < ActionView::TestCase
  Pod = Data.define(:id, :system_name)

  setup do
    RefineryRelay::RelaySetting.delete_all
  end

  teardown do
    RefineryRelay::RelaySetting.delete_all
  end

  test "renders only the widget mount element when no widget markup is configured" do
    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: Pod.new(42, "llm_chat") }

    assert_select "relay-llm-widget", count: 1
    assert_equal "<relay-llm-widget></relay-llm-widget>", rendered.strip
  end

  test "renders the trusted widget markup from Relay settings in place of the pod" do
    widget_markup = '<style>.relay-widget { display: block; }</style><script>window.relayWidgetReady = true;</script><div class="relay-widget" data-relay-widget="chat">Ready</div>'
    RefineryRelay::RelaySetting.create!(
      widget_markup:
    )

    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: Pod.new(42, "llm_chat") }

    assert_select "relay-llm-widget", count: 1 do
      assert_select "style", text: ".relay-widget { display: block; }"
      assert_select "script", text: "window.relayWidgetReady = true;"
      assert_select "div.relay-widget[data-relay-widget='chat']", text: "Ready"
    end
    assert_includes rendered, widget_markup
    assert_not_includes rendered, "&lt;script&gt;"
  end
end
