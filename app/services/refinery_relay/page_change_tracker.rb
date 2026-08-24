# frozen_string_literal: true

module RefineryRelay
  class PageChangeTracker
    class << self
      def record_page(page_id, deleted: false)
        return if page_id.blank?

        DocumentChange.create!(
          external_id: "pages:#{page_id}",
          resource_type: "Page",
          resource_id: page_id,
          deleted: deleted,
          occurred_at: Time.current
        )
      end

      def record_pages(page_ids, deleted: false)
        Array(page_ids).compact.uniq.each { |page_id| record_page(page_id, deleted:) }
      end

      def page_ids_for(record)
        return [] unless record

        if record.respond_to?(:pages)
          record.pages.pluck(:id)
        elsif record.respond_to?(:page)
          [ record.page&.id ]
        elsif record.respond_to?(:pod) && record.pod.respond_to?(:pages)
          record.pod.pages.pluck(:id)
        else
          []
        end.compact.uniq
      end
    end
  end
end
