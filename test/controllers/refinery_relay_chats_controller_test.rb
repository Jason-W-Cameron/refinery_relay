# frozen_string_literal: true

require "test_helper"

class RefineryRelayChatsControllerTest < ActionDispatch::IntegrationTest
  CHAT_PATH = "/refinery_relay/api/relay/chat"
  AVAILABILITY_PATH = "/refinery_relay/api/relay/chat/availability"

  setup do
    RefineryRelay.reset_configuration!
  end

  teardown do
    RefineryRelay.reset_configuration!
  end

  test "proxies a browser chat request to Relay" do
    test_case = self
    payload = {
      "conversation_id" => "conversation-123",
      "message_id" => "message-123",
      "answer" => "Hello from Relay.",
      "citations" => [],
      "fallback" => false
    }

    stub_class_method(RefineryRelay::CreditAvailability, :available?, ->(*) { true }) do
      stub_class_method(RefineryRelay::ChatClient, :call, lambda { |**arguments|
        test_case.assert_equal "How do I qualify?", arguments.fetch(:message)
        test_case.assert_equal "visitor-123", arguments.fetch(:visitor_id)
        test_case.assert_equal "web", arguments.dig(:context, "interface")
        RefineryRelay::ChatClient::Response.new(status: 200, payload: payload)
      }) do
        post CHAT_PATH, params: {
          message: "How do I qualify?",
          visitor_id: "visitor-123",
          context: { current_url: "https://refinery.example", locale: "en-ZA", interface: "web", interface_type: "web" }
        }, as: :json
      end
    end

    assert_response :success
    assert_equal payload, response.parsed_body
  end

  test "requires a message" do
    stub_class_method(RefineryRelay::CreditAvailability, :available?, ->(*) { true }) do
      post CHAT_PATH, params: {}, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_request", response.parsed_body.fetch("error")
  end

  test "keeps only citations from the configured public site" do
    RefineryRelay.configuration.public_base_url = "https://refinery.example"
    test_case = self
    payload = {
      "answer" => "Read the About page [1].",
      "citations" => [
        { "title" => "About", "url" => "https://refinery.example/about" },
        { "title" => "External", "url" => "https://other.example/article" },
        { "title" => "Unsafe", "url" => "javascript:alert(1)" }
      ]
    }

    stub_class_method(RefineryRelay::CreditAvailability, :available?, ->(*) { true }) do
      stub_class_method(RefineryRelay::ChatClient, :call, lambda { |**|
        RefineryRelay::ChatClient::Response.new(status: 200, payload: payload)
      }) do
        post CHAT_PATH, params: { message: "Where is the about page?" }, as: :json
      end
    end

    test_case.assert_response :success
    assert_equal [
      { "title" => "About", "url" => "https://refinery.example/about" },
      nil,
      nil
    ], response.parsed_body.fetch("citations")
  end

  test "keeps local loopback citations when the browser uses localhost" do
    RefineryRelay.configuration.public_base_url = "http://localhost:3004"
    payload = {
      "answer" => "Read the home page [1].",
      "citations" => [
        { "title" => "Home", "url" => "http://127.0.0.1:3004/" },
        { "title" => "Wrong port", "url" => "http://127.0.0.1:3005/" }
      ]
    }

    stub_class_method(RefineryRelay::CreditAvailability, :available?, ->(*) { true }) do
      stub_class_method(RefineryRelay::ChatClient, :call, lambda { |**|
        RefineryRelay::ChatClient::Response.new(status: 200, payload: payload)
      }) do
        post CHAT_PATH, params: { message: "Where is home?" }, as: :json
      end
    end

    assert_response :success
    assert_equal [
      { "title" => "Home", "url" => "http://127.0.0.1:3004/" },
      nil
    ], response.parsed_body.fetch("citations")
  end

  test "returns unavailable when the shared circuit is open" do
    test_case = self
    stub_class_method(RefineryRelay::CreditAvailability, :available?, ->(*) { false }) do
      stub_class_method(RefineryRelay::ChatClient, :call, ->(**) { test_case.flunk "Relay must not be called" }) do
        post CHAT_PATH, params: { message: "Hello" }, as: :json
      end
    end

    assert_response :success
    assert_equal({ "chat_unavailable" => true }, response.parsed_body)
  end

  test "availability endpoint returns the generic availability flag" do
    stub_class_method(RefineryRelay::CreditAvailability, :available?, ->(*) { false }) do
      get AVAILABILITY_PATH
    end

    assert_response :success
    assert_equal({ "available" => false }, response.parsed_body)
  end
end
