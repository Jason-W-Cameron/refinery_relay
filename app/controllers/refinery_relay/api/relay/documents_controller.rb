# frozen_string_literal: true

module RefineryRelay
  module Api
    module Relay
      class DocumentsController < ActionController::API
        RSS_PATH = "/nlweb/rss"

        before_action :ensure_configured
        before_action :authenticate_source

        def index
          render json: RefineryRelay::RssDocumentFeed.call(
            feed_url: "#{source_base_url}#{RSS_PATH}"
          )
        rescue RefineryRelay::RssDocumentFeed::Error => e
          render json: { error: "rss_feed_unavailable", message: e.message }, status: :bad_gateway
        end

        private

        def ensure_configured
          return if RefineryRelay.configuration.source_token.present?

          render json: { error: "source_not_configured" }, status: :service_unavailable
        end

        def source_base_url
          RefineryRelay.configuration.public_base_url.presence || request.base_url
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
