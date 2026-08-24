module RefineryRelay
  class Configuration
    DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS = 5
    DEFAULT_CHAT_READ_TIMEOUT_SECONDS = 45
    DEFAULT_CHAT_ACCENT_COLOR = "#fbbf24"
    DEFAULT_CHAT_BACKGROUND_COLOR = "#101010"
    DEFAULT_CHAT_SURFACE_COLOR = "#181818"
    DEFAULT_CHAT_TEXT_COLOR = "#f5f5f5"

    attr_accessor :source_token,
                  :rss_feed_url,
                  :public_base_url,
                  :chat_base_url,
                  :chat_token,
                  :chat_tenant_key,
                  :chat_open_timeout_seconds,
                  :chat_read_timeout_seconds,
                  :chat_accent_color,
                  :chat_background_color,
                  :chat_surface_color,
                  :chat_text_color,
                  :redis,
                  :broadcaster

    def self.from_env(env = ENV)
      new(
        source_token: env["RELAY_SOURCE_TOKEN"],
        rss_feed_url: env.fetch("RELAY_RSS_FEED_URL", ""),
        public_base_url: env.fetch("RELAY_PUBLIC_BASE_URL", ""),
        chat_base_url: env.fetch("RELAY_CHAT_BASE_URL", ""),
        chat_token: env["RELAY_CHAT_TOKEN"],
        chat_tenant_key: env.fetch("RELAY_CHAT_TENANT_KEY", "refinery"),
        chat_open_timeout_seconds: env.fetch("RELAY_CHAT_OPEN_TIMEOUT_SECONDS", DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS),
        chat_read_timeout_seconds: env.fetch("RELAY_CHAT_READ_TIMEOUT_SECONDS", DEFAULT_CHAT_READ_TIMEOUT_SECONDS),
        chat_accent_color: env.fetch("RELAY_CHAT_ACCENT_COLOR", DEFAULT_CHAT_ACCENT_COLOR),
        chat_background_color: env.fetch("RELAY_CHAT_BACKGROUND_COLOR", DEFAULT_CHAT_BACKGROUND_COLOR),
        chat_surface_color: env.fetch("RELAY_CHAT_SURFACE_COLOR", DEFAULT_CHAT_SURFACE_COLOR),
        chat_text_color: env.fetch("RELAY_CHAT_TEXT_COLOR", DEFAULT_CHAT_TEXT_COLOR)
      )
    end

    def initialize(source_token: nil, rss_feed_url: "", public_base_url: "", chat_base_url: "", chat_token: nil,
                   chat_tenant_key: "refinery", chat_open_timeout_seconds: DEFAULT_CHAT_OPEN_TIMEOUT_SECONDS,
                   chat_read_timeout_seconds: DEFAULT_CHAT_READ_TIMEOUT_SECONDS,
                   chat_accent_color: DEFAULT_CHAT_ACCENT_COLOR,
                   chat_background_color: DEFAULT_CHAT_BACKGROUND_COLOR,
                   chat_surface_color: DEFAULT_CHAT_SURFACE_COLOR,
                   chat_text_color: DEFAULT_CHAT_TEXT_COLOR,
                   redis: nil, broadcaster: nil)
      @source_token = source_token
      @rss_feed_url = rss_feed_url
      @public_base_url = public_base_url
      @chat_base_url = chat_base_url
      @chat_token = chat_token
      @chat_tenant_key = chat_tenant_key
      @chat_open_timeout_seconds = chat_open_timeout_seconds
      @chat_read_timeout_seconds = chat_read_timeout_seconds
      @chat_accent_color = chat_accent_color
      @chat_background_color = chat_background_color
      @chat_surface_color = chat_surface_color
      @chat_text_color = chat_text_color
      @redis = redis
      @broadcaster = broadcaster
    end

    def public_base_url
      strip_trailing_slashes(@public_base_url)
    end

    def rss_feed_url
      @rss_feed_url.to_s.strip
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
