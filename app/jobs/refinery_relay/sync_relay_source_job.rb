# frozen_string_literal: true

module RefineryRelay
  class SyncRelaySourceJob < ApplicationJob
    queue_as :default

    retry_on SourceSyncNotifier::UpstreamError, wait: 30.seconds, attempts: 5

    def perform
      SourceSyncNotifier.call!
    end
  end
end
