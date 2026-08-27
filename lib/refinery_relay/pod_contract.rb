# frozen_string_literal: true

module RefineryRelay
  # Defines the retained Refinery pod identity without supplying any UI.
  module PodContract
    POD_TYPE = "llm_chat"
    module_function

    def chat_pod?(pod)
      pod.respond_to?(:system_name) && pod.system_name.to_s == POD_TYPE
    end
  end
end
