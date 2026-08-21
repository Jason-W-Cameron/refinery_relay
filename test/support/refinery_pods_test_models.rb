# frozen_string_literal: true

module Refinery
  module Pods
    class Pod < ActiveRecord::Base
      self.table_name = "refinery_pods"

      POD_TYPES = [ [ "Basic Text Editor", "content" ] ]

      has_many :pod_items,
        class_name: "Refinery::Pods::PodItem",
        foreign_key: :pod_id,
        inverse_of: :pod,
        dependent: :delete_all

      validates :name, presence: true

      def system_name
        pod_type
      end
    end

    class PodItem < ActiveRecord::Base
      self.table_name = "refinery_pod_items"

      belongs_to :pod,
        class_name: "Refinery::Pods::Pod",
        inverse_of: :pod_items
    end
  end
end

module RefineryPodsTestSchema
  module_function

  def install!
    connection = ActiveRecord::Base.connection
    unless connection.data_source_exists?("refinery_pods")
      connection.create_table :refinery_pods do |table|
        table.string :name, null: false
        table.string :title
        table.string :subtitle
        table.text :body
        table.string :pod_type
        table.integer :position
        table.timestamps
      end
    end

    return if connection.data_source_exists?("refinery_pod_items")

    connection.create_table :refinery_pod_items do |table|
      table.references :pod, null: false
      table.string :title
      table.integer :position
      table.timestamps
    end
  end
end
