# frozen_string_literal: true

module RefineryRelay
  # Translates the fields exposed by refinerycms-pods into the values needed
  # by the Relay chat interface without coupling the generic backend to a CMS.
  module PodContract
    POD_TYPE = "llm_chat"
    DEFAULT_HEADING = "Ask us a question"

    module_function

    def chat_pod?(pod)
      pod.respond_to?(:system_name) && pod.system_name.to_s == POD_TYPE
    end

    def heading(pod)
      value = pod.title if pod.respond_to?(:title)
      value = pod.name if value.blank? && pod.respond_to?(:name)
      value.presence || DEFAULT_HEADING
    end

    def suggested_questions(pod)
      if pod.respond_to?(:pod_items)
        items = pod.pod_items
        items = items.order(:position) if items.respond_to?(:order)
        return Array(items).map { |item| item.title.presence }.compact
      end

      RefineryRelay::PodSettings.for(pod).suggested_questions
    end
  end
end
