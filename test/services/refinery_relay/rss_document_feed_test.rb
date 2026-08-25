# frozen_string_literal: true

require "test_helper"

class RefineryRelayRssDocumentFeedTest < ActiveSupport::TestCase
  class TestFeed < RefineryRelay::RssDocumentFeed
    attr_writer :response

    private

    def fetch_response(_uri)
      raise @response if @response.is_a?(Exception)

      @response
    end
  end

  setup do
    RefineryRelay.reset_configuration!
  end

  teardown do
    RefineryRelay.reset_configuration!
  end

  test "converts a page RSS item and its Pod summary into one Relay document" do
    feed = TestFeed.new(feed_url: "https://example.test/nlweb/rss")
    feed.response = successful_response(rss_body)

    payload = feed.call
    document = payload.fetch("documents").sole

    assert_equal "Race information", document.fetch("title")
    assert_equal "https://example.test/race-information", document.fetch("url")
    assert_equal "page", document.fetch("content_type")
    assert_equal "en-ZA", document.fetch("language")
    assert_includes document.fetch("content"), "Page introduction"
    assert_includes document.fetch("content"), "Pod registration details"
    assert_match(/\Arss:[a-f0-9]{64}\z/, document.fetch("external_id"))
    assert_match(/\A[a-f0-9]{64}\z/, document.fetch("content_hash"))
    assert_nil payload.fetch("next_cursor")
  end

  test "supports Atom entries" do
    feed = TestFeed.new(feed_url: "https://example.test/feed.atom")
    feed.response = successful_response(atom_body)

    document = feed.call.fetch("documents").sole

    assert_equal "Atom page", document.fetch("title")
    assert_equal "https://example.test/atom-page", document.fetch("url")
    assert_includes document.fetch("content"), "Atom page content"
    assert_equal "article", document.fetch("content_type")
  end

  test "converts Page and Pod items when an RSS feed contains mixed content types" do
    body = <<~XML
      <rss><channel>
        <item><title>About</title><link>https://example.test/about</link><category>Page</category></item>
        <item><title>Opening hours</title><link>https://example.test/about</link><guid>pods:12</guid><category>Pod</category><description>Weekdays from 09:00 to 17:00.</description></item>
        <item><title>News</title><link>https://example.test/news</link><category>Blog Post</category></item>
      </channel></rss>
    XML
    feed = TestFeed.new(feed_url: "https://example.test/feed.rss")
    feed.response = successful_response(body)

    documents = feed.call.fetch("documents")

    assert_equal [ "About", "Opening hours" ], documents.map { |document| document.fetch("title") }
    pod_document = documents.last
    assert_equal "pod", pod_document.fetch("content_type")
    assert_equal "https://example.test/about", pod_document.fetch("url")
    assert_includes pod_document.fetch("content"), "Weekdays from 09:00 to 17:00."
  end

  test "ignores feed items outside the configured public site" do
    RefineryRelay.configuration.public_base_url = "https://example.test"
    body = <<~XML
      <rss><channel>
        <item><title>About</title><link>https://example.test/about</link><category>Page</category></item>
        <item><title>External</title><link>https://other.example/article</link><category>Page</category></item>
      </channel></rss>
    XML
    feed = TestFeed.new(feed_url: "https://example.test/feed.rss")
    feed.response = successful_response(body)

    documents = feed.call.fetch("documents")

    assert_equal ["About"], documents.map { |document| document.fetch("title") }
  end

  test "rejects malformed XML" do
    feed = TestFeed.new(feed_url: "https://example.test/feed.rss")
    feed.response = successful_response("<rss><channel>")

    error = assert_raises(RefineryRelay::RssDocumentFeed::Error) { feed.call }

    assert_includes error.message, "invalid RSS feed"
  end

  test "rejects feeds over the item limit" do
    items = (RefineryRelay::RssDocumentFeed::MAX_ITEMS + 1).times.map do |index|
      "<item><title>Page #{index}</title><link>https://example.test/#{index}</link></item>"
    end.join
    feed = TestFeed.new(feed_url: "https://example.test/feed.rss")
    feed.response = successful_response("<rss><channel>#{items}</channel></rss>")

    error = assert_raises(RefineryRelay::RssDocumentFeed::Error) { feed.call }

    assert_includes error.message, "limit the feed"
  end

  test "reports network failures as feed errors" do
    feed = TestFeed.new(feed_url: "https://example.test/feed.rss")
    feed.response = Net::ReadTimeout.new("timed out")

    error = assert_raises(RefineryRelay::RssDocumentFeed::Error) do
      feed.call
    end

    assert_includes error.message, "could not fetch RSS feed"
  end

  private

  def successful_response(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def rss_body
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example website</title>
          <language>en-ZA</language>
          <item>
            <title>Race information</title>
            <link>https://example.test/race-information</link>
            <guid>pages:race-information</guid>
            <category>Page</category>
            <pubDate>Sun, 24 Aug 2026 11:00:00 +0200</pubDate>
            <description><![CDATA[
              <p>Page introduction</p>
              <section class="pods"><h4>Registration</h4><p>Pod registration details</p></section>
            ]]></description>
          </item>
        </channel>
      </rss>
    XML
  end

  def atom_body
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en">
        <title>Example Atom feed</title>
        <entry>
          <id>pages:atom-page</id>
          <title>Atom page</title>
          <link rel="alternate" href="https://example.test/atom-page" />
          <updated>2026-08-24T10:00:00Z</updated>
          <category term="Article" />
          <content type="html">&lt;p&gt;Atom page content&lt;/p&gt;</content>
        </entry>
      </feed>
    XML
  end
end
