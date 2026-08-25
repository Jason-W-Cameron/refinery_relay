# frozen_string_literal: true

require "digest"
require "net/http"
require "nokogiri"
require "time"
require "uri"

module RefineryRelay
  class RssDocumentFeed
    class Error < StandardError; end

    MAX_RESPONSE_BYTES = 5 * 1024 * 1024
    MAX_ITEMS = 100
    INDEXABLE_CATEGORIES = %w[page pod].freeze

    def self.call(feed_url:)
      new(feed_url: feed_url).call
    end

    def initialize(feed_url:)
      @feed_url = feed_url
    end

    def call
      response = fetch_response(feed_uri)
      raise Error, "RSS feed returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s
      enforce_response_limit!(response, body)
      feed = Nokogiri::XML(body) { |config| config.strict.nonet }
      items = indexable_items(item_nodes(feed))
      raise Error, "RSS feed contains #{items.size} items; limit the feed to #{MAX_ITEMS} items" if items.size > MAX_ITEMS

      documents = items.map { |item| document_for(item, feed) }
      if documents.map { |document| document.fetch("external_id") }.uniq.size != documents.size
        raise Error, "RSS feed contains duplicate item identifiers"
      end

      {
        "documents" => documents,
        "cursor" => Digest::SHA256.hexdigest(body),
        "next_cursor" => nil
      }
    rescue Nokogiri::XML::SyntaxError, URI::InvalidURIError => e
      raise Error, "invalid RSS feed: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise Error, "could not fetch RSS feed: #{e.message}"
    end

    private

    def feed_uri
      raise Error, "RSS feed URL is required" if @feed_url.blank?

      uri = URI.parse(@feed_url)
      unless %w[http https].include?(uri.scheme) && uri.host.present?
        raise Error, "RSS feed must use an HTTP or HTTPS URL"
      end

      uri
    end

    def fetch_response(uri)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml"

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 20) do |http|
        http.request(request)
      end
    end

    def enforce_response_limit!(response, body)
      return unless response["Content-Length"].to_i > MAX_RESPONSE_BYTES || body.bytesize > MAX_RESPONSE_BYTES

      raise Error, "RSS response exceeds the #{MAX_RESPONSE_BYTES / (1024 * 1024)} MB limit"
    end

    def item_nodes(feed)
      rss_items = feed.xpath("//*[local-name()='channel']/*[local-name()='item']")
      return rss_items if rss_items.any?

      feed.xpath("/*[local-name()='feed']/*[local-name()='entry']")
    end

    def document_for(item, feed)
      url = item_url(item)
      identifier = child_text(item, "guid").presence || child_text(item, "id").presence || url
      title = clean_text(child_text(item, "title")).presence || "Untitled RSS item"
      content = [ title, item_content(item) ].select(&:present?).uniq.join("\n\n")
      categories = item_categories(item)

      {
        "external_id" => "rss:#{Digest::SHA256.hexdigest(identifier)}",
        "title" => title,
        "url" => url,
        "content" => content,
        "content_type" => categories.first.to_s.parameterize(separator: "_").presence || "rss_item",
        "language" => feed_language(feed),
        "updated_at" => item_updated_at(item, feed).iso8601,
        "content_hash" => Digest::SHA256.hexdigest(content),
        "metadata" => {
          "feed_title" => feed_title(feed),
          "categories" => categories,
          "rss_identifier" => identifier
        }.compact
      }
    end

    def item_url(item)
      link = item.xpath("./*[local-name()='link']").find do |candidate|
        candidate["rel"].blank? || candidate["rel"] == "alternate"
      end
      raw_url = link&.[]("href").presence || link&.text.to_s.strip
      raise Error, "RSS item is missing a link" if raw_url.blank?

      uri = URI.join(@feed_url, raw_url)
      unless %w[http https].include?(uri.scheme) && uri.host.present?
        raise Error, "RSS item link must use HTTP or HTTPS"
      end

      uri.to_s
    end

    def item_content(item)
      value = %w[encoded content description summary].map do |name|
        child_text(item, name).presence
      end.compact.first
      clean_text(value)
    end

    # A combined Refinery feed can contain arbitrary CMS records. Prefer its
    # public Pages and Pods, but retain the old all-items behaviour for feeds
    # that do not label their records with either category.
    def indexable_items(items)
      categorized_items = items.select do |item|
        item_categories(item).any? do |category|
          INDEXABLE_CATEGORIES.include?(category.to_s.downcase)
        end
      end

      selected_items = categorized_items.any? ? categorized_items : items
      selected_items.select { |item| source_url_policy.allowed?(item_url(item)) }
    end

    def source_url_policy
      @source_url_policy ||= RefineryRelay::SourceUrlPolicy.new(
        base_url: RefineryRelay.configuration.public_base_url.presence || @feed_url
      )
    end

    def item_categories(item)
      item.xpath("./*[local-name()='category']").map do |category|
        clean_text(category["term"].presence || category.text).presence
      end.compact
    end

    def item_updated_at(item, feed)
      raw_date = %w[updated published pubDate date].map do |name|
        child_text(item, name).presence
      end.compact.first
      raw_date ||= %w[lastBuildDate updated].map do |name|
        child_text(feed_container(feed), name).presence
      end.compact.first

      raw_date.present? ? Time.parse(raw_date) : Time.current
    rescue ArgumentError
      raise Error, "RSS item has an invalid publication date"
    end

    def feed_container(feed)
      feed.at_xpath("//*[local-name()='channel']") || feed.root
    end

    def feed_title(feed)
      clean_text(child_text(feed_container(feed), "title")).presence
    end

    def feed_language(feed)
      container = feed_container(feed)
      child_text(container, "language").presence ||
        container.attribute_with_ns("lang", "http://www.w3.org/XML/1998/namespace")&.value.presence ||
        "en"
    end

    def child_text(node, name)
      node&.at_xpath("./*[local-name()='#{name}']")&.text.to_s
    end

    def clean_text(value)
      Nokogiri::HTML.fragment(value.to_s).xpath(".//text()").map(&:text).join(" ").squish
    end
  end
end
