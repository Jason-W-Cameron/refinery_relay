# frozen_string_literal: true

require "uri"

module RefineryRelay
  module Api
    module Relay
      class ChatsController < ActionController::API
        def availability
          render json: { available: RefineryRelay::CreditAvailability.available? }
        rescue RefineryRelay::CreditAvailability::CacheUnavailable
          render json: { available: false }
        end

        def create
          conversation_id = params[:conversation_id].presence
          return render_unavailable unless conversation_id || RefineryRelay::CreditAvailability.available?

          result = RefineryRelay::ChatClient.call(
            conversation_id: conversation_id,
            message: params.require(:message).to_s.strip,
            visitor_id: params[:visitor_id],
            context: context_params
          )

          return render_unavailable if credit_limit_exhausted?(result)

          render json: filter_source_citations(result.payload), status: result.status
        rescue ActionController::ParameterMissing
          render json: { error: "invalid_request", message: "message is required" }, status: :unprocessable_entity
        rescue RefineryRelay::CreditAvailability::CacheUnavailable
          render_unavailable
        rescue RefineryRelay::ChatClient::ConfigurationError, RefineryRelay::ChatClient::UpstreamError => e
          render json: { error: "chat_unavailable", message: e.message }, status: :service_unavailable
        end

        private

        def context_params
          params.fetch(:context, {}).permit(:current_url, :locale, :interface, :interface_type).to_h
        end

        # Relay's authenticated response is the authority for citation hosts.
        # Keep the array positions stable so answer markers such as [1] still
        # refer to the corresponding entry after an unsafe URL is removed.
        def filter_source_citations(payload)
          return payload unless payload.is_a?(Hash) && payload.key?("citations")

          citations = Array(payload["citations"])
          payload.merge(
            "citations" => citations.map do |citation|
              citation if citation.is_a?(Hash) && valid_citation_url?(citation["url"])
            end
          )
        end

        def valid_citation_url?(value)
          uri = URI.parse(value.to_s)
          uri.is_a?(URI::HTTP) && uri.host.present?
        rescue URI::InvalidURIError
          false
        end

        def credit_limit_exhausted?(result)
          return false unless result.status == 429 && result.payload["error"] == "credit_limit_exhausted"

          RefineryRelay::CreditAvailability.mark_unavailable!(resets_at: result.payload["resets_at"])
          true
        end

        def render_unavailable
          render json: { chat_unavailable: true }
        end
      end
    end
  end
end
