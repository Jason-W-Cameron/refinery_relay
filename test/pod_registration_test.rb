# frozen_string_literal: true

require "test_helper"

class RefineryRelayPodRegistrationTest < ActiveSupport::TestCase
  test "registers Relay Chat with the Refinery pod type list" do
    pod_class = build_pod_class([ [ "Basic Text Editor", "content" ] ])

    assert RefineryRelay::PodRegistration.install!(pod_class: pod_class)
    assert_includes pod_class::POD_TYPES, [ "Relay Chat", "relay_chat" ]
  end

  test "does not register the pod type more than once" do
    pod_class = build_pod_class([ [ "Basic Text Editor", "content" ] ])

    assert RefineryRelay::PodRegistration.install!(pod_class: pod_class)
    assert_not RefineryRelay::PodRegistration.install!(pod_class: pod_class)
    assert_equal 1, pod_class::POD_TYPES.count { |entry| entry[1] == "relay_chat" }
  end

  test "supports pod extensions that store plain pod type values" do
    pod_class = build_pod_class([ "content" ])

    assert RefineryRelay::PodRegistration.install!(pod_class: pod_class)
    assert_includes pod_class::POD_TYPES, "relay_chat"
    assert_not RefineryRelay::PodRegistration.install!(pod_class: pod_class)
  end

  test "waits safely when the pods extension is unavailable" do
    assert_not RefineryRelay::PodRegistration.install!(pod_class: nil)
  end

  test "loads the Pods model when registration runs before it has been referenced" do
    assert_equal Refinery::Pods::Pod,
                 RefineryRelay::PodRegistration.send(:default_pod_class)
  end

  private

  def build_pod_class(pod_types)
    Class.new.tap { |klass| klass.const_set(:POD_TYPES, pod_types) }
  end
end
