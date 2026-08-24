module RefineryRelay
  class Configuration
    DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS = 5
    DEFAULT_CHAT_READ_TIMEOUT_SECONDS = 45

    attr_accessor :source_token,
                  :public_base_url,
                  :chat_base_url,
                  :chat_token,
                  :chat_tenant_key,
                  :chat_open_timeout_seconds,
                  :chat_read_timeout_seconds,
                  :documents_page_size,
                  :redis,
                  :broadcaster

    def self.from_env(env = ENV)
      new(
        source_token: env["RELAY_SOURCE_TOKEN"],
        public_base_url: env.fetch("RELAY_PUBLIC_BASE_URL", ""),
        chat_base_url: env.fetch("RELAY_CHAT_BASE_URL", ""),
        chat_token: env["RELAY_CHAT_TOKEN"],
        chat_tenant_key: env.fetch("RELAY_CHAT_TENANT_KEY", "refinery"),
        chat_open_timeout_seconds: env.fetch("RELAY_CHAT_OPEN_TIMEOUT_SECONDS", DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS),
        chat_read_timeout_seconds: env.fetch("RELAY_CHAT_READ_TIMEOUT_SECONDS", DEFAULT_CHAT_READ_TIMEOUT_SECONDS),
        documents_page_size: env.fetch("RELAY_DOCUMENTS_PAGE_SIZE", 25)
      )
    end

    def initialize(source_token: nil, public_base_url: "", chat_base_url: "", chat_token: nil,
                   chat_tenant_key: "refinery", chat_open_timeout_seconds: DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS,
                   chat_read_timeout_seconds: DEFAULT_CHAT_READ_TIMEOUT_SECONDS, documents_page_size: 25,
                   redis: nil, broadcaster: nil)
      @source_token = source_token
      @public_base_url = public_base_url
      @chat_base_url = chat_base_url
      @chat_token = chat_token
      @chat_tenant_key = chat_tenant_key
      @chat_open_timeout_seconds = chat_open_timeout_seconds
      @chat_read_timeout_seconds = chat_read_timeout_seconds
      @documents_page_size = documents_page_size
      @redis = redis
      @broadcaster = broadcaster
    end

    def public_base_url
      strip_trailing_slashes(@public_base_url)
    end

    def chat_base_url
      strip_trailing_slashes(@chat_base_url)
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

    def documents_page_size
      bounded_integer(@documents_page_size, default: 25, min: 1, max: 100)
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
