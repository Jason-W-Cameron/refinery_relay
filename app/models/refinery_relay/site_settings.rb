# frozen_string_literal: true

module RefineryRelay
  class SiteSettings < ApplicationRecord
    self.table_name = "refinery_relay_site_settings"

    COLOR_ATTRIBUTES = %i[accent_color background_color surface_color text_color assistant_response_color].freeze
    HEX_COLOR = /\A#(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i

    def self.current
      return new unless connection.data_source_exists?(table_name)

      first || new
    end

    def self.save_colors(attributes)
      return unless connection.data_source_exists?(table_name)

      settings = first_or_initialize
      COLOR_ATTRIBUTES.each do |attribute|
        value = attributes[attribute] || attributes[attribute.to_s]
        settings.public_send("#{attribute}=", value.to_s.strip) if value.to_s.strip.match?(HEX_COLOR)
      end
      settings.save!
    end

    def overrides
      COLOR_ATTRIBUTES.each_with_object({}) do |attribute, values|
        value = public_send(attribute).to_s.strip
        values[attribute] = value if value.match?(HEX_COLOR)
      end
    end
  end
end
