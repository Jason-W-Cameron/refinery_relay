# frozen_string_literal: true

require "redis"

# RefineryRelay reads its credentials and defaults from RELAY_* environment
# variables. Keep credentials in the host environment rather than source control.
# Set RELAY_RSS_FEED_URL to the site's existing RSS or Atom feed and
# RELAY_SOURCE_TOKEN to a private token used by Relay when requesting it.
RefineryRelay.configure do |config|
  # A Redis connection is required for shared credit availability state.
  config.redis = Redis.new(url: ENV.fetch("REDIS_URL")) if ENV["REDIS_URL"].present?

  # Optional application-specific overrides:
  # config.chat_tenant_key = "my-refinery-site"
  # config.chat_open_timeout_seconds = 5
  # config.chat_read_timeout_seconds = 45
end
