# frozen_string_literal: true

require "uri"

module RefineryRelay
  class SourceUrlPolicy
    HTTP_SCHEMES = %w[http https].freeze
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    def initialize(base_url:)
      @base_uri = parse_uri(base_url)
    end

    def allowed?(value)
      return false unless @base_uri

      uri = parse_uri(value)
      return false unless uri && HTTP_SCHEMES.include?(uri.scheme)
      return false unless same_host?(uri, @base_uri)
      return false unless effective_port(uri) == effective_port(@base_uri)

      uri.scheme == @base_uri.scheme
    end

    private

    def parse_uri(value)
      uri = URI.parse(value.to_s)
      return unless HTTP_SCHEMES.include?(uri.scheme) && uri.host.present?

      uri
    rescue URI::InvalidURIError
      nil
    end

    def same_host?(left, right)
      left_host = normalize_host(left.host)
      right_host = normalize_host(right.host)

      left_host == right_host || (loopback_host?(left_host) && loopback_host?(right_host))
    end

    def normalize_host(host)
      host.to_s.downcase.sub(/\Awww\./, "").delete_prefix("[").delete_suffix("]")
    end

    def loopback_host?(host)
      LOOPBACK_HOSTS.include?(host)
    end

    def effective_port(uri)
      uri.port || (uri.scheme == "https" ? 443 : 80)
    end
  end
end
