# frozen_string_literal: true

module RefineryRelay
  # Makes the Relay pod available to Refinery's shared frontend pod renderer.
  # Host layouts may still provide an explicit pod_types list; in that case the
  # Relay pod is added to the first shared-pods call and rendered only once per
  # view context.
  module PodRendering
    RENDERED_IVAR = :@_refinery_relay_chat_pod_rendered
    UNLIMITED_IVAR = :@_refinery_relay_chat_pod_unlimited

    module HelperMethods
      def set_pod_types(locals)
        pod_types = super
        RefineryRelay::PodRendering.pod_types_for(pod_types, self, locals)
      end

      def set_pod_limit(locals)
        limit = super
        return limit unless instance_variable_get(RefineryRelay::PodRendering::UNLIMITED_IVAR)

        instance_variable_set(RefineryRelay::PodRendering::UNLIMITED_IVAR, false)
        nil
      end
    end

    module_function

    def install!(helper: "PodsHelper".safe_constantize)
      return false unless helper
      return false if helper.ancestors.include?(HelperMethods)

      helper.prepend(HelperMethods)
      true
    end

    def pod_types_for(pod_types, view_context, locals)
      values = Array(pod_types).map { |entry| pod_type_value(entry) }

      if values.include?(PodContract::POD_TYPE)
        view_context.instance_variable_set(RENDERED_IVAR, true)
      elsif locals.respond_to?(:key?) && locals.key?(:pod_types) &&
            !view_context.instance_variable_get(RENDERED_IVAR)
        values << PodContract::POD_TYPE
        view_context.instance_variable_set(RENDERED_IVAR, true)
      end

      # refinerycms-pods applies the host's limit after filtering by type. If
      # chat is among those types, an unrelated content limit can silently
      # omit it. Clear that one limit so the configured chat is always shown.
      if values.include?(PodContract::POD_TYPE) && locals.respond_to?(:key?) && locals.key?(:limit)
        view_context.instance_variable_set(UNLIMITED_IVAR, true)
      end

      values
    end

    def pod_type_value(entry)
      entry.is_a?(Array) ? entry[1].to_s : entry.to_s
    end
    private_class_method :pod_type_value
  end
end
