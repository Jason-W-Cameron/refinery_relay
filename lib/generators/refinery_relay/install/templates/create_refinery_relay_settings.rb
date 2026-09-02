# frozen_string_literal: true

class CreateRefineryRelaySettings < ActiveRecord::Migration[6.0]
  def up
    return if table_exists?(:refinery_relay_settings)

    create_table :refinery_relay_settings do |table|
      table.text :source_token
      table.string :public_base_url
      table.string :chat_base_url
      table.text :chat_token
      table.text :sync_token
      table.string :sync_source_id
      table.string :sync_base_url
      table.string :chat_tenant_key, default: "refinery", null: false
      table.integer :chat_open_timeout_seconds, default: 5, null: false
      table.integer :chat_read_timeout_seconds, default: 45, null: false
      table.integer :sync_open_timeout_seconds, default: 5, null: false
      table.integer :sync_read_timeout_seconds, default: 20, null: false
      table.text :redis_url
      table.text :widget_markup
      table.timestamps
    end
  end

  def down
    drop_table :refinery_relay_settings if table_exists?(:refinery_relay_settings)
  end
end
