# frozen_string_literal: true

class CreateRefineryRelaySiteSettings < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:refinery_relay_site_settings)

    create_table :refinery_relay_site_settings do |table|
      table.string :accent_color
      table.string :background_color
      table.string :surface_color
      table.string :text_color
      table.timestamps
    end
  end

  def down
    drop_table :refinery_relay_site_settings if table_exists?(:refinery_relay_site_settings)
  end
end
