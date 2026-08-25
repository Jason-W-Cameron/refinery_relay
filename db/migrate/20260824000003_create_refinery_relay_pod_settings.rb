# frozen_string_literal: true

class CreateRefineryRelayPodSettings < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:refinery_relay_pod_settings)

    create_table :refinery_relay_pod_settings do |table|
      table.bigint :pod_id, null: false
      table.string :prompt_placeholder
      table.text :information_text
      table.timestamps
    end

    add_index :refinery_relay_pod_settings, :pod_id, unique: true
  end

  def down
    drop_table :refinery_relay_pod_settings if table_exists?(:refinery_relay_pod_settings)
  end
end
