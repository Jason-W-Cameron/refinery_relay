# frozen_string_literal: true

class CreateRefineryRelaySourceTombstones < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:refinery_relay_source_tombstones)

    create_table :refinery_relay_source_tombstones do |table|
      table.string :external_id, null: false
      table.timestamps
    end
    add_index :refinery_relay_source_tombstones, :external_id, unique: true
  end

  def down
    drop_table :refinery_relay_source_tombstones if table_exists?(:refinery_relay_source_tombstones)
  end
end
