# frozen_string_literal: true

module RefineryRelay
  module PodsAdminController
    THEME_ATTRIBUTES = %w[
      refinery_relay_accent_color
      refinery_relay_background_color
      refinery_relay_surface_color
      refinery_relay_text_color
    ].freeze
    POD_SETTINGS_ATTRIBUTES = %w[
      refinery_relay_prompt_placeholder
      refinery_relay_information_text
      refinery_relay_footer_logo_url
      refinery_relay_footer_logo_link
    ].freeze

    def self.prepended(controller)
      controller.after_action :persist_refinery_relay_site_theme, only: %i[create update]
      controller.after_action :persist_refinery_relay_pod_settings, only: %i[create update]
    end

    private

    def pod_params
      pod_parameters = params[:pod]
      if pod_parameters.respond_to?(:permit)
        pod_values = pod_parameters.to_unsafe_h
        @refinery_relay_theme_attributes = pod_values.slice(*THEME_ATTRIBUTES)
        THEME_ATTRIBUTES.each { |attribute| pod_parameters.delete(attribute) }
        @refinery_relay_pod_settings_attributes = pod_values.slice(*POD_SETTINGS_ATTRIBUTES)
        POD_SETTINGS_ATTRIBUTES.each { |attribute| pod_parameters.delete(attribute) }
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

    def persist_refinery_relay_pod_settings
      return unless @pod&.persisted?
      return unless @pod.respond_to?(:system_name) && @pod.system_name.to_s == RefineryRelay::PodContract::POD_TYPE
      return if @pod.errors.any? || @refinery_relay_pod_settings_attributes.blank?
      return unless RefineryRelay::PodSettings.connection.data_source_exists?(RefineryRelay::PodSettings.table_name)

      attributes = @refinery_relay_pod_settings_attributes.transform_keys do |attribute|
        attribute.to_s.delete_prefix("refinery_relay_").to_sym
      end
      attributes.select! { |attribute, _value| RefineryRelay::PodSettings.column_names.include?(attribute.to_s) }
      return if attributes.blank?

      RefineryRelay::PodSettings.for(@pod).update!(attributes)
    end
  end
end
