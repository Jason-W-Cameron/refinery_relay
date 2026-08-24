# frozen_string_literal: true

module RefineryRelay
  module PodsAdminController
    THEME_ATTRIBUTES = %w[
      refinery_relay_accent_color
      refinery_relay_background_color
      refinery_relay_surface_color
      refinery_relay_text_color
    ].freeze

    def self.prepended(controller)
      controller.after_action :persist_refinery_relay_site_theme, only: %i[create update]
    end

    private

    def pod_params
      pod_parameters = params[:pod]
      if pod_parameters.respond_to?(:permit)
        @refinery_relay_theme_attributes = pod_parameters.permit(*THEME_ATTRIBUTES).to_h
        THEME_ATTRIBUTES.each { |attribute| pod_parameters.delete(attribute) }
      end

      super
    end

    def persist_refinery_relay_site_theme
      return unless @pod&.persisted?
      return unless @pod.respond_to?(:system_name) && @pod.system_name.to_s == RefineryRelay::PodContract::POD_TYPE
      return if @pod.errors.any? || @refinery_relay_theme_attributes.blank?

      attributes = @refinery_relay_theme_attributes.transform_keys do |attribute|
        attribute.to_s.delete_prefix("refinery_relay_").to_sym
      end
      RefineryRelay::SiteSettings.save_colors(attributes)
    end
  end
end
