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

  test "loads Relay's script and renders the mount markup without pasted scripts" do
    widget_markup = '<script src="https://relay.example/niimble-relay-widget.js"></script><niimble-relay-chat relay-url="https://relay.example" widget-key="nrw_test"></niimble-relay-chat>'
    RefineryRelay::RelaySetting.create!(
      widget_markup:
    )

    render partial: "refinery/pods/shared/llm_chat_pod", locals: { pod: Pod.new(42, "llm_chat") }

    assert_select "script[src='https://relay.example/niimble-relay-widget.js'][defer]", count: 1
    assert_select "relay-llm-widget", count: 1 do
      assert_select "script", count: 0
      assert_select "niimble-relay-chat[relay-url='https://relay.example'][widget-key='nrw_test']", count: 1
    end
    assert_not_includes rendered, '<script src="https://relay.example/niimble-relay-widget.js"></script>'
  end
end
