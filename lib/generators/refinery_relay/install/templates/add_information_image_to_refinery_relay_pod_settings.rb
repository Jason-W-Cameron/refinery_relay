# frozen_string_literal: true

class AddInformationImageToRefineryRelayPodSettings < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:refinery_relay_pod_settings)

    add_column :refinery_relay_pod_settings, :information_image_id, :bigint unless column_exists?(:refinery_relay_pod_settings, :information_image_id)
  end

  def down
    remove_column :refinery_relay_pod_settings, :information_image_id if column_exists?(:refinery_relay_pod_settings, :information_image_id)
  end
end
