# frozen_string_literal: true

module RefineryRelay
  module Api
    module Relay
      class DocumentsController < ActionController::API
        before_action :ensure_configured
        before_action :authenticate_source

        def index
          render json: RefineryRelay::RssDocumentFeed.call(
            feed_url: RefineryRelay.configuration.rss_feed_url
          )
        rescue RefineryRelay::RssDocumentFeed::Error => e
          render json: { error: "rss_feed_unavailable", message: e.message }, status: :bad_gateway
        end

        private

        def ensure_configured
          return if RefineryRelay.configuration.source_token.present? && RefineryRelay.configuration.rss_feed_url.present?

          render json: { error: "source_not_configured" }, status: :service_unavailable
        end

        def authenticate_source
          expected = RefineryRelay.configuration.source_token.to_s
          provided = request.authorization.to_s.match(/\ABearer\s+(.+)\z/i)&.captures&.first.to_s
          authenticated = expected.present? && provided.bytesize == expected.bytesize &&
            ActiveSupport::SecurityUtils.secure_compare(provided, expected)
          return if authenticated

          render json: { error: "unauthorized" }, status: :unauthorized
        end
      end
    end
  end
end
