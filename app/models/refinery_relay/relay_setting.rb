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
        source_field_mappings: {},
        chat_tenant_key: "refinery",
        chat_open_timeout_seconds: Configuration::DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS,
        chat_read_timeout_seconds: Configuration::DEFAULT_CHAT_READ_TIMEOUT_SECONDS,
        sync_open_timeout_seconds: Configuration::DEFAULT_SYNC_OPEN_TIMEOUT_SECONDS,
        sync_read_timeout_seconds: Configuration::DEFAULT_SYNC_READ_TIMEOUT_SECONDS
      }
    end

    # Rails 6 takes the serialized type as the second positional argument,
    # whereas Rails 7+ takes it as a keyword. Both forms use YAML, preserving
    # the representation used by existing installations.
    if ActiveRecord::VERSION::MAJOR >= 7
      serialize :source_types, coder: YAML, type: Array
      serialize :source_field_mappings, coder: YAML, type: Hash
    else
      serialize :source_types, Array
      serialize :source_field_mappings, Hash
    end

    def source_types
      values = super
      values = DEFAULT_SOURCE_TYPES if values.nil?
      Array(values).map(&:to_s) & SourceRegistry.keys
    end

    def source_types=(values)
      super(Array(values).map(&:to_s) & SourceRegistry.keys)
    end

    # A mapping only contains fields that the currently discovered source has
    # explicitly made available. Empty selections are omitted so the feed can
    # continue using that source's conservative default fields.
    def source_field_mappings
      normalize_source_field_mappings(super || {})
    end

    def source_field_mappings=(mappings)
      super(normalize_source_field_mappings(mappings))
    end

    validates :chat_open_timeout_seconds, :sync_open_timeout_seconds,
              numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 30 },
              allow_nil: true
    validates :chat_read_timeout_seconds,
              numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 },
              allow_nil: true

    private

    def normalize_source_field_mappings(mappings)
      values = mappings.respond_to?(:to_h) ? mappings.to_h : mappings
      SourceRegistry.normalize_field_mappings(values)
    end
  end
end
