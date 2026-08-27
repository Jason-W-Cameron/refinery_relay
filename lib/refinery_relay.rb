require "refinery_relay/version"
require "refinery_relay/configuration"
require "refinery_relay/pod_contract"
require "refinery_relay/pod_registration"
require "refinery_relay/source_url_policy"
require "refinery_relay/source_sync_callbacks"
require "refinery_relay/engine"

module RefineryRelay
  class << self
    def configuration
      Configuration.from_settings
    end

    def reset_configuration!
      # Settings are read from the database for every request, so there is no
      # process-local configuration cache to reset.
    end
  end
end
