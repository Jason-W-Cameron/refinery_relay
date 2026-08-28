# frozen_string_literal: true

require "securerandom"
require "time"
require "redis"
require "uri"

module RefineryRelay
  class CreditAvailability
    CACHE_PREFIX = "relay_chat_unavailable_until".freeze
    LOCK_PREFIX = "relay_chat_unavailable_lock".freeze
    LOCK_TTL_SECONDS = 5

    class CacheUnavailable < StandardError; end

    def self.available?
      new.available?
    end

    def self.mark_unavailable!(resets_at:)
      new.mark_unavailable!(resets_at: resets_at)
    end

    def self.clear_unavailability!
      new.clear_unavailability!
    end

    def initialize(redis: nil)
      @redis = redis || configured_redis
    end

    def available?
      return true unless redis

      value = redis.get(cache_key)
      return true if value.blank?

      reset_at = Time.iso8601(value)
      return false if reset_at.future?

      redis.del(cache_key)
      true
    rescue Redis::BaseError, ArgumentError, TypeError => e
      raise CacheUnavailable, e.message
    end

    def mark_unavailable!(resets_at:)
      return false unless redis

      reset_at = Time.iso8601(resets_at.to_s)
      return false unless reset_at.future?

      changed = with_lock do
        existing_value = redis.get(cache_key).presence
        existing_reset_at = Time.iso8601(existing_value) if existing_value
        next false if existing_reset_at && existing_reset_at >= reset_at

        redis.set(cache_key, reset_at.iso8601, ex: [ (reset_at - Time.current).ceil, 1 ].max)
        true
      end

      changed
    rescue Redis::BaseError, ArgumentError, TypeError => e
      raise CacheUnavailable, e.message
    end

    def clear_unavailability!
      return true unless redis

      redis.del(cache_key)
      true
    rescue Redis::BaseError => e
      raise CacheUnavailable, e.message
    end

    private

    attr_reader :redis

    def configured_redis
      configuration = RefineryRelay.configuration
      return configuration.redis if configuration.respond_to?(:redis) && configuration.redis

      redis_url = configuration.redis_url.to_s
      return nil if redis_url.blank?

      Redis.new(url: redis_url)
    rescue ArgumentError, URI::InvalidURIError => error
      raise CacheUnavailable, "Redis has not been configured for RefineryRelay: #{error.message}"
    end

    def cache_key
      "#{CACHE_PREFIX}:#{RefineryRelay.configuration.chat_tenant_key}"
    end

    def lock_key
      "#{LOCK_PREFIX}:#{RefineryRelay.configuration.chat_tenant_key}"
    end

    def with_lock
      token = SecureRandom.hex(12)
      acquired = false
      20.times do
        acquired = redis.set(lock_key, token, nx: true, ex: LOCK_TTL_SECONDS)
        break if acquired

        sleep 0.025
      end
      raise CacheUnavailable, "Unable to acquire the Relay credit availability lock." unless acquired

      yield
    ensure
      release_lock(token) if acquired
    end

    def release_lock(token)
      redis.eval(<<~LUA, keys: [ lock_key ], argv: [ token ])
        if redis.call("GET", KEYS[1]) == ARGV[1] then
          return redis.call("DEL", KEYS[1])
        end
        return 0
      LUA
    end
  end
end
