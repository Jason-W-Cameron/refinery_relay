# frozen_string_literal: true

module RefineryRelay
  # Registers the Relay chat Pod with the custom refinerycms-pods extension.
  # Registration is idempotent because Rails can run to_prepare more than once.
  module PodRegistration
    POD_TYPE = PodContract::POD_TYPE
    LABEL = "LLM Chat"
    POD_TYPE_OPTION = [ LABEL, POD_TYPE ].freeze

    module_function

    def install!(pod_class: default_pod_class)
      return false unless pod_class

      pod_types = pod_class::POD_TYPES
      return false if pod_types.any? { |entry| pod_type_value(entry) == POD_TYPE }

      # SIT_V4's pods extension expects an array of plain strings, while newer
      # releases use [label, value] select options.
      pod_types << (pod_types.first.is_a?(Array) ? POD_TYPE_OPTION.dup : POD_TYPE)
      true
    end

    def pod_type_value(entry)
      entry.is_a?(Array) ? entry[1].to_s : entry.to_s
    end
    private_class_method :pod_type_value

    def default_pod_class
      # On Rails' classic autoloader this model is often not loaded yet when
      # the engine's `to_prepare` callback first runs. `defined?` would return
      # false and the LLM Chat choice would never be added to the admin form.
      "Refinery::Pods::Pod".safe_constantize
    end
    private_class_method :default_pod_class
  end
end
