# frozen_string_literal: true

require "base64"
require "json"

module RefineryRelay
  class DocumentFeed
    class InvalidCursor < StandardError; end

    def initialize(cursor:, base_url:, page_size: RefineryRelay.configuration.documents_page_size)
      @cursor = decode(cursor)
      @base_url = base_url
      @page_size = page_size.to_i.clamp(1, 100)
    end

    def call
      cursor ? page_for_cursor : initial_snapshot
    end

    private

    attr_reader :cursor, :base_url, :page_size

    def initial_snapshot
      snapshot_page(mode: "snapshot", last_id: 0, high_water: DocumentChange.maximum(:id).to_i)
    end

    def page_for_cursor
      case cursor.fetch("mode")
      when "snapshot"
        snapshot_page(**cursor.slice("mode", "last_id", "high_water"))
      when "events"
        event_page(after: cursor.fetch("after"))
      else
        raise InvalidCursor
      end
    rescue KeyError, TypeError, ArgumentError
      raise InvalidCursor
    end

    def snapshot_page(mode:, last_id:, high_water:)
      pages = live_pages.where("id > ?", Integer(last_id)).order(:id).limit(page_size).to_a
      documents = pages.filter_map { |page| PageDocumentSerializer.for_page(page, base_url:) }

      if pages.length == page_size
        next_cursor = encode(mode: mode, last_id: pages.last.id, high_water: Integer(high_water))
        envelope(documents, next_cursor:)
      else
        envelope(documents, cursor: encode(mode: "events", after: Integer(high_water)))
      end
    end

    def event_page(after:)
      changes = DocumentChange.after_sequence(Integer(after)).limit(page_size).to_a
      documents = changes.map { |change| document_for_change(change) }
      checkpoint = changes.last&.id || Integer(after)
      payload = envelope(documents, cursor: encode(mode: "events", after: checkpoint))
      payload["next_cursor"] = encode(mode: "events", after: checkpoint) if changes.length == page_size
      payload
    end

    def document_for_change(change)
      return tombstone(change.external_id) if change.deleted?

      page = page_class.find_by(id: change.resource_id)
      page&.respond_to?(:live?) && !page.live? ? tombstone(change.external_id) : PageDocumentSerializer.for_page(page, base_url:) || tombstone(change.external_id)
    end

    def tombstone(external_id)
      { "external_id" => external_id, "deleted" => true }
    end

    def live_pages
      scope = page_class.respond_to?(:live) ? page_class.live : page_class.where(draft: false)
      scope = scope.includes(:parts) if page_class.respond_to?(:reflect_on_association) && page_class.reflect_on_association(:parts)
      scope = scope.includes(:pods) if page_class.respond_to?(:reflect_on_association) && page_class.reflect_on_association(:pods)
      scope
    end

    def page_class
      raise InvalidCursor unless defined?(::Refinery::Page)

      ::Refinery::Page
    end

    def envelope(documents, cursor: nil, next_cursor: nil)
      payload = { "documents" => documents }
      payload["cursor"] = cursor if cursor.present?
      payload["next_cursor"] = next_cursor if next_cursor.present?
      payload
    end

    def encode(value)
      Base64.urlsafe_encode64(JSON.generate(value), padding: false)
    end

    def decode(value)
      return nil if value.blank?

      encoded = value.to_s
      encoded = encoded.ljust((encoded.length + 3) / 4 * 4, "=")
      JSON.parse(Base64.urlsafe_decode64(encoded))
    rescue ArgumentError, JSON::ParserError
      raise InvalidCursor
    end
  end
end
