# frozen_string_literal: true

require "uri"

module RefineryRelay
  # Verifies a candidate citation path with an in-process, anonymous GET
  # through the host Rails app. A named route is not enough: an engine page
  # can still fail while rendering a site's shared layout.
  class PublicEndpointValidator
    CACHE_TTL = 5.minutes
    MAX_REDIRECTS = 3

    Result = Struct.new(:available, :reason, :path, keyword_init: true) do
      def available?
        available
      end
    end

    def self.call(path:, host: nil, protocol: "http")
      new(path: path, host: host, protocol: protocol).call
    end

    def initialize(path:, host: nil, protocol: "http")
      @path = path.to_s
      @host = host.to_s.presence || "www.example.com"
      @protocol = protocol.to_s == "https" ? "https" : "http"
    end

    def call
      request_path = normalized_path_for_request
      return Result.new(available: false, reason: "does not have a public frontend URL", path: path) unless request_path

      cached = Rails.cache.fetch(cache_key(request_path), expires_in: CACHE_TTL) do
        validate(request_path).to_h
      end
      Result.new(**cached.symbolize_keys)
    rescue StandardError => error
      Result.new(available: false, reason: "could not be rendered (#{error.class})", path: path)
    end

    private

    attr_reader :path, :host, :protocol

    def normalized_path_for_request
      uri = URI.parse(path)
      return if uri.scheme.present? || uri.host.present?

      request_path = uri.path.to_s
      return unless request_path.start_with?("/")
      return if admin_path?(request_path)

      "#{request_path}#{uri.query.present? ? "?#{uri.query}" : ""}"
    rescue URI::InvalidURIError
      nil
    end

    def validate(initial_path)
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.host! host
      session.https! if protocol == "https"
      session.get(initial_path)

      redirects = 0
      while session.response.redirect? && redirects < MAX_REDIRECTS
        redirect_path = local_redirect_path(session.response.headers["Location"])
        return unavailable("redirects away from the public site", initial_path) unless redirect_path

        session.get(redirect_path)
        redirects += 1
      end

      status = session.response.status.to_i
      return Result.new(available: true, reason: nil, path: initial_path) if status.between?(200, 299)

      unavailable("returns HTTP #{status}", initial_path)
    rescue StandardError => error
      unavailable("raises #{error.class}", initial_path)
    end

    def local_redirect_path(location)
      uri = URI.parse(location.to_s)
      return if uri.scheme.present? && uri.host.to_s != host.split(":").first

      candidate = uri.path.to_s
      return unless candidate.start_with?("/") && !admin_path?(candidate)

      "#{candidate}#{uri.query.present? ? "?#{uri.query}" : ""}"
    rescue URI::InvalidURIError
      nil
    end

    def admin_path?(candidate)
      backend_route = defined?(::Refinery::Core) && ::Refinery::Core.respond_to?(:backend_route) ? ::Refinery::Core.backend_route : "refinery"
      candidate == "/#{backend_route}" || candidate.start_with?("/#{backend_route}/")
    end

    def unavailable(reason, request_path)
      Result.new(available: false, reason: reason, path: request_path)
    end

    def cache_key(request_path)
      [ "refinery_relay", "public_endpoint", host, protocol, request_path ]
    end
  end
end
