# frozen_string_literal: true

class AddFooterLogoSettingsToRefineryRelayPodSettings < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:refinery_relay_pod_settings)

    add_column :refinery_relay_pod_settings, :footer_logo_url, :string unless column_exists?(:refinery_relay_pod_settings, :footer_logo_url)
    add_column :refinery_relay_pod_settings, :footer_logo_link, :string unless column_exists?(:refinery_relay_pod_settings, :footer_logo_link)
  end

  def down
    remove_column :refinery_relay_pod_settings, :footer_logo_link if column_exists?(:refinery_relay_pod_settings, :footer_logo_link)
    remove_column :refinery_relay_pod_settings, :footer_logo_url if column_exists?(:refinery_relay_pod_settings, :footer_logo_url)
  end
end
