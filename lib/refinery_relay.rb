require "refinery_relay/version"
require "refinery_relay/configuration"
require "refinery_relay/pod_contract"
require "refinery_relay/pod_registration"
require "refinery_relay/pod_rendering"
require "refinery_relay/widget_markup"
require "refinery_relay/source_url_policy"
require "refinery_relay/source_sync_callbacks"
require "refinery_relay/engine"

module RefineryRelay
  class << self
    def configuration
      configuration = Configuration.from_settings
      configuration.redis = @runtime_configuration.redis if @runtime_configuration && @runtime_configuration.redis
      configuration
    end

    # Keep the initializer API used by existing Rails 5 Refinery hosts. New
    # installations store settings in RelaySetting, but older hosts commonly
    # configure the Redis connection in config/initializers/refinery_relay.rb.
    def configure
      @runtime_configuration ||= Configuration.new
      yield(@runtime_configuration)
    end

    def reset_configuration!
      @runtime_configuration = nil
    end
  end
end
