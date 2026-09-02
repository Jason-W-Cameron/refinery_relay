# frozen_string_literal: true

module RefineryRelay
  # Registers the Relay chat Pod with the custom refinerycms-pods extension.
  # Registration is idempotent because Rails can run to_prepare more than once.
  module PodRegistration
    POD_TYPE = PodContract::POD_TYPE
    LABEL = "Relay Chat"
    POD_TYPE_OPTION = [ LABEL, POD_TYPE ].freeze
    POD_TYPE_METADATA = {
      name: POD_TYPE,
      details: "Embed the configured Niimble Relay chat widget.",
      clips: [],
      type_image_large: "",
      type_image_small: "relay_chat.svg",
      example_image: ""
    }.freeze

    module PodTypeMethods
      def pod_types
        types = Array(super)
        return types if types.any? { |type| type_name(type) == RefineryRelay::PodRegistration::POD_TYPE }

        types + [ RefineryRelay::PodRegistration::POD_TYPE_METADATA.dup ]
      end

      private

      def type_name(type)
        type.respond_to?(:[]) ? type[:name].to_s : type.to_s
      end
    end

    module_function

    def install!(pod_class: default_pod_class, pod_type_class: default_pod_type_class)
      registered = install_legacy_type!(pod_class)
      install_picker_type!(pod_type_class) || registered
    end

    def install_legacy_type!(pod_class)
      return false unless pod_class
      return false unless pod_class.const_defined?(:POD_TYPES, false)

      pod_types = pod_class::POD_TYPES
      return false if pod_types.any? { |entry| pod_type_value(entry) == POD_TYPE }

      pod_types << (pod_types.first.is_a?(Array) ? POD_TYPE_OPTION.dup : POD_TYPE)
      true
    end
    private_class_method :install_legacy_type!

    def install_picker_type!(pod_type_class)
      return false unless pod_type_class&.respond_to?(:pod_types)

      singleton_class = class << pod_type_class; self; end
      return false if singleton_class.ancestors.include?(PodTypeMethods)

      singleton_class.prepend(PodTypeMethods)
      true
    end
    private_class_method :install_picker_type!

    def pod_type_value(entry)
      entry.is_a?(Array) ? entry[1].to_s : entry.to_s
    end
    private_class_method :pod_type_value

    def default_pod_class
      # On Rails' classic autoloader this model is often not loaded yet when
      # the engine's `to_prepare` callback first runs. `defined?` would return
      # false and the Relay Chat choice would never be added to the admin form.
      "Refinery::Pods::Pod".safe_constantize
    end
    private_class_method :default_pod_class

    def default_pod_type_class
      "PodType".safe_constantize
    end
    private_class_method :default_pod_type_class
  end
end
