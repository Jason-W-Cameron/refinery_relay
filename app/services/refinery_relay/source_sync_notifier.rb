# frozen_string_literal: true

require "net/http"
require "uri"

module RefineryRelay
  # Notifies Relay only after a Refinery transaction has committed. Relay then
  # reads the configured feed with its separate source credential.
  class SourceSyncNotifier
    class UpstreamError < StandardError; end

    def self.call!
      new.call!
    end

    def self.enqueue
      return false unless RefineryRelay.configuration.sync_configured?

      RefineryRelay::SyncRelaySourceJob.perform_later
      true
    rescue StandardError => error
      Rails.logger.warn("Refinery Relay could not queue source sync: #{error.message}")
      false
    end

    def call!
      return false unless configuration.sync_configured?

      uri = sync_uri
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: configuration.sync_open_timeout_seconds,
        read_timeout: configuration.sync_read_timeout_seconds
      ) { |http| http.request(request_for(uri)) }

      return true if response.is_a?(Net::HTTPSuccess) && response.code.to_i == 202

      raise UpstreamError, "Relay source sync returned HTTP #{response.code}"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, URI::InvalidURIError => error
      raise UpstreamError, "Relay source sync is unavailable: #{error.message}"
    end

    private

    def configuration
      RefineryRelay.configuration
    end

    def sync_uri
      source_id = URI.encode_www_form_component(configuration.sync_source_id)
      URI.join("#{configuration.sync_base_url}/", "api/v1/sources/#{source_id}/sync")
    end

    def request_for(uri)
      Net::HTTP::Post.new(uri).tap do |request|
        request["Authorization"] = "Bearer #{configuration.sync_token}"
        request["Accept"] = "application/json"
      end
    end
  end
end
