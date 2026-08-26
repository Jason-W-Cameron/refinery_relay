# frozen_string_literal: true

class AddAssistantResponseColorToRefineryRelaySiteSettings < ActiveRecord::Migration[5.1]
  def up
    return unless table_exists?(:refinery_relay_site_settings)
    return if column_exists?(:refinery_relay_site_settings, :assistant_response_color)

    add_column :refinery_relay_site_settings, :assistant_response_color, :string
  end

  def down
    return unless table_exists?(:refinery_relay_site_settings)
    return unless column_exists?(:refinery_relay_site_settings, :assistant_response_color)

    remove_column :refinery_relay_site_settings, :assistant_response_color
  end
end
