# frozen_string_literal: true

class CreateRefineryRelayDocumentChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :refinery_relay_document_changes do |table|
      table.string :external_id, null: false
      table.string :resource_type, null: false
      table.bigint :resource_id, null: false
      table.boolean :deleted, null: false, default: false
      table.datetime :occurred_at, null: false

      table.index [ :occurred_at, :id ], name: "index_refinery_relay_changes_on_occurred_at_and_id"
      table.index [ :resource_type, :resource_id ], name: "index_refinery_relay_changes_on_resource"
    end
  end
end
