(function ($) {
  "use strict";

  var POD_TYPE = "llm_chat";

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

  $(function () {
    preparePodForm();
    preparePodItemForm();
  });
})(jQuery);
