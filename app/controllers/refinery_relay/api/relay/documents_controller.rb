# frozen_string_literal: true

require "digest"

module RefineryRelay
  module Api
    module Relay
      class DocumentsController < ActionController::API
        before_action :authenticate_source!

        def index
          render json: RefineryRelay::DocumentFeed.new(
            cursor: params[:cursor],
            base_url: request.base_url
          ).call
        rescue RefineryRelay::DocumentFeed::InvalidCursor
          render json: { error: "invalid_cursor", message: "cursor is invalid" }, status: :unprocessable_entity
        end

        private

        def authenticate_source!
          configured = RefineryRelay.configuration.source_token.to_s
          supplied = request.authorization.to_s.delete_prefix("Bearer ").strip

          valid = configured.present? && supplied.present? &&
            ActiveSupport::SecurityUtils.secure_compare(
              Digest::SHA256.hexdigest(configured),
              Digest::SHA256.hexdigest(supplied)
            )
          return if valid

          render json: { error: "unauthorized", message: "A valid Relay source token is required." }, status: :unauthorized
        end
      end
    end
  end
end
