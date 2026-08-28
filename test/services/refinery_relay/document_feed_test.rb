# frozen_string_literal: true

require "test_helper"

class RefineryRelayDocumentFeedTest < ActiveSupport::TestCase
  FakePart = Struct.new(:id, :position, :title, :body, :updated_at)
  FakePod = Struct.new(:id, :position, :name, :pod_type, :body, :body2, :body3, :hidden_body, :updated_at,
                       :image, :mobile_image, :image2, :image3, :background_image, :file, :file2)
  FakePage = Struct.new(:id, :title, :slug, :url, :parts, :pods, :updated_at)
  FakeFaq = Struct.new(:id, :question, :answer, :updated_at, :slug)
  FakeBlogPost = Struct.new(:id, :title, :short_description, :custom_teaser, :body, :updated_at, :slug, :custom_url)
  FakeBinary = Struct.new(:url, :data)
  FakeImage = Struct.new(:id, :title, :alt, :image_mime_type, :updated_at, :url, :image) do
    def thumbnail(geometry:)
      FakeBinary.new("#{url}?geometry=#{geometry}", "thumbnail")
    end
  end

  FakeResource = Struct.new(:id, :title, :file_mime_type, :updated_at, :url, :file)

  setup do
    RefineryRelay::SourceRegistry.register(
      key: "faqs",
      label: "FAQs",
      description: "Questions and answers",
      model: FakeFaq.name,
      title: :question,
      fields: [ :answer ],
      path: "/faqs",
      scope: :live,
      route: :faq_path
    )
    RefineryRelay::SourceRegistry.register(
      key: "blog_posts",
      label: "Blog posts",
      model: FakeBlogPost.name,
      title: :title,
      fields: %i[custom_teaser body],
      scope: :live,
      route: :blog_post_path
    )
  end

  teardown do
    registered = RefineryRelay::SourceRegistry.instance_variable_get(:@registered_sources)
    %w[faqs blog_posts].each { |key| registered.delete(key) } if registered
    RefineryRelay::SourceRegistry.reset!
  end

  class TestFeed < RefineryRelay::DocumentFeed
    def initialize(pages:, source_records: {}, **options)
      @pages = pages
      @source_records = source_records
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

    def source_scope(source_type, last_id)
      return page_scope(last_id) if source_type == "pages"

      records = @source_records.fetch(source_type, []).select { |record| record.id > last_id }
      Class.new do
        def initialize(records)
          @records = records
        end

        def limit(size)
          @records.first(size)
        end
      end.new(records)
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

  test "prefers the page canonical URL over Refinery's generic page route" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    page = FakePage.new(1, "Blog", "blog", "/blog", [], [], now)
    route_helpers = Object.new
    route_helpers.define_singleton_method(:page_path) { |_record| "/pages/blog" }

    document = TestFeed.new(
      pages: [ page ],
      cursor: nil,
      public_base_url: "http://localhost:3001",
      route_helpers: route_helpers
    ).call.fetch("documents").first

    assert_equal "http://localhost:3001/blog", document.fetch("url")
  end

  test "excludes referenced images and files from the text-only Relay feed" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    image = FakeImage.new(8, "Start line", "Runners at the start line", "image/jpeg", now,
                          "/system/images/start.jpg", FakeBinary.new("/system/images/start.jpg", "image-bytes"))
    file = FakeResource.new(9, "Parking layout", "application/pdf", now,
                            "/system/resources/parking.pdf", FakeBinary.new("/system/resources/parking.pdf", "pdf-bytes"))
    pod = FakePod.new(2, 1, "Race assets", "content", "<p>See the downloadable layout.</p>", nil, nil, nil, now,
                      image, nil, nil, nil, nil, file, nil)
    page = FakePage.new(7, "Race information", "race-information", "/race-information", [], [ pod ], now)

    document = TestFeed.new(pages: [ page ], cursor: nil, public_base_url: "https://sit.example").call.fetch("documents").first
    assert_nil document.dig("metadata", "assets")
    assert_not_includes document.fetch("content"), "Parking layout"
  end

  test "only emits the configured non-page sources" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    faq = FakeFaq.new(4, "How does Relay work?", "Relay indexes the selected Refinery content.", now, nil)
    page = FakePage.new(7, "Not selected", "not-selected", "/not-selected", [], [], now)
    route_helpers = Object.new
    route_helpers.define_singleton_method(:faq_path) { |record| "/faqs/#{record.id}" }

    payload = TestFeed.new(
      pages: [ page ],
      source_records: { "faqs" => [ faq ] },
      source_types: [ "faqs" ],
      cursor: nil,
      public_base_url: "https://sit.example",
      route_helpers: route_helpers
    ).call

    assert_equal [ "faqs:4" ], payload.fetch("documents").map { |document| document.fetch("external_id") }
    document = payload.fetch("documents").first
    assert_equal "faq", document.fetch("content_type")
    assert_equal "https://sit.example/faqs/4", document.fetch("url")
    assert_includes document.fetch("content"), "Relay indexes the selected Refinery content."
  end

  test "does not emit source documents whose route resolves to the Refinery admin" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    faq = FakeFaq.new(4, "How does Relay work?", "Relay indexes the selected Refinery content.", now, nil)
    route_helpers = Object.new
    route_helpers.define_singleton_method(:faq_path) { |_record| "/refinery/faqs/4" }

    payload = TestFeed.new(
      pages: [],
      source_records: { "faqs" => [ faq ] },
      source_types: [ "faqs" ],
      cursor: nil,
      public_base_url: "https://sit.example",
      route_helpers: route_helpers
    ).call

    assert_equal [], payload.fetch("documents")
  end

  test "uses the Refinery route helper for source URLs" do
    now = Time.utc(2026, 8, 25, 12, 0, 0)
    post = FakeBlogPost.new(
      8, "Why marketing spend matters", nil, nil, "The article body.", now,
      "why-your-marketing-spend-matters-more-than-you-think",
      "Why-Your-Marketing-Spend-Matters-More-Than-You-Think"
    )
    route_helpers = Object.new
    route_helpers.define_singleton_method(:blog_post_path) { |record| "/blog/posts/#{record.slug}" }

    stub_class_method(Refinery, :route_for_model, ->(*) { "blog_post_path" }) do
      document = TestFeed.new(
        pages: [],
        source_records: { "blog_posts" => [ post ] },
        source_types: [ "blog_posts" ],
        cursor: nil,
        public_base_url: "http://localhost:3000",
        route_helpers: route_helpers
      ).call.fetch("documents").first

      assert_equal "http://localhost:3000/blog/posts/why-your-marketing-spend-matters-more-than-you-think", document.fetch("url")
    end
  end
end
