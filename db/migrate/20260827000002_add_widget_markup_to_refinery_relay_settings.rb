# frozen_string_literal: true

class AddWidgetMarkupToRefineryRelaySettings < ActiveRecord::Migration[5.1]
  def up
    add_column :refinery_relay_settings, :widget_markup, :text unless column_exists?(:refinery_relay_settings, :widget_markup)
  end

  def down
    remove_column :refinery_relay_settings, :widget_markup if column_exists?(:refinery_relay_settings, :widget_markup)
  end
end
