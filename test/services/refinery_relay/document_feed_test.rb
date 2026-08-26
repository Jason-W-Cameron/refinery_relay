# frozen_string_literal: true

require "test_helper"

class RefineryRelayDocumentFeedTest < ActiveSupport::TestCase
  FakePart = Struct.new(:id, :position, :title, :body, :updated_at)
  FakePod = Struct.new(:id, :position, :name, :pod_type, :body, :body2, :body3, :hidden_body, :updated_at,
                       :image, :mobile_image, :image2, :image3, :background_image, :file, :file2)
  FakePage = Struct.new(:id, :title, :slug, :url, :parts, :pods, :updated_at)
  FakeBinary = Struct.new(:url, :data)
  FakeImage = Struct.new(:id, :title, :alt, :image_mime_type, :updated_at, :url, :image) do
    def thumbnail(geometry:)
      FakeBinary.new("#{url}?geometry=#{geometry}", "thumbnail")
    end
  end

  FakeResource = Struct.new(:id, :title, :file_mime_type, :updated_at, :url, :file)

  class TestFeed < RefineryRelay::DocumentFeed
    def initialize(pages:, **options)
      @pages = pages
      super(**options)
    end

    private

    def page_scope(last_id)
      pages = @pages.select { |page| page.id > last_id }
      Class.new do
        def initialize(records)
          @records = records
        end

        def limit(size)
          @records.first(size)
        end
      end.new(pages)
    end
  end

  test "serializes published page parts and pods without requesting RSS" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    page = FakePage.new(
      7, "Race information", "race-information", "/race-information",
      [ FakePart.new(1, 0, "Overview", "<p>Enter the race before Friday.</p>", now) ],
      [ FakePod.new(2, 1, "Registration", "content", "<p>Bring your ID.</p>", nil, nil, nil, now) ],
      now
    )

    payload = TestFeed.new(pages: [ page ], cursor: nil, public_base_url: "https://sit.example").call
    document = payload.fetch("documents").first

    assert_equal "pages:7", document.fetch("external_id")
    assert_equal "https://sit.example/race-information", document.fetch("url")
    assert_equal "page", document.fetch("content_type")
    assert_includes document.fetch("content"), "Enter the race before Friday."
    assert_includes document.fetch("content"), "Bring your ID."
    assert_equal [
      { "kind" => "heading", "level" => 1, "text" => "Race information" },
      { "kind" => "heading", "level" => 2, "text" => "Overview" },
      { "kind" => "paragraph", "text" => "Enter the race before Friday." },
      { "kind" => "heading", "level" => 2, "text" => "Registration" },
      { "kind" => "paragraph", "text" => "Bring your ID." }
    ], document.fetch("content_blocks")
    assert_equal [ "content" ], document.dig("metadata", "pod_types")
    assert_nil payload["next_cursor"]
  end

  test "paginates direct documents and starts a new snapshot after completion" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    pages = [
      FakePage.new(1, "One", "one", "/one", [], [], now),
      FakePage.new(2, "Two", "two", "/two", [], [], now)
    ]

    first = TestFeed.new(pages: pages, cursor: nil, public_base_url: "https://sit.example", page_size: 1).call
    assert_equal [ "pages:1" ], first.fetch("documents").map { |document| document.fetch("external_id") }
    assert_equal first.fetch("cursor"), first.fetch("next_cursor")

    second = TestFeed.new(pages: pages, cursor: first.fetch("next_cursor"), public_base_url: "https://sit.example", page_size: 1).call
    assert_equal [ "pages:2" ], second.fetch("documents").map { |document| document.fetch("external_id") }
    assert_nil second["next_cursor"]

    restarted = TestFeed.new(pages: pages, cursor: second.fetch("cursor"), public_base_url: "https://sit.example", page_size: 1).call
    assert_equal [ "pages:1" ], restarted.fetch("documents").map { |document| document.fetch("external_id") }
  end

  test "starts a direct snapshot when upgrading from an RSS hash cursor" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    page = FakePage.new(1, "One", "one", "/one", [], [], now)

    payload = TestFeed.new(
      pages: [ page ],
      cursor: "a" * 64,
      public_base_url: "https://sit.example"
    ).call

    assert_equal [ "pages:1" ], payload.fetch("documents").map { |document| document.fetch("external_id") }
  end

  test "normalizes a legacy page URL that contains spaces" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    page = FakePage.new(1, "Terms", "terms", "/terms and conditions", [], [], now)

    document = TestFeed.new(pages: [ page ], cursor: nil, public_base_url: "https://sit.example").call.fetch("documents").first

    assert_equal "https://sit.example/terms%20and%20conditions", document.fetch("url")
  end

  test "includes referenced Refinery images and files as Relay citation assets" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    image = FakeImage.new(8, "Start line", "Runners at the start line", "image/jpeg", now,
                          "/system/images/start.jpg", FakeBinary.new("/system/images/start.jpg", "image-bytes"))
    file = FakeResource.new(9, "Parking layout", "application/pdf", now,
                            "/system/resources/parking.pdf", FakeBinary.new("/system/resources/parking.pdf", "pdf-bytes"))
    pod = FakePod.new(2, 1, "Race assets", "content", "<p>See the downloadable layout.</p>", nil, nil, nil, now,
                      image, nil, nil, nil, nil, file, nil)
    page = FakePage.new(7, "Race information", "race-information", "/race-information", [], [ pod ], now)

    document = TestFeed.new(pages: [ page ], cursor: nil, public_base_url: "https://sit.example").call.fetch("documents").first
    assets = document.dig("metadata", "assets")

    assert_equal [ "images:8", "files:9" ], assets.map { |asset| asset.fetch("external_id") }
    assert_equal "https://sit.example/system/images/start.jpg", assets.first.fetch("url")
    assert_equal "https://sit.example/system/images/start.jpg?geometry=480x480%3E", assets.first.fetch("thumbnail_url")
    assert_equal "image", assets.first.fetch("kind")
    assert_equal "pdf", assets.last.fetch("kind")
    assert_match(/\A[a-f0-9]{64}\z/, assets.first.fetch("content_hash"))
    assert_includes document.fetch("content"), "Parking layout"
  end
end
