# frozen_string_literal: true

class RenameLlmChatPodTypeToRelayChat < ActiveRecord::Migration[6.0]
  def up
    return unless table_exists?(:refinery_pods)

    execute <<~SQL
      UPDATE #{quote_table_name(:refinery_pods)}
      SET pod_type = 'relay_chat'
      WHERE pod_type = 'llm_chat'
    SQL
  end

  def down
    return unless table_exists?(:refinery_pods)

    execute <<~SQL
      UPDATE #{quote_table_name(:refinery_pods)}
      SET pod_type = 'llm_chat'
      WHERE pod_type = 'relay_chat'
    SQL
  end
end
