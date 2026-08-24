require "refinery_relay/version"
require "refinery_relay/configuration"
require "refinery_relay/pod_contract"
require "refinery_relay/pod_registration"
require "refinery_relay/chat_theme"
require "refinery_relay/pods_admin_controller"
require "refinery_relay/rss_document_feed"
require "refinery_relay/engine"

module RefineryRelay
  class << self
    def configuration
      @configuration ||= Configuration.from_env
    end

    def configure
      yield(configuration)
    end

    def configure_from_env!(env = ENV)
      @configuration = Configuration.from_env(env)
    end

    def reset_configuration!
      @configuration = Configuration.from_env
    end
  end
end
