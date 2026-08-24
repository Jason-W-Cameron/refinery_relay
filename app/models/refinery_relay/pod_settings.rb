# frozen_string_literal: true

module RefineryRelay
  class PodSettings < ApplicationRecord
    self.table_name = "refinery_relay_pod_settings"

    DEFAULT_INFORMATION_TEXT = <<~TEXT.squish
      This intelligent assistant is powered by this organisation’s published information.
      It helps visitors find accurate answers and key information instantly.
    TEXT

    def self.for(pod)
      return new unless pod.respond_to?(:id) && pod.id.present?
      return new unless connection.data_source_exists?(table_name)

      find_or_initialize_by(pod_id: pod.id)
    end

    def prompt_placeholder
      self[:prompt_placeholder].to_s.strip.presence || RefineryRelay.configuration.chat_prompt_placeholder
    end

    def information_text
      self[:information_text].to_s.strip.presence || DEFAULT_INFORMATION_TEXT
    end
  end
end
