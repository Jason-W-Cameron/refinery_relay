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
        render json: { theme: RefineryRelay::ChatTheme.current.editable_values }
      end
    end
  end
end
