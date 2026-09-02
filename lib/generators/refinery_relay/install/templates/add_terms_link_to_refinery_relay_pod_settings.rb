# frozen_string_literal: true

class AddTermsLinkToRefineryRelayPodSettings < ActiveRecord::Migration[6.0]
  def up
    return unless table_exists?(:refinery_relay_pod_settings)

    add_column :refinery_relay_pod_settings, :terms_link, :string unless column_exists?(:refinery_relay_pod_settings, :terms_link)
  end

  def down
    remove_column :refinery_relay_pod_settings, :terms_link if column_exists?(:refinery_relay_pod_settings, :terms_link)
  end
end
