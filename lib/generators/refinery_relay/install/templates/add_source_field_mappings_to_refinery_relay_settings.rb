# frozen_string_literal: true

class AddSourceFieldMappingsToRefineryRelaySettings < ActiveRecord::Migration[8.1]
  def up
    add_column :refinery_relay_settings, :source_field_mappings, :text unless column_exists?(:refinery_relay_settings, :source_field_mappings)
  end

  def down
    remove_column :refinery_relay_settings, :source_field_mappings if column_exists?(:refinery_relay_settings, :source_field_mappings)
  end
end
