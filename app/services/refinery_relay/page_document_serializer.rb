# frozen_string_literal: true

require "digest"
require "json"

module RefineryRelay
  class PageDocumentSerializer
    TEXT_FIELDS = %w[title name subtitle body large_text quote_text description question answer link_text].freeze

    class << self
      def for_page(page, base_url:)
        return unless page

        content, blocks, timestamps, pod_ids = content_for(page)
        title = clean(page.respond_to?(:title) ? page.title : "Page")
        return if title.blank? && content.blank?

        content = [ title, content ].compact_blank.join("\n\n")
        metadata = {
          "source" => "refinery",
          "page_id" => page.id,
          "pod_ids" => pod_ids,
          "draft" => page.respond_to?(:draft?) ? page.draft? : false
        }

        {
          "external_id" => "pages:#{page.id}",
          "title" => title.presence || "Page #{page.id}",
          "url" => absolute_url(page_url(page), base_url),
          "content" => content,
          "content_type" => "page",
          "language" => I18n.locale.to_s,
          "updated_at" => iso8601([ page.updated_at, *timestamps ].compact.max),
          "content_hash" => Digest::SHA256.hexdigest(JSON.generate(content: content, blocks: blocks, metadata: metadata)),
          "deleted" => false,
          "content_blocks" => blocks,
          "metadata" => metadata
        }
      end

      private

      def content_for(page)
        segments = []
        blocks = []
        timestamps = []
        pod_ids = []

        if page.respond_to?(:meta_description) && page.meta_description.present?
          append_segment(segments, blocks, "Description", page.meta_description)
        end

        if page.respond_to?(:parts)
          parts = page.parts.respond_to?(:order) ? page.parts.order(:position) : Array(page.parts)
          parts.each do |part|
            timestamps << part.updated_at if part.respond_to?(:updated_at)
            append_segment(segments, blocks, part.respond_to?(:title) ? part.title : nil, part.body)
          end
        end

        if page.respond_to?(:pods)
          pods = page.pods.respond_to?(:order) ? page.pods.order(:position) : Array(page.pods)
          pods.each do |pod|
            pod_ids << pod.id if pod.respond_to?(:id)
            timestamps << pod.updated_at if pod.respond_to?(:updated_at)
            pod_text, pod_blocks, pod_timestamps = pod_content(pod)
            segments << pod_text if pod_text.present?
            blocks.concat(pod_blocks)
            timestamps.concat(pod_timestamps)
          end
        end

        [ segments.compact_blank.join("\n\n"), blocks, timestamps, pod_ids.compact ]
      end

      def pod_content(pod)
        segments = []
        blocks = []
        timestamps = []

        TEXT_FIELDS.each do |field|
          next unless pod.respond_to?(field)

          value = pod.public_send(field)
          next if value.blank?

          append_segment(segments, blocks, field.humanize, value)
        end

        if pod.respond_to?(:pod_items)
          items = pod.pod_items.respond_to?(:order) ? pod.pod_items.order(:position) : Array(pod.pod_items)
          items.each do |item|
            timestamps << item.updated_at if item.respond_to?(:updated_at)
            item_text = TEXT_FIELDS.filter_map do |field|
              next unless item.respond_to?(field)

              value = item.public_send(field)
              value.present? ? "#{field.humanize}: #{clean(value)}" : nil
            end.join("\n")
            next if item_text.blank?

            segments << item_text
            blocks << { "kind" => "paragraph", "text" => item_text }
          end
        end

        [ segments.join("\n\n"), blocks, timestamps ]
      end

      def append_segment(segments, blocks, label, value)
        text = clean(value)
        return if text.blank?

        labelled = label.present? ? "#{clean(label)}: #{text}" : text
        segments << labelled
        blocks << { "kind" => "paragraph", "text" => labelled }
      end

      def clean(value)
        Rails::Html::FullSanitizer.new.sanitize(value.to_s)
          .gsub(/[ \t]+/, " ")
          .gsub(/\n{3,}/, "\n\n")
          .strip
      end

      def page_url(page)
        return page.url if page.respond_to?(:url) && page.url.present?
        return page.path if page.respond_to?(:path) && page.path.present?

        "/#{page.respond_to?(:slug) ? page.slug : page.id}"
      end

      def absolute_url(path, base_url)
        return path if path.to_s.match?(%r{\Ahttps?://}i)

        "#{base_url.to_s.sub(%r{/+\z}, "")}/#{path.to_s.sub(%r{\A/+}, "")}".sub(%r{://}, "§").gsub(%r{/+}, "/").sub("§", "://")
      end

      def iso8601(time)
        time&.utc&.iso8601
      end
    end
  end
end
