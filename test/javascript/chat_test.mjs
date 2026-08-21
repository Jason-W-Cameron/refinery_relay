import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../../app/assets/javascripts/refinery_relay/chat.js", import.meta.url), "utf8")
const documentListeners = {}
const document = {
  readyState: "loading",
  documentElement: { lang: "en-ZA" },
  addEventListener(type, handler) { documentListeners[type] = handler },
  querySelectorAll() { return [] },
  createElement() { throw new Error("This test must provide a DOM element") },
  createTextNode(text) { return { textContent: text } }
}
const storage = new Map()
const window = {
  URL,
  Event,
  Promise,
  location: { href: "https://refinery.example/about", protocol: "https:" },
  localStorage: {
    getItem(key) { return storage.get(key) || null },
    setItem(key, value) { storage.set(key, value) },
    removeItem(key) { storage.delete(key) }
  },
  crypto: { randomUUID() { return "visitor-test" } },
  setTimeout(handler) { handler() },
  requestAnimationFrame(handler) { handler() }
}

vm.runInNewContext(source, { window, document, URL, Event, Promise, JSON, Math, Date, Error })

const ChatController = window.RefineryRelayChat.Controller

function citationController(overrides = {}) {
  return {
    allowInsecureAssets: false,
    domainFor: ChatController.prototype.domainFor,
    safeImageUrl: ChatController.prototype.safeImageUrl,
    safeSourceUrl: ChatController.prototype.safeSourceUrl,
    ...overrides
  }
}

test("exports a namespaced standalone controller and Swup lifecycle hooks", () => {
  assert.equal(ChatController.channelName, "RefineryRelay::RelayChatChannel")
  assert.equal(typeof window.RefineryRelayChat.initialize, "function")
  assert.equal(typeof documentListeners["swup:willReplaceContent"], "function")
  assert.equal(typeof documentListeners["swup:contentReplaced"], "function")
})

test("builds citation view models with safe image and PDF metadata", () => {
  const image = ChatController.prototype.citationViewModel.call(citationController(), {
    title: "Race information",
    url: "https://refinery.example/race-day",
    content_type: "page",
    page_number: 4,
    asset: {
      kind: "image",
      thumbnail_url: "https://cdn.example/race-thumb.jpg",
      alt_text: "Runners",
      caption: "Race day"
    }
  })
  const pdf = ChatController.prototype.citationViewModel.call(citationController(), {
    title: "Safety guide",
    url: "https://refinery.example/safety.pdf",
    content_type: "pdf",
    asset: { kind: "pdf", page_count: 24 }
  })

  assert.equal(image.href, "https://refinery.example/race-day")
  assert.equal(image.thumbnailUrl, "https://cdn.example/race-thumb.jpg")
  assert.equal(image.thumbnailAlt, "Runners")
  assert.equal(image.secondaryLabel, "Race day")
  assert.equal(image.detail, "refinery.example · page · Page 4")
  assert.equal(pdf.isPdf, true)
  assert.equal(pdf.thumbnailUrl, null)
  assert.equal(pdf.detail, "refinery.example · pdf · 24 pages")
})

test("rejects unsafe source protocols and only permits HTTP when configured", () => {
  const production = citationController()
  const development = citationController({ allowInsecureAssets: true })

  assert.equal(ChatController.prototype.safeSourceUrl.call(production, "javascript:alert(1)"), null)
  assert.equal(ChatController.prototype.safeSourceUrl.call(production, "http://cdn.example/image.jpg"), null)
  assert.equal(
    ChatController.prototype.safeSourceUrl.call(development, "http://cdn.example/image.jpg"),
    "http://cdn.example/image.jpg"
  )
})

test("removes redundant uploaded-source Markdown links from answers", () => {
  const url = "https://relay.example/uploads/elevation.jpeg"
  const answer = [
    "The route reaches 875 metres.",
    "",
    `[Uploaded source](${url})`,
    `[**Elevation**](${url})**`
  ].join("\n")

  assert.equal(
    ChatController.prototype.answerWithoutUploadedSourceLinks.call({}, answer, [{ url }]),
    "The route reaches 875 metres."
  )
})

