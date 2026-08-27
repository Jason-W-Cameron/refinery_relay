# frozen_string_literal: true

module RefineryRelay
  module SourceSyncCallbacks
    extend ActiveSupport::Concern

    included do
      after_commit :refinery_relay_enqueue_source_sync, on: %i[create update destroy]
    end

    private

    def refinery_relay_enqueue_source_sync
      RefineryRelay::SourceSyncNotifier.enqueue
    end
  end

  module SourceTombstoneCallbacks
    extend ActiveSupport::Concern

    included do
      after_commit :refinery_relay_reconcile_source_tombstone, on: %i[create update destroy]
    end

    private

    def refinery_relay_reconcile_source_tombstone
      source_type = RefineryRelay::DocumentFeed.source_type_for(self.class)
      if source_type
        external_id = "#{source_type}:#{id}"
        if destroyed?
          RefineryRelay::SourceTombstone.record!(external_id)
        else
          RefineryRelay::SourceTombstone.clear!(external_id)
        end
      end
    ensure
      RefineryRelay::SourceSyncNotifier.enqueue
    end
  end

  module PageSourceSyncCallbacks
    extend ActiveSupport::Concern

    included do
      after_commit :refinery_relay_reconcile_tombstone, on: %i[create update destroy]
    end

    private

    def refinery_relay_reconcile_tombstone
      external_id = "pages:#{id}"
      if destroyed? || (respond_to?(:draft) && draft)
        RefineryRelay::SourceTombstone.record!(external_id)
      else
        RefineryRelay::SourceTombstone.clear!(external_id)
      end
    ensure
      RefineryRelay::SourceSyncNotifier.enqueue
    end
  end
end
