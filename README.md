# RefineryRelay

A Rails engine that adds the Niimble Relay LLM Chat Pod to Refinery CMS applications.

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
The Pod partial does not output separate asset tags, preventing duplicate JavaScript, Action Cable
subscriptions, or stylesheet requests.

Set `RELAY_CHAT_BASE_URL`, `RELAY_CHAT_TOKEN`, `RELAY_CHAT_TENANT_KEY`,
`RELAY_PUBLIC_BASE_URL`, and `REDIS_URL` in the host environment. The generated initializer is
available for optional application-specific overrides:

```ruby
RefineryRelay.configure do |config|
  config.chat_tenant_key = "my-refinery-site"
end
```

The engine registers the `LLM Chat` Pod type. In Refinery admin, the Pod title is the chat
heading, subtitle is the welcome message, body is introductory content, and Pod Item titles are
suggested questions.

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
