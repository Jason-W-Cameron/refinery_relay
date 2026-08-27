# RefineryRelay

A Rails engine that connects Refinery CMS content to Niimble Relay.

This gem does not ship a visual implementation. It registers the `Relay Chat`
(`llm_chat`) Pod type and renders only a `<relay-llm-widget>` mount element.
Relay owns all browser UI, branding, styles, images, and interactive chat
behavior.

## Installation

Add the gem to a Refinery application and run:

```bash
bin/rails generate refinery_relay:install
```

The installer configures the backend routes and adds the Relay settings and
source-tombstone migrations. It does not create an initializer or alter
JavaScript, stylesheet, or Action Cable manifests.

Run `bin/rails db:migrate`, then open **Relay Settings** in the Refinery admin
sidebar. This single page stores selected source types, the generated feed
bearer token, and direct Relay widget markup in `refinery_relay_settings`. No
Relay environment variables or host initializer are required. The public Relay
widget communicates directly with Relay using a public widget key; private chat
credentials are never stored in the browser.

The **Sources to ingest** checkboxes control which Refinery content families
are exported by the direct feed: Pages, Blog posts, Works, Expertises, FAQs,
Industries, Local businesses, and Brands. Pages are enabled by default;
optional sources are skipped when their Refinery extension is not installed.

## Pod compatibility

The gem continues to register the `Relay Chat` Pod type with
`refinerycms-pods`. Existing and new `llm_chat` pod records remain selectable.
The engine also adds `llm_chat` automatically when a host layout passes an
explicit `pod_types` list to Refinery's shared pod renderer, so host layouts do
not need a Relay-specific edit. It is rendered once per view context to avoid
duplicates across multiple pod regions.
Use **Relay Settings → LLM widget** in Refinery admin to enter the Relay widget
HTML/script. That trusted markup is rendered inside `<relay-llm-widget>` exactly
where a Relay Chat Pod is placed.

## Direct source feed

The gem converts the selected Refinery content families into Relay's paginated
JSON document format. Pages include their associated Pod text. The feed is
text-only: it does not export images, thumbnails, files, themes, or other
visual assets.

Relay can fetch:

```text
GET /refinery_relay/api/relay/documents
```

In **Relay Settings**, generate a bearer token and copy it into Relay's HTTP
feed source configuration. Copy the displayed feed endpoint into that source's
endpoint field. Relay polls the endpoint for content changes, so no sync URL,
source ID, Redis URL, tenant key, or timeout setting is needed.

## License

The gem is available as open source under the terms of the MIT License.
