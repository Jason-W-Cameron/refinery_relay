# frozen_string_literal: true

require "test_helper"
require "support/refinery_pods_test_models"

module Refinery
  class Page < ActiveRecord::Base
    self.table_name = "refinery_pages"

    has_many :parts,
      class_name: "Refinery::PagePart",
      foreign_key: :refinery_page_id,
      dependent: :delete_all
    has_and_belongs_to_many :pods,
      class_name: "Refinery::Pods::Pod",
      join_table: "refinery_pages_pods"

    scope :live, -> { where(draft: false) }

    def live?
      !draft?
    end

    def url
      "/#{slug}"
    end
  end

  class PagePart < ActiveRecord::Base
    self.table_name = "refinery_page_parts"
    belongs_to :page, foreign_key: :refinery_page_id, optional: true
  end
end

Refinery::Pods::Pod.class_eval do
  has_and_belongs_to_many :pages,
    class_name: "Refinery::Page",
    join_table: "refinery_pages_pods"
end

module RefineryRelayDocumentFeedSchema
  module_function

  def install!
    connection = ActiveRecord::Base.connection
    unless connection.data_source_exists?("refinery_pages")
      connection.create_table :refinery_pages do |table|
        table.string :title
        table.string :slug
        table.boolean :draft, default: false, null: false
        table.timestamps
      end
    end

    unless connection.data_source_exists?("refinery_page_parts")
      connection.create_table :refinery_page_parts do |table|
        table.references :refinery_page
        table.string :title
        table.text :body
        table.integer :position
        table.timestamps
      end
    end

    return if connection.data_source_exists?("refinery_pages_pods")

    connection.create_table :refinery_pages_pods, id: false do |table|
      table.integer :page_id
      table.integer :pod_id
    end
  end
end

class RefineryRelayDocumentFeedTest < ActiveSupport::TestCase
  setup do
    RefineryPodsTestSchema.install!
    RefineryRelayDocumentFeedSchema.install!
    RefineryRelay::DocumentChange.delete_all
    Refinery::PagePart.delete_all
    Refinery::Page.delete_all
    Refinery::Pods::Pod.delete_all

    @page = Refinery::Page.create!(title: "About Simon Says", slug: "about", draft: false)
    @page.parts.create!(title: "Body", body: "We build useful things.", position: 1)
    @pod = Refinery::Pods::Pod.create!(
      name: "Company details",
      title: "Our approach",
      body: "We work with ambitious teams.",
      pod_type: "content"
    )
    @page.pods << @pod
  end

  test "emits one page document containing page and pod content" do
    payload = RefineryRelay::DocumentFeed.new(cursor: nil, base_url: "https://example.test").call
    document = payload.fetch("documents").fetch(0)

    assert_equal "pages:#{@page.id}", document.fetch("external_id")
    assert_equal "https://example.test/about", document.fetch("url")
    assert_includes document.fetch("content"), "We build useful things."
    assert_includes document.fetch("content"), "We work with ambitious teams."
    refute payload.fetch("documents").any? { |item| item["external_id"].to_s.start_with?("pods:") }
  end

  test "emits a changed page when an associated pod changes" do
    initial = RefineryRelay::DocumentFeed.new(cursor: nil, base_url: "https://example.test").call
    @pod.update!(body: "We work with thoughtful teams.")
    RefineryRelay::PageChangeTracker.record_page(@page.id)

    payload = RefineryRelay::DocumentFeed.new(cursor: initial.fetch("cursor"), base_url: "https://example.test").call
    document = payload.fetch("documents").find { |item| item["external_id"] == "pages:#{@page.id}" }

    assert_includes document.fetch("content"), "thoughtful teams"
  end

  test "emits a tombstone for an unpublished page" do
    initial = RefineryRelay::DocumentFeed.new(cursor: nil, base_url: "https://example.test").call
    @page.update!(draft: true)
    RefineryRelay::PageChangeTracker.record_page(@page.id, deleted: true)

    payload = RefineryRelay::DocumentFeed.new(cursor: initial.fetch("cursor"), base_url: "https://example.test").call
    document = payload.fetch("documents").find { |item| item["external_id"] == "pages:#{@page.id}" }

    assert_equal({ "external_id" => "pages:#{@page.id}", "deleted" => true }, document)
  end
end
