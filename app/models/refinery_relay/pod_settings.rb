# frozen_string_literal: true

module RefineryRelay
  class PodSettings < ApplicationRecord
    self.table_name = "refinery_relay_pod_settings"

    DEFAULT_INFORMATION_TEXT = <<~TEXT.squish
      This intelligent assistant is powered by this organisation’s published information.
      It helps visitors find accurate answers and key information instantly.
    TEXT
    DEFAULT_FOOTER_LOGO_URL = RefineryRelay::Configuration::DEFAULT_CHAT_FOOTER_LOGO_URL
    DEFAULT_FOOTER_LOGO_LINK = RefineryRelay::Configuration::DEFAULT_CHAT_FOOTER_LOGO_LINK

    def self.for(pod)
      return new unless pod.respond_to?(:id) && pod.id.present?
      return new unless connection.data_source_exists?(table_name)

      find_or_initialize_by(pod_id: pod.id)
    end

    def prompt_placeholder
      setting_value(:prompt_placeholder).to_s.strip.presence || RefineryRelay.configuration.chat_prompt_placeholder
    end

    def information_text
      setting_value(:information_text).to_s.strip.presence || DEFAULT_INFORMATION_TEXT
    end

    def footer_logo_url
      value = setting_value(:footer_logo_url).to_s.strip.presence || RefineryRelay.configuration.chat_footer_logo_url
      valid_logo_reference?(value) ? value : DEFAULT_FOOTER_LOGO_URL
    end

    def footer_logo_link
      value = setting_value(:footer_logo_link).to_s.strip.presence || RefineryRelay.configuration.chat_footer_logo_link
      valid_link?(value) ? value : DEFAULT_FOOTER_LOGO_LINK
    end

    private

    def setting_value(attribute)
      has_attribute?(attribute) ? self[attribute] : nil
    end

    def valid_logo_reference?(value)
      value.match?(%r{\A(?:https?://|/|[\w./-]+\z)}i)
    end

    def valid_link?(value)
      value.match?(%r{\A(?:https?://|/)}i)
    end
  end
end
