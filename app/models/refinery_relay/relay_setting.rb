# frozen_string_literal: true

module RefineryRelay
  # The singleton source of runtime configuration for the Relay integration.
  # It deliberately keeps credentials in the application's database rather
  # than in a host initializer or environment variables.
  class RelaySetting < ApplicationRecord
    self.table_name = "refinery_relay_settings"

    SECRET_ATTRIBUTES = %i[source_token chat_token sync_token redis_url].freeze
    DEFAULT_SOURCE_TYPES = %w[pages].freeze
    TIMEOUT_ATTRIBUTES = %i[
      chat_open_timeout_seconds
      chat_read_timeout_seconds
      sync_open_timeout_seconds
      sync_read_timeout_seconds
    ].freeze

    def self.current
      return new(default_attributes) unless table_available?

      first || new(default_attributes)
    end

    def self.table_available?
      connection.data_source_exists?(table_name)
    rescue ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.default_attributes
      {
        source_types: DEFAULT_SOURCE_TYPES,
        chat_tenant_key: "refinery",
        chat_open_timeout_seconds: Configuration::DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS,
        chat_read_timeout_seconds: Configuration::DEFAULT_CHAT_READ_TIMEOUT_SECONDS,
        sync_open_timeout_seconds: Configuration::DEFAULT_SYNC_OPEN_TIMEOUT_SECONDS,
        sync_read_timeout_seconds: Configuration::DEFAULT_SYNC_READ_TIMEOUT_SECONDS
      }
    end

    # JSON-in-text keeps this setting portable across host database adapters.
    serialize :source_types, coder: JSON

    def source_types
      values = super
      values = DEFAULT_SOURCE_TYPES if values.nil?
      Array(values).map(&:to_s).intersection(DocumentFeed::SOURCE_TYPES)
    end

    def source_types=(values)
      super(Array(values).map(&:to_s).intersection(DocumentFeed::SOURCE_TYPES))
    end

    validates :chat_open_timeout_seconds, :sync_open_timeout_seconds,
              numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 30 },
              allow_nil: true
    validates :chat_read_timeout_seconds,
              numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 },
              allow_nil: true
  end
end
