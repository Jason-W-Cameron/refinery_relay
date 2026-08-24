# frozen_string_literal: true

module RefineryRelay
  class DocumentChange < ApplicationRecord
    self.table_name = "refinery_relay_document_changes"

    scope :ordered, -> { order(:id) }
    scope :after_sequence, ->(sequence) { where("id > ?", sequence.to_i).ordered }

    validates :external_id, :resource_type, :resource_id, presence: true
  end
end
