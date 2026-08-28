module RefineryRelay
  class Configuration
    DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS = 5
    DEFAULT_CHAT_READ_TIMEOUT_SECONDS = 45
    DEFAULT_SYNC_OPEN_TIMEOUT_SECONDS = 5
    DEFAULT_SYNC_READ_TIMEOUT_SECONDS = 20

    attr_accessor :source_token,
                  :source_types,
                  :public_base_url,
                  :chat_base_url,
                  :chat_token,
                  :sync_token,
                  :sync_source_id,
                  :sync_base_url,
                  :chat_tenant_key,
                  :chat_open_timeout_seconds,
                  :chat_read_timeout_seconds,
                  :sync_open_timeout_seconds,
                  :sync_read_timeout_seconds,
                  :redis_url,
                  :redis

    def self.from_settings(settings = RelaySetting.current)
      new(
        source_token: settings.source_token,
        source_types: settings.source_types,
        public_base_url: settings.public_base_url,
        chat_base_url: settings.chat_base_url,
        chat_token: settings.chat_token,
        sync_token: settings.sync_token,
        sync_source_id: settings.sync_source_id,
        sync_base_url: settings.sync_base_url,
        chat_tenant_key: settings.chat_tenant_key,
        chat_open_timeout_seconds: settings.chat_open_timeout_seconds,
        chat_read_timeout_seconds: settings.chat_read_timeout_seconds,
        sync_open_timeout_seconds: settings.sync_open_timeout_seconds,
        sync_read_timeout_seconds: settings.sync_read_timeout_seconds,
        redis_url: settings.redis_url
      )
    end

    def initialize(source_token: nil, source_types: RelaySetting::DEFAULT_SOURCE_TYPES,
                   public_base_url: "", chat_base_url: "", chat_token: nil,
                   sync_token: nil, sync_source_id: nil, sync_base_url: "",
                   chat_tenant_key: "refinery", chat_open_timeout_seconds: DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS,
                   chat_read_timeout_seconds: DEFAULT_CHAT_READ_TIMEOUT_SECONDS,
                   sync_open_timeout_seconds: DEFAULT_SYNC_OPEN_TIMEOUT_SECONDS,
                   sync_read_timeout_seconds: DEFAULT_SYNC_READ_TIMEOUT_SECONDS,
                   redis_url: nil)
      @source_token = source_token
      @source_types = Array(source_types).map(&:to_s) & SourceRegistry.keys
      @public_base_url = public_base_url
      @chat_base_url = chat_base_url
      @chat_token = chat_token
      @sync_token = sync_token
      @sync_source_id = sync_source_id
      @sync_base_url = sync_base_url
      @chat_tenant_key = chat_tenant_key
      @chat_open_timeout_seconds = chat_open_timeout_seconds
      @chat_read_timeout_seconds = chat_read_timeout_seconds
      @sync_open_timeout_seconds = sync_open_timeout_seconds
      @sync_read_timeout_seconds = sync_read_timeout_seconds
      @redis_url = redis_url
    end

    def source_types
      @source_types || RelaySetting::DEFAULT_SOURCE_TYPES
    end

    def public_base_url
      strip_trailing_slashes(@public_base_url)
    end

    def chat_base_url
      strip_trailing_slashes(@chat_base_url)
    end

    def sync_base_url
      strip_trailing_slashes(@sync_base_url.presence || @chat_base_url)
    end

    def sync_configured?
      sync_base_url.present? && sync_token.present? && sync_source_id.present?
    end

    def chat_tenant_key
      @chat_tenant_key.to_s.parameterize.presence || "refinery"
    end

    def chat_open_timeout_seconds
      bounded_integer(@chat_open_timeout_seconds, default: DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS, min: 1, max: 30)
    end

    def chat_read_timeout_seconds
      bounded_integer(@chat_read_timeout_seconds, default: DEFAULT_CHAT_READ_TIMEOUT_SECONDS, min: 1, max: 120)
    end

    def sync_open_timeout_seconds
      bounded_integer(@sync_open_timeout_seconds, default: DEFAULT_SYNC_OPEN_TIMEOUT_SECONDS, min: 1, max: 30)
    end

    def sync_read_timeout_seconds
      bounded_integer(@sync_read_timeout_seconds, default: DEFAULT_SYNC_READ_TIMEOUT_SECONDS, min: 1, max: 30)
    end

    private

    def strip_trailing_slashes(value)
      value.to_s.sub(%r{/+\z}, "")
    end

    def bounded_integer(value, default:, min:, max:)
      Integer(value).clamp(min, max)
    rescue ArgumentError, TypeError
      default
    end
  end
end
