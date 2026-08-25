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
  var POD_SETTINGS_FIELDS = [
    {
      key: "prompt_placeholder",
      label: "Prompt placeholder",
      type: "text",
      defaultValue: "Ask a question about this organisation's published information…"
    },
    {
      key: "information_text",
      label: "Information card",
      type: "textarea",
      defaultValue: "This intelligent assistant is powered by this organisation’s published information. It helps visitors find accurate answers and key information instantly."
    },
    {
      key: "information_image_id",
      label: "Information card image",
      type: "image"
    },
    {
      key: "footer_logo_url",
      label: "Footer logo image URL",
      type: "text",
      defaultValue: "refinery_relay/niimble-logo-light-tp.png"
    },
    {
      key: "footer_logo_link",
      label: "Footer logo link",
      type: "text",
      defaultValue: "https://www.niimble.io"
    },
    {
      key: "terms_link",
      label: "Terms & Conditions link",
      type: "text",
      defaultValue: "https://www.niimble.io/terms"
    }
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

    var podItems = $(".pod-items");
    podItems.addClass(POD_TYPE);
    var questionRows = podItems.find("tr.field").filter(function () {
      return $(this).find("th").first().text().trim() === "Title";
    });
    questionRows.addClass(POD_TYPE).addClass("refinery-relay-suggestion-title-row").each(function () {
      $(this).find("th").first().text("Question");
    });

    var suggestionTable = podItems.find("table").first();
    suggestionTable.addClass("refinery-relay-suggestion-table");
    suggestionTable.find("tr").filter(function () {
      return $(this).find("h3").length > 0;
    }).addClass("refinery-relay-suggestion-item-header");

    var podHints = podItems.find("small.field");
    podHints.first().addClass(POD_TYPE).addClass("refinery-relay-pod-items-hint")
      .html("<strong>Suggested questions:</strong> Add the questions visitors can choose before they start chatting.");
    podHints.slice(1).hide().removeClass(POD_TYPE);
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

  function currentPodId() {
    var hiddenPodId = $("#pod_id").val() || $("input[name='pod[id]']").first().val();
    if (hiddenPodId) return hiddenPodId;

    var formAction = $("form[action]").filter(function() {
      return ($(this).attr("action") || "").indexOf("/pods/") !== -1;
    }).first().attr("action") || "";
    var locationPath = window.location.pathname || "";
    var match = (locationPath + " " + formAction).match(/\/pods\/(\d+)(?:\/edit)?(?:[/?#]|$)/);
    return match ? match[1] : "";
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
        if (payload.theme[field.key]) {
          inputs[field.key].val(payload.theme[field.key]).trigger("change");
        }
      });
    }).catch(function() {
      // The initializer defaults remain usable when theme storage is unavailable.
    });
  }

  function preparePodSettingsFields() {
    var podType = $("#pod_pod_type");
    var podItems = $(".pod-items").last();
    if (!podType.length || $(".refinery-relay-pod-settings-fields").length) return;

    var container = $("<fieldset>", { "class": "refinery-relay-pod-settings-fields field llm_chat" });
    container.append($("<legend>", { text: "Chat content" }));
    container.append($("<small>", {
      "class": "refinery-relay-pod-settings-hint",
      text: "These values apply only to this LLM Chat Pod. Leave them unchanged to use the configured defaults."
    }));

    var inputs = {};
    var imagePickerCounter = 0;

    function imagePickerField(field) {
      imagePickerCounter += 1;
      var pickerId = "refinery-relay-information-image-picker-" + imagePickerCounter;
      var callbackName = pickerId.replace(/[^a-z0-9_]/gi, "_") + "_changed";
      var imagePickerPath = "/refinery/images/admin/images/insert";
      var wrapper = $("<div>", { "class": "field llm_chat refinery-relay-image-field" });
      var inputId = "pod_refinery_relay_" + field.key;
      var label = $("<label>", { "for": inputId, text: field.label });
      var picker = $("<div>", {
        id: pickerId,
        "class": "refinery-relay-image-picker"
      });
      var input = $("<input>", {
        type: "hidden",
        id: inputId,
        name: "pod[refinery_relay_" + field.key + "]",
        "class": "refinery-relay-image-picker__input"
      });
      var link = $("<a>", {
        "class": "refinery-relay-image-picker__link dialog",
        href: imagePickerPath + "?dialog=true&callback=" + encodeURIComponent(callbackName) + "&width=866&height=510",
        title: "Choose Information Card image"
      });
      var image = $("<img>", {
        "class": "refinery-relay-image-picker__preview",
        alt: "",
        style: "display:none"
      });
      var empty = $("<span>", {
        "class": "refinery-relay-image-picker__empty",
        text: "Choose an image"
      });
      var remove = $("<button>", {
        type: "button",
        "class": "refinery-relay-image-picker__remove",
        text: "Remove image",
        style: "display:none"
      });

      link.append(image, empty);
      picker.append(input, link, remove);
      wrapper.append(label, picker);

      function applyImage(args) {
        var selectedImage = $(args);
        var imageId = selectedImage.attr("id") || args.id || "";
        var imageUrl = selectedImage.attr("data-medium") || selectedImage.attr("data-original") || selectedImage.attr("src") || args.src || "";
        var imageAlt = selectedImage.attr("alt") || selectedImage.attr("title") || args.alt || "Information card";

        imageId = imageId.replace(/^image_/, "");
        if (!imageId || !imageUrl) return;

        input.val(imageId).trigger("change");
        image.attr({ src: imageUrl, alt: imageAlt }).show();
        empty.hide();
        remove.show();
      }

      window[callbackName] = applyImage;
      remove.on("click", function() {
        input.val("").trigger("change");
        image.attr({ src: "", alt: "" }).hide();
        empty.show();
        remove.hide();
      });

      return { wrapper: wrapper, input: input, link: link, callbackName: callbackName, applyImage: applyImage };
    }

    POD_SETTINGS_FIELDS.forEach(function(field) {
      if (field.type === "image") {
        var imageField = imagePickerField(field);
        inputs[field.key] = imageField;
        container.append(imageField.wrapper);
        return;
      }

      var wrapper = $("<div>", { "class": "field llm_chat" });
      var inputId = "pod_refinery_relay_" + field.key;
      var label = $("<label>", { "for": inputId, text: field.label });
      var inputType = field.type === "textarea" ? "textarea" : "input";
      var input = $("<" + inputType + ">", {
        id: inputId,
        name: "pod[refinery_relay_" + field.key + "]",
        type: field.type === "text" ? "text" : undefined
      });

      if (field.type === "textarea") {
        input.attr({ rows: 5, maxlength: 2000 }).val(field.defaultValue);
      } else {
        input.attr({ maxlength: 500 }).val(field.defaultValue);
      }

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

    var podId = currentPodId();
    var endpoint = SETTINGS_ENDPOINT + (podId ? "?pod_id=" + encodeURIComponent(podId) : "");
    window.fetch(endpoint, {
      headers: { "Accept": "application/json" },
      credentials: "same-origin",
      cache: "no-store"
    }).then(function(response) {
      return response.ok ? response.json() : null;
    }).then(function(payload) {
      if (!payload || !payload.pod) return;

      if (payload.pod.image_picker_path && inputs.information_image_id) {
        inputs.information_image_id.link.attr("href", payload.pod.image_picker_path + "?dialog=true&callback=" + encodeURIComponent(inputs.information_image_id.callbackName) + "&width=866&height=510");
      }

      POD_SETTINGS_FIELDS.forEach(function(field) {
        var value = payload.pod[field.key];
        if (field.type === "image") {
          if (payload.pod.information_image_id && payload.pod.information_image_url) {
            inputs[field.key].input.val(payload.pod.information_image_id).trigger("change");
            inputs[field.key].applyImage({
              id: "image_" + payload.pod.information_image_id,
              src: payload.pod.information_image_url,
              alt: payload.pod.information_image_alt || "Information card"
            });
          }
        } else if (value) {
          inputs[field.key].val(value).trigger("change");
        }
      });
    }).catch(function() {
      // The field defaults remain usable when per-pod storage is unavailable.
    });
  }

  function fieldValue(selector, fallback) {
    var field = $(selector);
    var value = field.length ? field.val() : "";
    return $.trim(value || "") || fallback;
  }

  function colorChannels(hex) {
    var value = (hex || "").replace(/^#/, "");
    if (value.length === 3) value = value.split("").map(function(channel) { return channel + channel; }).join("");
    return [0, 2, 4].map(function(index) { return parseInt(value.substr(index, 2), 16); });
  }

  function rgbaColor(hex, alpha) {
    return "rgba(" + colorChannels(hex).join(", ") + ", " + alpha + ")";
  }

  function contrastText(hex) {
    var channels = colorChannels(hex).map(function(channel) { return channel / 255; }).map(function(channel) {
      return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    });
    var luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
    return luminance > 0.179 ? "#171717" : "#ffffff";
  }

  function suggestedQuestions(podItems) {
    var questions = [];

    podItems.find("input, textarea").filter(function() {
      return /\[title\]/.test($(this).attr("name") || "");
    }).each(function() {
      var value = $.trim($(this).val() || "");
      if (value && questions.indexOf(value) === -1) questions.push(value);
    });

    if (questions.length) return questions;

    podItems.find("tr.field").filter(function() {
      return $.trim($(this).find("th").first().text()).toLowerCase() === "title";
    }).each(function() {
      var value = $.trim($(this).find("td").first().text());
      if (value && questions.indexOf(value) === -1) questions.push(value);
    });

    return questions;
  }

  function preparePreview() {
    var podType = $("#pod_pod_type");
    var podItems = $(".pod-items").last();
    var podExample = $(".previews").first();
    var podExamplePanel = podExample.children("div").first();
    var preview;

    if (!podType.length || $(".refinery-relay-admin-preview").length) return;

    preview = $("<section>", { "class": "refinery-relay-chat refinery-relay-admin-preview" });
    preview.append($("<div>", { "class": "refinery-relay-chat__initial" }).append(
      $("<header>", { "class": "refinery-relay-chat__header" }).append(
        $("<p>", { "class": "refinery-relay-chat__eyebrow", text: "Niimble Relay" }),
        $("<h2>", { "class": "refinery-relay-chat__heading" }),
      ),
      $("<div>", { "class": "refinery-relay-chat__suggestions" }).append(
        $("<h3>", { "class": "refinery-relay-chat__suggestions-heading", text: "Suggested questions" }),
        $("<div>", { "class": "refinery-relay-chat__suggestion-list" })
      ),
      $("<div>", { "class": "refinery-relay-chat__form refinery-relay-chat__form--initial" }).append(
        $("<div>", { "class": "refinery-relay-chat__composer" }).append(
          $("<span>", {
            "class": "refinery-relay-chat__input",
            text: "Ask a question about this organisation's published information…"
          }),
          $("<span>", { "class": "refinery-relay-chat__send", text: "Send" })
        )
      )
    ));
    preview.append($("<footer>", { "class": "refinery-relay-chat__footer" }).append(
      $("<span>", { text: "Answers are generated from this organisation’s published information using AI." }),
      $("<span>", { "class": "refinery-relay-chat__attribution" }).append(
        $("<span>", { text: "Niimble Relay developed by Niimble" })
      )
    ));

    if (podExamplePanel.length) {
      podExamplePanel.append(preview);
    } else {
      ( $(".refinery-relay-theme-fields").length ? $(".refinery-relay-theme-fields") : podItems )
        .after(preview);
    }

    function updatePreview() {
      var questions = suggestedQuestions(podItems);
      var questionList = preview.find(".refinery-relay-chat__suggestion-list").empty();

      preview.find(".refinery-relay-chat__heading").text(fieldValue("#pod_title", "Ask us a question"));

      questions.forEach(function(question) {
        questionList.append($("<span>", {
          "class": "refinery-relay-chat__suggestion",
          text: question
        }));
      });
      preview.find(".refinery-relay-chat__suggestions").toggle(questions.length > 0);

      var theme = {};
      THEME_FIELDS.forEach(function(field) {
        var input = $("#pod_refinery_relay_" + field.key);
        theme[field.key] = input.length && input.val() ? input.val() : field.defaultValue;
      });
      preview[0].style.setProperty("--refinery-relay-accent", theme.accent_color);
      preview[0].style.setProperty("--refinery-relay-accent-soft", rgbaColor(theme.accent_color, 0.09));
      preview[0].style.setProperty("--refinery-relay-accent-focus", rgbaColor(theme.accent_color, 0.13));
      preview[0].style.setProperty("--refinery-relay-accent-text", contrastText(theme.accent_color));
      preview[0].style.setProperty("--refinery-relay-background", theme.background_color);
      preview[0].style.setProperty("--refinery-relay-surface", theme.surface_color);
      preview[0].style.setProperty("--refinery-relay-surface-raised", rgbaColor(theme.text_color, 0.08));
      preview[0].style.setProperty("--refinery-relay-border", rgbaColor(theme.text_color, 0.14));
      preview[0].style.setProperty("--refinery-relay-border-strong", rgbaColor(theme.text_color, 0.28));
      preview[0].style.setProperty("--refinery-relay-text", theme.text_color);
      preview[0].style.setProperty("--refinery-relay-text-muted", rgbaColor(theme.text_color, 0.68));
      preview[0].style.setProperty("--refinery-relay-danger", contrastText(theme.background_color) === "#ffffff" ? "#fca5a5" : "#b91c1c");

      if (podExamplePanel.length && podType.val() === POD_TYPE) {
        podExamplePanel.children(".field").hide();
      }
      preview.toggle(podType.val() === POD_TYPE);
    }

    $("#pod_title").on("input.refineryRelayPreview change.refineryRelayPreview keyup.refineryRelayPreview", updatePreview);
    $("#pod_pod_type").on("change.refineryRelayPreview", updatePreview);
    $(".refinery-relay-theme-fields").on("input.refineryRelayPreview change.refineryRelayPreview", "input", updatePreview);
    podItems.on("input.refineryRelayPreview change.refineryRelayPreview", "input, textarea", updatePreview);

    if (window.MutationObserver && podItems.length) {
      new MutationObserver(updatePreview).observe(podItems[0], { childList: true, subtree: true });
    }

    updatePreview();
  }

  function temporarilyHideLlmChatPodExample() {
    var podType = $("#pod_pod_type");
    var podExample = $(".previews").first();
    if (!podType.length || !podExample.length) return;

    function syncVisibility() {
      podExample.toggle(podType.val() !== POD_TYPE);
    }

    podType.on("change.refineryRelayPreview", syncVisibility);
    syncVisibility();
  }

  $(function () {
    preparePodForm();
    preparePodItemForm();
    prepareThemeFields();
    preparePodSettingsFields();
    // TODO: Re-enable the LLM Chat Pod Example after the admin preview layout is finalised.
    // preparePreview();
    temporarilyHideLlmChatPodExample();
  });
})(jQuery);
