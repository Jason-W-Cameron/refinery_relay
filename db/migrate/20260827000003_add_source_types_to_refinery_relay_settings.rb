# frozen_string_literal: true

class AddSourceTypesToRefineryRelaySettings < ActiveRecord::Migration[8.1]
  def up
    add_column :refinery_relay_settings, :source_types, :text unless column_exists?(:refinery_relay_settings, :source_types)
  end

  def down
    remove_column :refinery_relay_settings, :source_types if column_exists?(:refinery_relay_settings, :source_types)
  end
end
