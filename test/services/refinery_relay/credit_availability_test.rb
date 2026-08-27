# frozen_string_literal: true

require "test_helper"

class RefineryRelayCreditAvailabilityTest < ActiveSupport::TestCase
  class FakeRedis
    def initialize
      @values = {}
    end

    def get(key) = @values[key]

    def set(key, value, nx: false, ex: nil)
      return nil if nx && @values.key?(key)

      @values[key] = value
      "OK"
    end

    def del(key)
      @values.delete(key)
      1
    end

    def eval(_script, keys:, argv:)
      del(keys.first) if get(keys.first) == argv.first
    end
  end

  setup do
    @redis = FakeRedis.new
    RefineryRelay::RelaySetting.delete_all
    RefineryRelay::RelaySetting.create!(chat_tenant_key: "refinery-site")
    @availability = RefineryRelay::CreditAvailability.new(redis: @redis)
  end

  teardown do
    RefineryRelay::RelaySetting.delete_all
  end

  test "is available until a future reset time is recorded" do
    assert @availability.available?

    reset_at = 2.hours.from_now.iso8601
    assert @availability.mark_unavailable!(resets_at: reset_at)
    assert_not @availability.available?
  end

  test "keeps the latest reset time when state changes" do
    earlier = 1.hour.from_now.iso8601
    later = 2.hours.from_now.iso8601

    assert @availability.mark_unavailable!(resets_at: earlier)
    assert @availability.mark_unavailable!(resets_at: later)
    assert_not @availability.mark_unavailable!(resets_at: earlier)

    assert_equal later, @redis.get("relay_chat_unavailable_until:refinery-site")
  end

  test "clears the unavailable circuit" do
    @availability.mark_unavailable!(resets_at: 2.hours.from_now.iso8601)

    assert @availability.clear_unavailability!
    assert @availability.available?
  end
end
