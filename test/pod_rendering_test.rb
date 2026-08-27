# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodRenderingTest < ActiveSupport::TestCase
  test "adds Relay Chat to an explicit shared-pods list" do
    view = build_view

    assert_equal [ "content", "llm_chat" ], view.set_pod_types(pod_types: [ "content" ])
  end

  test "does not add Relay Chat again to later shared-pods calls" do
    view = build_view

    view.set_pod_types(pod_types: [ "content" ])

    assert_equal [ "testimonial" ], view.set_pod_types(pod_types: [ "testimonial" ])
  end

  test "normalizes registered select options for frontend filtering" do
    view = build_view

    assert_equal [ "content", "llm_chat" ],
                 view.set_pod_types(pod_types: [ [ "Basic Text Editor", "content" ],
                                                  [ "Relay Chat", "llm_chat" ] ])
  end

  private

  def build_view
    base_helper = Module.new do
      define_method(:set_pod_types) { |locals| locals[:pod_types] }
    end

    view_class = Class.new do
      include base_helper
      prepend RefineryRelay::PodRendering::HelperMethods
    end

    view_class.new
  end
end
