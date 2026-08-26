# frozen_string_literal: true

module RefineryRelay
  class ChatTheme
    EDITABLE_ATTRIBUTES = %i[accent_color background_color surface_color text_color assistant_response_color].freeze

    DEFAULTS = {
      accent_color: "#fbbf24",
      background_color: "#101010",
      surface_color: "#181818",
      text_color: "#f5f5f5",
      assistant_response_color: "#dedede"
    }.freeze

    HEX_COLOR = /\A#(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i

    attr_reader(*EDITABLE_ATTRIBUTES)

    def self.current
      values = {
        accent_color: RefineryRelay.configuration.chat_accent_color,
        background_color: RefineryRelay.configuration.chat_background_color,
        surface_color: RefineryRelay.configuration.chat_surface_color,
        text_color: RefineryRelay.configuration.chat_text_color,
        assistant_response_color: RefineryRelay.configuration.chat_assistant_response_color
      }
      new(values.merge(RefineryRelay::SiteSettings.current.overrides))
    end

    def initialize(values = DEFAULTS)
      EDITABLE_ATTRIBUTES.each do |attribute|
        value = values.fetch(attribute, DEFAULTS.fetch(attribute)).to_s.strip
        value = DEFAULTS.fetch(attribute) unless value.match?(HEX_COLOR)
        instance_variable_set("@#{attribute}", value)
      end
    end

    def editable_values
      EDITABLE_ATTRIBUTES.index_with { |attribute| public_send(attribute) }
    end

    def css_variables
      accent_rgb = rgb(accent_color)
      text_rgb = rgb(text_color)
      background_rgb = rgb(background_color)
      danger_color = contrast_text(background_rgb) == "#ffffff" ? "#fca5a5" : "#b91c1c"
      danger_rgb = rgb(danger_color)

      {
        "--refinery-relay-accent" => accent_color,
        "--refinery-relay-accent-soft" => rgba(accent_rgb, 0.09),
        "--refinery-relay-accent-focus" => rgba(accent_rgb, 0.13),
        "--refinery-relay-accent-text" => contrast_text(accent_rgb),
        "--refinery-relay-background" => background_color,
        "--refinery-relay-surface" => surface_color,
        "--refinery-relay-surface-raised" => rgba(text_rgb, 0.08),
        "--refinery-relay-surface-raised-hover" => rgba(text_rgb, 0.12),
        "--refinery-relay-border" => rgba(text_rgb, 0.14),
        "--refinery-relay-border-strong" => rgba(text_rgb, 0.28),
        "--refinery-relay-text" => text_color,
        "--refinery-relay-assistant-response" => assistant_response_color,
        "--refinery-relay-text-muted" => rgba(text_rgb, 0.68),
        "--refinery-relay-danger" => danger_color,
        "--refinery-relay-danger-soft" => rgba(danger_rgb, 0.11),
        "--refinery-relay-danger-border" => rgba(danger_rgb, 0.22)
      }.map { |name, value| "#{name}: #{value}" }.join("; ")
    end

    private

    def rgb(hex)
      value = hex.delete_prefix("#")
      value = value.chars.map { |character| character * 2 }.join if value.length == 3
      value.scan(/../).map { |channel| channel.to_i(16) }
    end

    def rgba(channels, alpha)
      "rgba(#{channels.join(', ')}, #{alpha})"
    end

    def contrast_text(channels)
      luminance = channels.map { |channel| channel / 255.0 }.map do |channel|
        channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
      end

      0.2126 * luminance[0] + 0.7152 * luminance[1] + 0.0722 * luminance[2] > 0.179 ? "#171717" : "#ffffff"
    end
  end
end
