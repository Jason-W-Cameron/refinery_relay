# frozen_string_literal: true

module RefineryRelay
  module Admin
    class SettingsController < ::Refinery::AdminController
      # This endpoint is used by the Styling fields embedded in the Pods form.
      # It is authenticated through Refinery's admin controller, but it is not
      # a standalone Refinery plugin controller and therefore is not present in
      # Refinery's controller authorisation list.
      skip_before_action :restrict_controller, only: :show

      def show
        render json: {
          theme: RefineryRelay::ChatTheme.current.editable_values,
          pod: pod_settings_payload
        }
      end

      private

      def pod_settings_payload
        settings = RefineryRelay::PodSettings.for(refinery_pod)
        {
          prompt_placeholder: settings.prompt_placeholder,
          information_text: settings.information_text,
          information_image_id: settings.information_image_id_value,
          information_image_url: settings.information_image_url,
          information_image_alt: settings.information_image_alt,
          footer_logo_url: settings.footer_logo_url,
          footer_logo_link: settings.footer_logo_link,
          terms_link: settings.terms_link,
          image_picker_path: refinery.insert_admin_images_path
        }
      end

      def refinery_pod
        return unless params[:pod_id].present?
        return unless defined?(::Refinery::Pods::Pod)

        ::Refinery::Pods::Pod.find_by(id: params[:pod_id])
      end
    end
  end
end
