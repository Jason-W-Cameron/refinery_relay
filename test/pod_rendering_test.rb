# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodRenderingTest < ActiveSupport::TestCase
  test "adds Relay Chat to an explicit shared-pods list" do
    view = build_view

    assert_equal [ "content", "relay_chat" ],
                 view.set_pod_types(pod_types: [ "content" ])
  end

  test "does not add Relay Chat again to later shared-pods calls" do
    view = build_view

    view.set_pod_types(pod_types: [ "content" ])

    assert_equal [ "testimonial" ], view.set_pod_types(pod_types: [ "testimonial" ])
  end

  test "normalizes registered select options for frontend filtering" do
    view = build_view

    assert_equal [ "content", "relay_chat" ],
                 view.set_pod_types(pod_types: [ [ "Basic Text Editor", "content" ],
                                                  [ "Relay Chat", "relay_chat" ] ])
  end

  test "adds the canonical key to a legacy explicit list" do
    view = build_view

    assert_equal [ "llm_chat", "relay_chat" ],
                 view.set_pod_types(pod_types: [ "llm_chat" ])
  end

  test "does not let a content limit omit Relay Chat" do
    view = build_view

    assert_equal [ "content", "relay_chat" ],
                 view.set_pod_types(pod_types: [ "content" ], limit: 5)
    assert_nil view.set_pod_limit(limit: 5)
  end

  private

  def build_view
    base_helper = Module.new do
      define_method(:set_pod_types) { |locals| locals[:pod_types] }
      define_method(:set_pod_limit) { |locals| locals[:limit] }
    end

    view_class = Class.new do
      include base_helper
      prepend RefineryRelay::PodRendering::HelperMethods
    end

    view_class.new
  end
end
