//= require action_cable

(function(window, document) {
  "use strict";

  var ROOT_SELECTOR = "[data-refinery-relay-chat]";
  var CONTROLLER_KEY = "__refineryRelayChatController";
  var VISITOR_STORAGE_KEY = "niimble-relay-visitor-id";
  var CONVERSATION_STORAGE_KEY = "niimble-relay-conversation-id";
  var VIEW_TRANSITION_MS = 180;

  function toArray(collection) {
    return Array.prototype.slice.call(collection || []);
  }

  function clearElement(element) {
    while (element && element.firstChild) element.removeChild(element.firstChild);
  }

  function appendChildren(element, children) {
    children.forEach(function(child) { element.appendChild(child); });
  }

  function frame(callback) {
    var requestFrame = window.requestAnimationFrame || function(next) { window.setTimeout(next, 0); };
    requestFrame(callback);
  }

  function ChatController(element) {
    this.element = element;
    this.chatUrl = element.getAttribute("data-chat-url");
    this.availabilityUrl = element.getAttribute("data-availability-url");
    this.channelName = element.getAttribute("data-channel") || "RefineryRelay::RelayChatChannel";
    this.sourceOrigin = element.getAttribute("data-source-origin") || window.location.origin;
    this.allowInsecureAssets = element.getAttribute("data-allow-insecure-assets") === "true";

    this.initialTarget = element.querySelector("[data-refinery-relay-view='initial']");
    this.conversationTarget = element.querySelector("[data-refinery-relay-view='conversation']");
    this.messagesTarget = element.querySelector("[data-refinery-relay-messages]");
    this.typingTarget = element.querySelector("[data-refinery-relay-typing]");
    this.errorTarget = element.querySelector("[data-refinery-relay-error]");
    this.sourcesTarget = element.querySelector("[data-refinery-relay-sources]");
    this.sourceCountTarget = element.querySelector("[data-refinery-relay-source-count]");
    this.emptySourcesTarget = element.querySelector("[data-refinery-relay-empty-sources]");
    this.unavailableTarget = element.querySelector("[data-refinery-relay-unavailable]");
    this.forms = toArray(element.querySelectorAll("[data-refinery-relay-form]"));
    this.inputs = toArray(element.querySelectorAll("[data-refinery-relay-input]"));
    this.sendButtons = toArray(element.querySelectorAll("[data-refinery-relay-send]"));
    this.suggestions = toArray(element.querySelectorAll("[data-refinery-relay-suggestion]"));
    this.resetButton = element.querySelector("[data-refinery-relay-reset]");
    this.listeners = [];
  }

  ChatController.channelName = "RefineryRelay::RelayChatChannel";

  ChatController.prototype.connect = function() {
    var controller = this;
    if (this.connected) return;

    this.connected = true;
    this.conversationId = this.restoreConversationId();
    this.visitorId = this.restoreVisitorId();
    this.requestSequence = 0;
    this.transitionSequence = 0;
    this.isLoading = false;

    this.forms.forEach(function(form) {
      controller.listen(form, "submit", function(event) { controller.submit(event); });
    });
    this.inputs.forEach(function(input) {
      controller.listen(input, "input", function(event) { controller.resizeInput(event); });
      controller.listen(input, "keydown", function(event) { controller.submitOnEnter(event); });
    });
    this.suggestions.forEach(function(button) {
      controller.listen(button, "click", function() { controller.submitSuggestion(button); });
    });
    if (this.resetButton) {
      this.listen(this.resetButton, "click", function() { controller.reset(); });
    }

    this.subscribeToAvailability();
    this.checkAvailability();
  };

  ChatController.prototype.disconnect = function() {
    this.requestSequence += 1;
    this.listeners.forEach(function(listener) {
      listener.target.removeEventListener(listener.type, listener.handler);
    });
    this.listeners = [];
    if (this.subscription && typeof this.subscription.unsubscribe === "function") {
      this.subscription.unsubscribe();
    }
    this.subscription = null;
    this.element.removeAttribute("data-refinery-relay-cable-connected");
    this.connected = false;
  };

  ChatController.prototype.listen = function(target, type, handler) {
    target.addEventListener(type, handler);
    this.listeners.push({ target: target, type: type, handler: handler });
  };

  ChatController.prototype.submitSuggestion = function(button) {
    var input = this.initialTarget && this.initialTarget.querySelector("[data-refinery-relay-input]");
    var form = input && input.form;
    if (!input || !form || this.isLoading) return;

    input.value = (button.textContent || "").trim();
    this.resizeInput(input);
    if (typeof form.requestSubmit === "function") form.requestSubmit();
    else form.dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
  };

  ChatController.prototype.submit = function(event) {
    var controller = this;
    event.preventDefault();

    var form = event.currentTarget;
    var input = form.querySelector("[data-refinery-relay-input]");
    var message = input ? input.value.trim() : "";
    if (!message || this.isLoading) return Promise.resolve(false);

    this.hideError();
    this.showConversation();
    this.appendMessage("user", message);
    input.value = "";
    this.resizeInput(input);
    this.setLoading(true);
    var requestId = ++this.requestSequence;

    return window.fetch(this.chatUrl, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json"
      },
      credentials: "same-origin",
      body: JSON.stringify({
        conversation_id: this.conversationId,
        message: message,
        visitor_id: this.visitorId,
        context: {
          current_url: window.location.href,
          locale: document.documentElement.lang || "en-ZA",
          interface: "web",
          interface_type: "web"
        }
      })
    }).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(result) {
        if (result.chat_unavailable) {
          controller.handleChatUnavailable();
          return false;
        }
        if (!response.ok) {
          throw new Error(result.message || "We could not answer that just now.");
        }
        if (requestId !== controller.requestSequence) return false;

        controller.conversationId = result.conversation_id || controller.conversationId;
        controller.persistConversationId();
        controller.appendMessage(
          "assistant",
          result.answer || "I don't have enough information in the available sources to answer that.",
          result.citations || [],
          result.uploaded_sources || []
        );
        controller.renderSources(result.citations || []);
        return true;
      });
    }).catch(function(error) {
      if (requestId === controller.requestSequence) {
        controller.showError(error.message || "We could not answer that just now. Please try again.");
      }
      return false;
    }).then(function(result) {
      if (requestId === controller.requestSequence) {
        controller.setLoading(false);
        var conversationInput = controller.conversationTarget.querySelector("[data-refinery-relay-input]");
        if (conversationInput) conversationInput.focus();
      }
      return result;
    });
  };

  ChatController.prototype.reset = function() {
    var controller = this;
    this.requestSequence += 1;
    this.clearConversationId();
    clearElement(this.messagesTarget);
    clearElement(this.sourcesTarget);
    this.emptySourcesTarget.hidden = false;
    this.sourceCountTarget.textContent = "References appear here";
    this.hideError();
    this.setLoading(false);

    return this.checkAvailability().then(function(available) {
      if (available) controller.showInitial();
      return available;
    });
  };

  ChatController.prototype.showConversation = function() {
    var controller = this;
    var transitionId = ++this.transitionSequence;

    this.unavailableTarget.hidden = true;
    this.initialTarget.classList.add("is-exiting");
    this.conversationTarget.hidden = false;
    this.conversationTarget.classList.add("is-entering");

    frame(function() {
      if (transitionId !== controller.transitionSequence) return;
      controller.conversationTarget.classList.remove("is-entering");
    });

    window.setTimeout(function() {
      if (transitionId !== controller.transitionSequence) return;
      controller.initialTarget.hidden = true;
      controller.initialTarget.classList.remove("is-exiting");
    }, VIEW_TRANSITION_MS);
  };

  ChatController.prototype.showInitial = function() {
    var controller = this;
    var transitionId = ++this.transitionSequence;

    this.unavailableTarget.hidden = true;
    this.conversationTarget.classList.add("is-exiting");
    this.initialTarget.hidden = false;
    this.initialTarget.classList.add("is-entering");

    frame(function() {
      if (transitionId !== controller.transitionSequence) return;
      controller.initialTarget.classList.remove("is-entering");
    });

    window.setTimeout(function() {
      if (transitionId !== controller.transitionSequence) return;
      controller.conversationTarget.hidden = true;
      controller.conversationTarget.classList.remove("is-exiting");
    }, VIEW_TRANSITION_MS);

    var input = this.initialTarget.querySelector("[data-refinery-relay-input]");
    if (input) input.focus();
  };

  ChatController.prototype.showUnavailable = function() {
    this.requestSequence += 1;
    this.transitionSequence += 1;
    this.setLoading(false);
    this.initialTarget.classList.remove("is-entering", "is-exiting");
    this.conversationTarget.classList.remove("is-entering", "is-exiting");
    this.initialTarget.hidden = true;
    this.conversationTarget.hidden = true;
    this.unavailableTarget.hidden = false;
  };

  ChatController.prototype.subscribeToAvailability = function() {
    var controller = this;
    var consumer = null;

    if (window.App && window.App.cable) consumer = window.App.cable;
    else if (window.ActionCable && typeof window.ActionCable.createConsumer === "function") {
      consumer = window.ActionCable.createConsumer(this.cableUrl());
    }
    if (!consumer || !consumer.subscriptions) return;

    this.subscription = consumer.subscriptions.create(this.channelName, {
      connected: function() {
        controller.element.setAttribute("data-refinery-relay-cable-connected", "true");
        controller.checkAvailability();
      },
      received: function(event) {
        if (event && event.type === "chat_unavailable") controller.handleChatUnavailable();
      }
    });
  };

  ChatController.prototype.checkAvailability = function() {
    var controller = this;
    if (!this.availabilityUrl || typeof window.fetch !== "function") {
      if (!this.conversationId) this.showUnavailable();
      return Promise.resolve(false);
    }

    return window.fetch(this.availabilityUrl, {
      headers: { "Accept": "application/json" },
      credentials: "same-origin",
      cache: "no-store"
    }).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(payload) {
        var available = response.ok && payload.available === true;
        if (available) {
          controller.unavailableTarget.hidden = true;
          if (controller.initialTarget.hidden && controller.conversationTarget.hidden) controller.showInitial();
        } else if (!controller.conversationId) {
          controller.showUnavailable();
        }
        return available;
      });
    }).catch(function() {
      if (!controller.conversationId) controller.showUnavailable();
      return false;
    });
  };

  ChatController.prototype.handleChatUnavailable = function() {
    if (!this.conversationId) this.showUnavailable();
  };

  ChatController.prototype.cableUrl = function() {
    var url = new window.URL("/cable", window.location.href);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    return url.toString();
  };

  ChatController.prototype.resizeInput = function(eventOrInput) {
    var input = eventOrInput && eventOrInput.target ? eventOrInput.target : eventOrInput;
    if (!input || input.tagName !== "TEXTAREA") return;

    input.style.height = "auto";
    var maxHeight = 160;
    input.style.height = Math.min(input.scrollHeight, maxHeight) + "px";
    input.style.overflowY = input.scrollHeight > maxHeight ? "auto" : "hidden";
  };

  ChatController.prototype.submitOnEnter = function(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return;

    event.preventDefault();
    if (event.target.form && typeof event.target.form.requestSubmit === "function") {
      event.target.form.requestSubmit();
    }
  };

  ChatController.prototype.appendMessage = function(role, text, citations, uploadedSources) {
    var item = document.createElement("article");
    item.className = "refinery-relay-chat__message refinery-relay-chat__message--" + role;

    var bubble = document.createElement("div");
    bubble.className = "refinery-relay-chat__message-content";
    if (role === "assistant") {
      this.appendUploadedSourceImages(item, uploadedSources || []);
      this.appendAnswerContent(bubble, this.answerWithoutUploadedSourceLinks(text, uploadedSources || []), citations || []);
    } else {
      bubble.textContent = text;
    }
    item.appendChild(bubble);
    this.messagesTarget.appendChild(item);
    this.scrollMessagesToBottom();
  };

  ChatController.prototype.appendAnswerContent = function(element, answer, citations) {
    var controller = this;
    String(answer).split(/(\[\d+\])/g).forEach(function(part) {
      var match = part.match(/^\[(\d+)\]$/);
      var citation = match && citations[Number(match[1]) - 1];
      var href = citation && controller.safeSourceUrl(citation.url);
      if (!href) {
        if (match) return;
        element.appendChild(document.createTextNode(part));
        return;
      }

      var link = document.createElement("a");
      link.href = href;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.className = "refinery-relay-chat__citation";
      link.textContent = match[1];
      link.setAttribute("aria-label", "Open source " + match[1] + ": " + (citation.title || "reference"));
      element.appendChild(link);
    });
  };

  ChatController.prototype.appendUploadedSourceImages = function(message, uploadedSources) {
    var controller = this;
    var images = document.createElement("div");
    images.className = "refinery-relay-chat__uploaded-sources";
    images.setAttribute("aria-label", "Uploaded source images");

    (Array.isArray(uploadedSources) ? uploadedSources : []).forEach(function(source) {
      var viewModel = controller.uploadedSourceViewModel(source);
      if (!viewModel.href || !viewModel.isImage || !viewModel.thumbnailUrl) return;

      var link = document.createElement("a");
      link.href = viewModel.href;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.className = "refinery-relay-chat__uploaded-source";

      var image = document.createElement("img");
      image.src = viewModel.thumbnailUrl;
      image.alt = viewModel.thumbnailAlt;
      if (!viewModel.thumbnailAlt) image.setAttribute("aria-hidden", "true");
      image.loading = "lazy";
      image.className = "refinery-relay-chat__uploaded-image";
      image.addEventListener("error", function() {
        if (link.parentNode) link.parentNode.removeChild(link);
      }, { once: true });
      link.appendChild(image);
      images.appendChild(link);
    });

    if (images.childNodes.length) message.appendChild(images);
  };

  ChatController.prototype.answerWithoutUploadedSourceLinks = function(answer, uploadedSources) {
    var urls = (Array.isArray(uploadedSources) ? uploadedSources : []).map(function(source) {
      return source && source.url;
    }).filter(function(url) {
      return typeof url === "string" && url;
    });

    return urls.reduce(function(cleanedAnswer, url) {
      var escapedUrl = url.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      var markdownLink = new RegExp("(?:\\*{1,2})?\\[[^\\]]*\\]\\(" + escapedUrl + "\\)(?:\\*{1,2})?", "g");
      return cleanedAnswer.replace(markdownLink, "");
    }, String(answer)).replace(/\n{3,}/g, "\n\n").trim();
  };

  ChatController.prototype.renderSources = function(citations) {
    var controller = this;
    var sourceCitations = Array.isArray(citations) ? citations : [];
    var renderedSources = sourceCitations.filter(function(citation) {
      return controller.citationViewModel(citation).href;
    });
    clearElement(this.sourcesTarget);
    this.emptySourcesTarget.hidden = renderedSources.length > 0;
    this.sourceCountTarget.textContent = renderedSources.length ?
      renderedSources.length + " " + (renderedSources.length === 1 ? "reference" : "references") :
      "No references returned";

    sourceCitations.forEach(function(citation) {
      var source = controller.citationViewModel(citation);
      if (!source.href) return;

      var link = document.createElement("a");
      link.href = source.href;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.className = "refinery-relay-chat__source";

      var copy = document.createElement("span");
      copy.className = "refinery-relay-chat__source-copy";
      var detail = document.createElement("span");
      detail.className = "refinery-relay-chat__source-detail";
      detail.textContent = source.detail;
      var title = document.createElement("strong");
      title.className = "refinery-relay-chat__source-title";
      title.textContent = source.title;
      appendChildren(copy, [detail, title]);

      if (source.secondaryLabel) {
        var secondaryLabel = document.createElement("span");
        secondaryLabel.className = "refinery-relay-chat__source-caption";
        secondaryLabel.textContent = source.secondaryLabel;
        copy.appendChild(secondaryLabel);
      }
      link.appendChild(copy);

      if (source.thumbnailUrl) {
        var thumbnail = document.createElement("img");
        thumbnail.src = source.thumbnailUrl;
        thumbnail.alt = source.thumbnailAlt;
        if (!source.thumbnailAlt) thumbnail.setAttribute("aria-hidden", "true");
        thumbnail.loading = "lazy";
        thumbnail.className = "refinery-relay-chat__source-thumbnail";
        thumbnail.addEventListener("error", function() {
          if (thumbnail.parentNode) thumbnail.parentNode.removeChild(thumbnail);
        }, { once: true });
        link.appendChild(thumbnail);
      } else if (source.isPdf) {
        var pdfBadge = document.createElement("span");
        pdfBadge.className = "refinery-relay-chat__source-pdf";
        pdfBadge.textContent = "PDF";
        pdfBadge.setAttribute("aria-label", "PDF document");
        link.appendChild(pdfBadge);
      } else {
        var sourceBadge = document.createElement("span");
        sourceBadge.className = "refinery-relay-chat__source-fallback";
        sourceBadge.textContent = "↗";
        sourceBadge.setAttribute("aria-hidden", "true");
        link.appendChild(sourceBadge);
      }
      controller.sourcesTarget.appendChild(link);
    });
  };

  ChatController.prototype.citationViewModel = function(citation) {
    citation = citation || {};
    var asset = citation.asset && typeof citation.asset === "object" ? citation.asset : null;
    var isImage = asset && asset.kind === "image";
    var metadata = citation.metadata || {};
    var legacyImageUrl = citation.image_url || citation.image || metadata.image_url || metadata.cover_image_url;
    var detail = [
      this.domainFor(citation.url),
      this.humanizeContentType(citation.content_type),
      citation.page_number ? "Page " + citation.page_number : null,
      asset && asset.kind === "pdf" && asset.page_count ? asset.page_count + " pages" : null
    ].filter(function(value) { return Boolean(value); }).join(" · ");

    return {
      href: this.safeSourceUrl(citation.url),
      title: String(citation.title || "").trim() || this.titleFromUrl(citation.url) || "Source",
      detail: detail || "Source",
      thumbnailUrl: isImage ?
        (this.safeImageUrl(asset.thumbnail_url) || this.safeImageUrl(asset.url)) :
        this.safeImageUrl(legacyImageUrl),
      thumbnailAlt: (asset && asset.alt_text) || citation.image_alt || "",
      isPdf: Boolean(asset && asset.kind === "pdf"),
      secondaryLabel: (asset && (asset.caption || asset.alt_text)) || null
    };
  };

  ChatController.prototype.uploadedSourceViewModel = function(source) {
    source = source || {};
    var asset = source.asset && typeof source.asset === "object" ? source.asset : {};
    var isImage = asset.kind === "image";

    return {
      href: this.safeAssetUrl(source.url),
      title: source.title || "Uploaded source",
      thumbnailUrl: isImage ? (this.safeImageUrl(asset.thumbnail_url) || this.safeImageUrl(asset.url)) : null,
      thumbnailAlt: asset.alt_text || asset.caption || source.title || "",
      isImage: isImage,
      isPdf: asset.kind === "pdf",
      pageCount: asset.page_count || null
    };
  };

  ChatController.prototype.safeImageUrl = function(value) {
    return this.safeAssetUrl(value);
  };

  ChatController.prototype.safeSourceUrl = function(value) {
    return this.safeAssetUrl(value, true);
  };

  ChatController.prototype.safeAssetUrl = function(value, allowInsecureHttp) {
    if (typeof value !== "string" || !value.trim()) return null;

    try {
      var url = new window.URL(value);
      var allowsHttp = allowInsecureHttp || this.allowInsecureAssets || window.location.protocol === "http:";
      return url.protocol === "https:" || (allowsHttp && url.protocol === "http:") ? url.toString() : null;
    } catch (error) {
      return null;
    }
  };

  ChatController.prototype.humanizeContentType = function(value) {
    var contentType = String(value || "").replace(/[_-]+/g, " ").trim();
    return contentType ? contentType.toLowerCase() : null;
  };

  ChatController.prototype.titleFromUrl = function(value) {
    if (typeof value !== "string" || !value.trim()) return null;

    try {
      var path = new window.URL(value).pathname;
      var segment = path.split("/").filter(Boolean).pop();
      if (!segment) return "Home";

      segment = decodeURIComponent(segment).replace(/\.[a-z0-9]{2,5}$/i, "");
      return segment.replace(/[-_]+/g, " ").replace(/\b\w/g, function(letter) {
        return letter.toUpperCase();
      });
    } catch (error) {
      return null;
    }
  };

  ChatController.prototype.setLoading = function(loading) {
    this.isLoading = loading;
    this.sendButtons.forEach(function(button) {
      button.disabled = loading;
      button.setAttribute("aria-busy", loading ? "true" : "false");
      button.setAttribute("aria-label", loading ? "Sending question" : "Send question");
      if (loading) button.classList.add("is-loading");
      else button.classList.remove("is-loading");
    });
    this.typingTarget.hidden = !loading;
    this.scrollMessagesToBottom();
  };

  ChatController.prototype.showError = function(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  };

  ChatController.prototype.hideError = function() {
    this.errorTarget.textContent = "";
    this.errorTarget.hidden = true;
  };

  ChatController.prototype.scrollMessagesToBottom = function() {
    var messages = this.messagesTarget;
    frame(function() {
      if (typeof messages.scrollTo === "function") {
        messages.scrollTo({ top: messages.scrollHeight, behavior: "smooth" });
      } else {
        messages.scrollTop = messages.scrollHeight;
      }
    });
  };

  ChatController.prototype.domainFor = function(url) {
    try {
      return new window.URL(url).hostname.replace(/^www\./, "");
    } catch (error) {
      return "Source";
    }
  };

  ChatController.prototype.restoreVisitorId = function() {
    try {
      var existing = window.localStorage.getItem(VISITOR_STORAGE_KEY);
      if (existing) return existing;
      var visitorId = window.crypto && typeof window.crypto.randomUUID === "function" ?
        window.crypto.randomUUID() :
        "visitor-" + Date.now() + "-" + Math.random().toString(16).slice(2);
      window.localStorage.setItem(VISITOR_STORAGE_KEY, visitorId);
      return visitorId;
    } catch (error) {
      return "visitor-" + Date.now() + "-" + Math.random().toString(16).slice(2);
    }
  };

  ChatController.prototype.restoreConversationId = function() {
    try {
      return window.localStorage.getItem(CONVERSATION_STORAGE_KEY) || null;
    } catch (error) {
      return null;
    }
  };

  ChatController.prototype.persistConversationId = function() {
    if (!this.conversationId) return;
    try {
      window.localStorage.setItem(CONVERSATION_STORAGE_KEY, this.conversationId);
    } catch (error) {
      // Storage can be unavailable in private browsing modes.
    }
  };

  ChatController.prototype.clearConversationId = function() {
    this.conversationId = null;
    try {
      window.localStorage.removeItem(CONVERSATION_STORAGE_KEY);
    } catch (error) {
      // Storage can be unavailable in private browsing modes.
    }
  };

  function initialize(scope) {
    var roots = [];
    if (scope && typeof scope.matches === "function" && scope.matches(ROOT_SELECTOR)) roots.push(scope);
    if (scope && typeof scope.querySelectorAll === "function") {
      roots = roots.concat(toArray(scope.querySelectorAll(ROOT_SELECTOR)));
    }

    roots.forEach(function(root) {
      if (root[CONTROLLER_KEY]) return;
      var controller = new ChatController(root);
      root[CONTROLLER_KEY] = controller;
      controller.connect();
    });
    return roots.length;
  }

  function disconnect(scope) {
    var roots = [];
    if (scope && typeof scope.matches === "function" && scope.matches(ROOT_SELECTOR)) roots.push(scope);
    if (scope && typeof scope.querySelectorAll === "function") {
      roots = roots.concat(toArray(scope.querySelectorAll(ROOT_SELECTOR)));
    }
    roots.forEach(function(root) {
      if (!root[CONTROLLER_KEY]) return;
      root[CONTROLLER_KEY].disconnect();
      root[CONTROLLER_KEY] = null;
    });
    return roots.length;
  }

  window.RefineryRelayChat = {
    Controller: ChatController,
    initialize: initialize,
    disconnect: disconnect
  };

  document.addEventListener("swup:willReplaceContent", function() { disconnect(document); });
  document.addEventListener("swup:contentReplaced", function() { initialize(document); });
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function() { initialize(document); });
  } else {
    initialize(document);
  }
})(window, document);
