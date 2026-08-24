# frozen_string_literal: true

module RefineryRelay
  module PageChangeTracking
    module_function

    def install!
      install_page_tracking
      install_page_part_tracking
      install_pod_tracking
      install_pod_item_tracking
    end

    def install_page_tracking
      install_on(defined?(::Refinery::Page) && ::Refinery::Page, :page) do |klass|
        klass.after_commit(on: %i[create update]) { PageChangeTracker.record_page(id, deleted: !PageChangeTracking.live_record?(self)) }
        klass.before_destroy { @_refinery_relay_page_id = id }
        klass.after_commit(on: :destroy) { PageChangeTracker.record_page(@_refinery_relay_page_id, deleted: true) }
      end
    end

    def install_page_part_tracking
      install_on(defined?(::Refinery::PagePart) && ::Refinery::PagePart, :page_part) do |klass|
        klass.after_commit(on: %i[create update]) { PageChangeTracker.record_pages(PageChangeTracker.page_ids_for(self)) }
        klass.before_destroy { @_refinery_relay_page_ids = PageChangeTracker.page_ids_for(self) }
        klass.after_commit(on: :destroy) { PageChangeTracker.record_pages(@_refinery_relay_page_ids) }
      end
    end

    def install_pod_tracking
      return unless defined?(::Refinery::Pods::Pod)

      install_on(::Refinery::Pods::Pod, :pod) do |klass|
        klass.after_commit(on: %i[create update]) { PageChangeTracker.record_pages(PageChangeTracker.page_ids_for(self)) }
        klass.before_destroy { @_refinery_relay_page_ids = PageChangeTracker.page_ids_for(self) }
        klass.after_commit(on: :destroy) { PageChangeTracker.record_pages(@_refinery_relay_page_ids) }
      end
    end

    def install_pod_item_tracking
      return unless defined?(::Refinery::Pods::PodItem)

      install_on(::Refinery::Pods::PodItem, :pod_item) do |klass|
        klass.after_commit(on: %i[create update]) { PageChangeTracker.record_pages(PageChangeTracker.page_ids_for(self)) }
        klass.before_destroy { @_refinery_relay_page_ids = PageChangeTracker.page_ids_for(self) }
        klass.after_commit(on: :destroy) { PageChangeTracker.record_pages(@_refinery_relay_page_ids) }
      end
    end

    def install_on(klass, name)
      return if klass.blank? || klass.instance_variable_defined?(:@_refinery_relay_change_tracking_installed)

      yield klass
      klass.instance_variable_set(:@_refinery_relay_change_tracking_installed, true)
    end

    def live_record?(record)
      record.respond_to?(:live?) ? record.live? : !record.respond_to?(:draft) || !record.draft?
    end
  end
end
