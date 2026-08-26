# RefineryRelay

A Rails engine that adds the Niimble Relay LLM Chat Pod to Refinery CMS applications.

## Requirements

RefineryRelay supports Rails 8.1+ and Refinery CMS 4.1+. It requires the
`refinerycms-pods` 1.x extension, Sprockets JavaScript and stylesheet manifests,
Redis, and the `RELAY_CHAT_BASE_URL`, `RELAY_CHAT_TOKEN`, `RELAY_PUBLIC_BASE_URL`,
and `REDIS_URL` environment variables. The installer checks these requirements
before it changes the host application.

## Installation

Add the gem to the host application's Gemfile and run `bundle install`:

```ruby
gem "refinery_relay"
```

Run the installer from the consuming Refinery application:

```bash
bin/rails generate refinery_relay:install
```

The generator creates `config/initializers/refinery_relay.rb`, adds the direct host routes below,
and registers the engine JavaScript and CSS in the host's Sprockets manifests. It is safe to run
more than once and preserves an existing initializer.

The generated routes are:

```ruby
mount ActionCable.server => "/cable"
```

```ruby
get "/refinery_relay/api/relay/chat/availability",
    to: "refinery_relay/api/relay/chats#availability"
post "/refinery_relay/api/relay/chat",
     to: "refinery_relay/api/relay/chats#create"
```

The installer loads the browser controller globally so Swup and other partial-page navigation
libraries can enter a page containing the Pod:

```javascript
//= require refinery_relay/chat
```

The installer also adds the engine stylesheet to the host stylesheet manifest:

```css
/*
 *= require refinery_relay/application
 */
```

The stylesheet is scoped beneath `.refinery-relay-chat`. A host can override the theme without
copying engine CSS by setting the `--refinery-relay-*` custom properties on that root class.
The chat typography inherits the consuming website's computed font, including its configured
font stack and loaded webfont.
The Pod partial does not output separate asset tags, preventing duplicate JavaScript, Action Cable
subscriptions, or stylesheet requests.

Set `RELAY_CHAT_BASE_URL`, `RELAY_CHAT_TOKEN`, `RELAY_CHAT_TENANT_KEY`,
`RELAY_PUBLIC_BASE_URL`, and `REDIS_URL` in the host environment. The generated initializer is
available for optional application-specific overrides:

```ruby
RefineryRelay.configure do |config|
  config.chat_tenant_key = "my-refinery-site"
  config.chat_prompt_placeholder = "How many Comrades Marathons must I run to get a Green Number?"
end
```

The prompt placeholder is also available through `RELAY_CHAT_PROMPT_PLACEHOLDER`.
The default footer logo and its destination can be overridden with
`RELAY_CHAT_FOOTER_LOGO_URL` and `RELAY_CHAT_FOOTER_LOGO_LINK`.

The engine registers the `LLM Chat` Pod type. In Refinery admin, the Pod title is the chat
heading and Pod Item titles are suggested questions. The LLM Chat Pod does not use the generic
subtitle or body fields.

The `Chat content` section on an LLM Chat Pod controls that pod's prompt placeholder,
right-hand information card, footer logo image URL, and footer logo link. These values are
stored per pod; blank values fall back to the initializer defaults.

The chat theme can be configured once per Refinery site in the `Styling` section beneath
Suggested Questions when editing an `LLM Chat` Pod. The five available values are accent colour,
background colour, surface colour, text colour, and assistant response colour. Supporting colours and contrast-safe button
text are derived automatically and shared by all LLM Chat Pods. The generated initializer remains
the fallback when no admin values have been saved.

## Direct source feed

The gem converts published Refinery Pages and their associated Pods directly into Relay's
paginated JSON document format. It does not require or call an `/nlweb/rss` endpoint. It includes
structured page/Pod text plus linked Refinery images and resources as Relay citation assets. A
page delete or unpublish is retained as an explicit feed tombstone, so Relay removes it instead of
mistaking an absent record for unchanged content. Configure a private source token:

```text
RELAY_SOURCE_TOKEN=replace-with-a-private-token
```

The gem automatically provides `GET /refinery_relay/api/relay/documents`. Configure Relay's HTTP
feed source with that URL and the same bearer token. Each snapshot page represents one published
Refinery Page with its Page Parts and associated Pod text. Documents use stable identifiers, are
paginated for Relay, and contain the public Page URL for citations. Chat responses also apply the
same-origin check before rendering a citation link in the browser.

To request an immediate re-read after content changes, also configure Relay's source-sync
credential and the source UUID shown in the Relay console:

```text
RELAY_SYNC_TOKEN=sync-write-credential
RELAY_SOURCE_ID=relay-source-uuid
```

`RELAY_SYNC_BASE_URL` is optional and defaults to `RELAY_CHAT_BASE_URL`. The gem queues a
`POST /api/v1/sources/:source_id/sync` only after a Page, Page Part, Pod, Image, or Resource
transaction commits. Relay's normal polling remains the safety net if the source application or
Relay is temporarily unavailable.

## Development

Run the Ruby and browser test suites:

```bash
bundle exec rails test
npm run test:js
bin/rails test:system
```

The system suite requires Redis plus Google Chrome and a matching ChromeDriver. Together, these
suites install the engine into a disposable host, render a persisted Refinery Pod, and exercise the
Relay HTTP boundary, citations, Action Cable availability broadcasts, and the Swup replacement
lifecycle.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
