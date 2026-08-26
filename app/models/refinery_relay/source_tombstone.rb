# frozen_string_literal: true

module RefineryRelay
  # Preserves page deletions and unpublishes long enough for Relay to receive
  # an explicit `{ external_id, deleted: true }` feed record. A source feed
  # cannot infer a deletion from an absent page on one polling pass.
  class SourceTombstone < ApplicationRecord
    validates :external_id, presence: true, uniqueness: true

    class << self
      def available?
        connection.data_source_exists?(table_name)
      rescue ActiveRecord::ConnectionNotEstablished
        false
      end

      def record!(external_id)
        return unless available?

        where(external_id: external_id).first_or_create!
      end

      def clear!(external_id)
        return unless available?

        where(external_id: external_id).delete_all
      end
    end
  end
end
