# frozen_string_literal: true

require "securerandom"

module RefineryRelay
  module Admin
    class RelaySettingsController < ::Refinery::AdminController
      helper_method :refinery, :relay_documents_endpoint
      skip_after_action :store_location?

      def edit
        @relay_setting = RelaySetting.current
        @generated_source_token = session.delete(:refinery_relay_generated_source_token)
      end

      def update
        @relay_setting = RelaySetting.current

        if @relay_setting.update(relay_setting_params)
          redirect_to Rails.application.routes.url_helpers.refinery_relay_settings_path,
                      notice: "Relay settings were saved."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def generate_bearer_token
        token = SecureRandom.urlsafe_base64(32)
        RelaySetting.current.update!(source_token: token)
        session[:refinery_relay_generated_source_token] = token

        redirect_to Rails.application.routes.url_helpers.refinery_relay_settings_path(anchor: "relay-generated-token-panel"),
                    notice: "A new bearer access token was generated. Copy it now; it will not be shown again."
      end

      private

      # Refinery's admin layout expects the host's `refinery` route proxy.
      # This isolated engine is mounted alongside Refinery, so use the host
      # route set to keep the shared layout and sidebar available.
      def refinery
        Rails.application.routes.url_helpers
      end

      def relay_documents_endpoint
        "#{request.base_url}/refinery_relay/api/relay/documents"
      end

      def relay_setting_params
        attributes = params.require(:relay_setting).permit(
          :chat_base_url,
          :chat_token,
          :widget_markup,
          source_types: []
        )

        RelaySetting::SECRET_ATTRIBUTES.each do |attribute|
          attributes.delete(attribute) if attributes[attribute].blank?
        end

        attributes
      end
    end
  end
end
