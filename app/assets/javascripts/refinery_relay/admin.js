(function ($) {
  "use strict";

  var POD_TYPE = "llm_chat";
  var SETTINGS_ENDPOINT = "/refinery_relay/admin/settings";
  var THEME_FIELDS = [
    { key: "accent_color", label: "Accent colour", defaultValue: "#fbbf24" },
    { key: "background_color", label: "Background colour", defaultValue: "#101010" },
    { key: "surface_color", label: "Surface colour", defaultValue: "#181818" },
    { key: "text_color", label: "Text colour", defaultValue: "#f5f5f5" }
  ];

  function addPodField(inputSelector, label) {
    var input = $(inputSelector);
    if (!input.length) return;

    input.closest(".field").addClass(POD_TYPE);
    $("label[for='" + input.attr("id") + "']").first().text(label);
  }

  function preparePodForm() {
    if (!$("#pod_pod_type").length) return;

    addPodField("#pod_title", "Chat heading");
    addPodField("#pod_subtitle", "Welcome message");
    addPodField("#pod_body", "Introductory content");

    var podItems = $(".pod-items");
    podItems.addClass(POD_TYPE);
    podItems.find("tr.field").filter(function () {
      return $(this).find("th").first().text().trim() === "Title";
    }).addClass(POD_TYPE);
    podItems.find("small.field").addClass(POD_TYPE)
      .html("<strong>Hint:</strong> Each item title becomes a suggested question in the chat.");
    podItems.find("h3").first().text("Suggested Questions");
    podItems.find("a").filter(function () {
      return $(this).text().trim() === "Add item";
    }).text("Add suggested question");
  }

  function preparePodItemForm() {
    if (!$("#pod_item_pod_id").length) return;

    var heading = $("h2").first().text().toLowerCase();
    if (heading.indexOf("llm chat pod item") === -1) return;

    addPodField("#pod_item_title", "Suggested question");
  }

  function prepareThemeFields() {
    var podType = $("#pod_pod_type");
    var podItems = $(".pod-items").last();
    if (!podType.length || $(".refinery-relay-theme-fields").length) return;

    var container = $("<fieldset>", { "class": "refinery-relay-theme-fields field llm_chat" });
    container.append($("<legend>", { text: "Styling" }));
    container.append($("<small>", {
      "class": "refinery-relay-theme-hint",
      text: "These colours apply to all LLM Chat Pods on this website."
    }));

    var inputs = {};
    THEME_FIELDS.forEach(function(field) {
      var wrapper = $("<div>", { "class": "field llm_chat" });
      var inputId = "pod_refinery_relay_" + field.key;
      var label = $("<label>", { "for": inputId, text: field.label });
      var input = $("<input>", {
        type: "color",
        id: inputId,
        name: "pod[refinery_relay_" + field.key + "]",
        value: field.defaultValue
      });

      inputs[field.key] = input;
      wrapper.append(label, input);
      container.append(wrapper);
    });

    (podItems.length ? podItems : podType.closest(".field")).after(container);

    function syncVisibility() {
      container.toggle(podType.val() === POD_TYPE);
    }

    podType.on("change", syncVisibility);
    syncVisibility();

    if (typeof window.fetch !== "function") return;

    window.fetch(SETTINGS_ENDPOINT, {
      headers: { "Accept": "application/json" },
      credentials: "same-origin",
      cache: "no-store"
    }).then(function(response) {
      return response.ok ? response.json() : null;
    }).then(function(payload) {
      if (!payload || !payload.theme) return;

      THEME_FIELDS.forEach(function(field) {
        if (payload.theme[field.key]) inputs[field.key].val(payload.theme[field.key]);
      });
    }).catch(function() {
      // The initializer defaults remain usable when theme storage is unavailable.
    });
  }

  $(function () {
    preparePodForm();
    preparePodItemForm();
    prepareThemeFields();
  });
})(jQuery);