test("textarea resizing caps height and Enter submits while Shift+Enter does not", () => {
  let submissions = 0
  let prevented = 0
  const input = {
    tagName: "TEXTAREA",
    scrollHeight: 220,
    style: {},
    form: { requestSubmit() { submissions += 1 } }
  }

  ChatController.prototype.resizeInput.call({}, input)
  ChatController.prototype.submitOnEnter.call({}, {
    key: "Enter", target: input, preventDefault() { prevented += 1 }
  })
  ChatController.prototype.submitOnEnter.call({}, {
    key: "Enter", shiftKey: true, target: input, preventDefault() { prevented += 1 }
  })

  assert.equal(input.style.height, "160px")
  assert.equal(input.style.overflowY, "auto")
  assert.equal(submissions, 1)
  assert.equal(prevented, 1)
})

test("submits the Relay browser payload and persists the returned conversation", async () => {
  let request
  const messages = []
  window.fetch = async (url, options) => {
    request = { url, options }
    return {
      ok: true,
      json: async () => ({
        conversation_id: "conversation-123",
        answer: "Relay answer [1]",
        citations: [{ title: "About", url: "https://refinery.example/about" }]
      })
    }
  }

  const input = { value: " What services do you offer? ", style: {}, tagName: "TEXTAREA", scrollHeight: 20 }
  const controller = {
    chatUrl: "/refinery_relay/api/relay/chat",
    conversationId: null,
    visitorId: "visitor-123",
    requestSequence: 0,
    isLoading: false,
    hideError() {},
    showConversation() {},
    appendMessage(role, message) { messages.push([role, message]) },
    resizeInput: ChatController.prototype.resizeInput,
    setLoading(loading) { this.isLoading = loading },
    persistConversationId() { this.persisted = this.conversationId },
    renderSources(citations) { this.citations = citations },
    showError(message) { this.error = message },
    conversationTarget: { querySelector() { return { focus() {} } } }
  }
  const event = {
    currentTarget: { querySelector() { return input } },
    preventDefault() {}
  }

  assert.equal(await ChatController.prototype.submit.call(controller, event), true)
  const body = JSON.parse(request.options.body)
  assert.equal(request.url, "/refinery_relay/api/relay/chat")
  assert.equal(body.message, "What services do you offer?")
  assert.equal(body.visitor_id, "visitor-123")
  assert.equal(body.context.interface, "web")
  assert.equal(body.context.locale, "en-ZA")
  assert.equal(controller.persisted, "conversation-123")
  assert.deepEqual(messages, [
    ["user", "What services do you offer?"],
    ["assistant", "Relay answer [1]"]
  ])
})

test("availability failure shows the unavailable state only for a new conversation", async () => {
  window.fetch = async () => ({ ok: true, json: async () => ({ available: false }) })
  let unavailable = 0
  const fresh = {
    availabilityUrl: "/refinery_relay/api/relay/chat/availability",
    conversationId: null,
    unavailableTarget: { hidden: true },
    showUnavailable() { unavailable += 1 }
  }
  const existing = { ...fresh, conversationId: "conversation-123" }

  assert.equal(await ChatController.prototype.checkAvailability.call(fresh), false)
  assert.equal(await ChatController.prototype.checkAvailability.call(existing), false)
  assert.equal(unavailable, 1)
})

test("availability recovery restores the initial chat view", async () => {
  window.fetch = async () => ({ ok: true, json: async () => ({ available: true }) })
  let showedInitial = 0
  const controller = {
    availabilityUrl: "/refinery_relay/api/relay/chat/availability",
    conversationId: null,
    unavailableTarget: { hidden: false },
    initialTarget: { hidden: true },
    conversationTarget: { hidden: true },
    showInitial() { showedInitial += 1 }
  }

  assert.equal(await ChatController.prototype.checkAvailability.call(controller), true)
  assert.equal(controller.unavailableTarget.hidden, true)
  assert.equal(showedInitial, 1)
})

test("uses an existing Action Cable consumer for availability events", () => {
  let subscribedChannel
  let unavailable = 0
  window.App = {
    cable: {
      subscriptions: {
        create(channel, callbacks) {
          subscribedChannel = channel
          callbacks.received({ type: "chat_unavailable" })
          return { unsubscribe() {} }
        }
      }
    }
  }
  const controller = {
    channelName: "RefineryRelay::RelayChatChannel",
    checkAvailability() {},
    handleChatUnavailable() { unavailable += 1 }
  }

  ChatController.prototype.subscribeToAvailability.call(controller)
  assert.equal(subscribedChannel, "RefineryRelay::RelayChatChannel")
  assert.equal(unavailable, 1)
})
