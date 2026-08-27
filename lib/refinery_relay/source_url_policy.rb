# frozen_string_literal: true

require "uri"

module RefineryRelay
  class SourceUrlPolicy
    # Relay's authenticated response establishes citation provenance. This
    # policy validates URL structure and scheme only; it does not restrict
    # citations to a configured source host.
    HTTP_SCHEMES = %w[http https].freeze

    def allowed?(value)
      uri = parse_uri(value)
      uri && HTTP_SCHEMES.include?(uri.scheme)
    end

    private

    def parse_uri(value)
      uri = URI.parse(value.to_s)
      return unless HTTP_SCHEMES.include?(uri.scheme) && uri.host.present?

      uri
    rescue URI::InvalidURIError
      nil
    end

  end
end
