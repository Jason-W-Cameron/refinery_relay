# frozen_string_literal: true

require "application_system_test_case"
require "support/refinery_pods_test_models"
require "support/redis_test_server"
require "support/relay_stub_server"

class RefineryRelayChatSystemTest < ApplicationSystemTestCase
  include RedisTestServer

  setup do
    RefineryPodsTestSchema.install!
    RefineryRelay::PodRegistration.install!(pod_class: Refinery::Pods::Pod)
    @redis = start_test_redis
    @redis.flushdb
    @relay = RelayStubServer.new.start
    configure_relay
    @pod = create_chat_pod
  end

  teardown do
    @relay&.stop
    stop_test_redis
    RefineryRelay.reset_configuration!
  end

  test "persisted Refinery Pod submits chat and renders citations before reset" do
    visit relay_test_path(@pod)
    wait_for_chat_ready

    assert_text "Ask the test site"
    assert_text "What would you like to know?"
    assert_button "What information is published?"

    fill_in "Ask a question", with: "What does Relay know?"
    within "[data-refinery-relay-view='initial']" do
      find("[data-refinery-relay-send]").click
    end

    assert_text "What does Relay know?"
    assert_text "Relay can answer from the published website"
    assert_link "Published information", href: "#{@relay.base_url}/source"
    assert_text "1 reference"

    request = next_chat_request
    assert_equal "POST", request.fetch(:method)
    assert_equal "/api/v1/chat/messages", request.fetch(:path)
    assert_equal "What does Relay know?", request.dig(:body, "message")
    assert_equal "web", request.dig(:body, "context", "interface")

    click_button "Start over"
    assert_field "Ask a question"
    assert_no_text "Relay can answer from the published website"
  end

  test "real Redis state reaches the browser through Action Cable" do
    visit relay_test_path(@pod)
    wait_for_chat_ready
    assert_field "Ask a question"

    RefineryRelay::CreditAvailability.mark_unavailable!(resets_at: 2.minutes.from_now.iso8601)

    assert_text "Chat is temporarily unavailable", wait: 8
    assert_equal false, RefineryRelay::CreditAvailability.available?
  end

  test "chat reconnects after a Swup content replacement" do
    visit relay_test_path(@pod)
    wait_for_chat_ready
    assert_field "Ask a question"

    page.execute_script <<~JAVASCRIPT
      var root = document.querySelector("[data-refinery-relay-chat]");
      document.dispatchEvent(new CustomEvent("swup:willReplaceContent"));
      var replacement = root.cloneNode(true);
      root.parentNode.replaceChild(replacement, root);
      document.dispatchEvent(new CustomEvent("swup:contentReplaced"));
    JAVASCRIPT
    wait_for_chat_ready

    fill_in "Ask a question", with: "Does Swup still work?"
    within "[data-refinery-relay-view='initial']" do
      find("[data-refinery-relay-send]").click
    end

    assert_text "Does Swup still work?"
    assert_text "Relay can answer from the published website"
  end

  private

  def wait_for_chat_ready
    assert_selector(
      "[data-refinery-relay-chat][data-refinery-relay-cable-connected='true']",
      wait: 8
    )
    assert_no_selector(
      "[data-refinery-relay-view='initial'] [data-refinery-relay-send][disabled]",
      wait: 8
    )
  end

  def configure_relay
    RefineryRelay.configure do |config|
      config.chat_base_url = @relay.base_url
      config.chat_token = "system-test-token"
      config.chat_tenant_key = "system-test"
      config.public_base_url = @relay.base_url
      config.redis = @redis
      config.broadcaster = ActionCable.server
    end
  end

  def create_chat_pod
    Refinery::Pods::Pod.create!(
      name: "System test chat",
      title: "Ask the test site",
      subtitle: "What would you like to know?",
      body: "<p>Answers come from a persisted Refinery Pod.</p>",
      pod_type: "llm_chat"
    ).tap do |pod|
      pod.pod_items.create!(title: "What information is published?", position: 1)
    end
  end

  def next_chat_request
    loop do
      request = @relay.next_request
      return request if request.fetch(:method) == "POST"
    end
  end
end
