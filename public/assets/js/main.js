$(function() {

  // ensure we trigger pageviews on each pjax click
  $(document).on('pjax:success', function() {
    if (window.ga) {
      console.log("[pjax] Sending pageview.")
      ga('send', 'pageview');
    }
  });


  $(".view_preview a").click(function() {
    $('html, body').animate({
      scrollTop: $("#preview").offset().top
     });

    return false;
  });

  // login link should always point to redirect back
  $("a.login, a.logout").click(function() {
    var current = $(this).attr("href");
    $(this).attr("href", current + "?redirect=" + Utils.currentPath());
  });

  $("#content").on("click", "a.untruncate", function() {
    var to_hide = $(this).parents(".truncated");
    var tag = to_hide.data("tag");
    $(".untruncated[data-tag=" + tag + "]").show();
    to_hide.hide();
    return false;
  });

  $("#content").on("click", "a.ununtruncate", function() {
    var to_hide = $(this).parents(".untruncated");
    var tag = to_hide.data("tag");
    $(".truncated[data-tag=" + tag + "]").show();
    to_hide.hide();
    return false;
  });

  // $("#content").on("click", 'a[data-pjax]', function() {
  //   Utils.pjax($(this).attr("href"), $(this).data("pjax"));
  //   return false;
  // });

  $(document).pjax("a[data-pjax]", {
    timeout: 5000,
    container: "#center"
  }).on("pjax:error", function(e, xhr, err) {
    Utils.log("Error PJAX loading: " + e.target.baseURI);
  });

  $("#search_form .query_type input[type=radio]").change(function() {
    var queryType = $(".query_type input[type=radio]:checked").val();
    $("ul.search_explain").hide();
    $("ul.search_explain." + queryType).show();

    var placeholder = {
      simple: "Search for a keyword or phrase...",
      advanced: "Enter search terms..."
    }[queryType];

    $("#search_form input.query").attr("placeholder", placeholder);
  });

  $("form#search_form").submit(function() {
    var query = $(this).find("input.query").val();
    if (query) {
      // no empty string
      query = $.trim(query);

      // strip plain wildcard searches down to just the wildcard (which is now allowed)
      query = query.replace(/^[^\w]*\*[^\w]*$/, '*');
    }
    if (!query) query = "*"; // return false;

    var queryType = $(".query_type input[type=radio]:checked").val();

    // if we are on the search page itself, this search box integrates with the filters
    if (typeof(goToSearch) != "undefined") {
      // These two values are cached in separate hidden fields,
      // and not read live from the search box.
      // Editing the search query and switching from simple/advance
      // should only take effect when the user explicitly hits the search button.
      $(".filters input.query").val(query);
      $(".filters input.query_type").val(queryType);
      goToSearch();
    }

    // we're on the home page, just do a bare search
    else {
      var url = "/search/all/" + encodeURIComponent(query);
      if (queryType == "advanced")
        url += "?query_type=" + queryType;
      window.location = url;
    }

    return false;
  });

});

var Utils = {
  log: function(msg) {
    if (typeof(console) != "undefined")
      console.log(msg);
  },

  event: function(category, action, label, value) {
    console.log("Event: " + [category, action, label, value].join(", "));
    if (_gaq) _gaq.push(['_trackEvent', category, action, label, value]);
  },

  pjax: function(href, container) {
    if (!container)
      container = "#center";

    if ($.support.pjax) {
      $.pjax({
        url: href,
        container: container,
        timeout: 5000,
        error: function() {
          Utils.log("Error on PJAX: " + href);
        }
      });
    } else
      window.location = href;
  },

  // returns a path string suitable for redirects back to this location
  currentPath: function(options, bare) {
    var fullDomain = window.location.protocol + "//" + window.location.host;
    var queryString = window.location.href.replace(fullDomain + window.location.pathname, "");

    if (options) {
      if (queryString)
        queryString += "&" + $.param(options);
      else
        queryString = "?" + $.param(options);
    }

    var url = window.location.pathname + queryString;
    return bare ? url : escape(url);
  },

  shareButtons: function(title) {
    if (!title) {
      title = $("#share-title, .entryHeader h2").text();
      title = $.trim(title);
    }
    if (!title) return;

    title = "Scout - " + title;

    $(".share-buttons")
      .attr("data-options", "title=" + encodeURIComponent(title));
      // .attr("data-twitter-tweet-options", "count=none");

    $(".share-buttons").trigger("register").trigger("ready");
  }
};

// all praise to http://stackoverflow.com/a/7720056/16075
// (seriously customized since then)
// var glossaryTextNodes;
function searchHTML(Glossary, container, term) {
  var expr = term.replace(/ /g, "\\s+");
  expr = new RegExp(expr, "gi");
  // var once = false;
  // var expr = new RegExp("(" + terms.join("|") + ")\\b", "gi");

  var elements = container.find("*").andSelf();
  var glossaryTextNodes = elements.contents().not(elements);

  for (var g=0; g < glossaryTextNodes.length; g++) {
    var node = glossaryTextNodes[g];
    var matches = node.nodeValue.match(expr);
    if (matches) {
      // console.log(matches);

      var parts = node.nodeValue.split(expr);
      for (var n = 0; n < parts.length; n++) {
        if (n) {
          // var thisMatch = matches[n-1];
          // console.log(thisMatch);
          // var term = thisMatch.toLowerCase();
          // console.log(term);

          var elem = $("<span />");
          // if (!once) {
            elem.addClass("glossary");
            elem.attr("title", Glossary.definitions[term].long_definition_html);
            // elem.data("term", term);
            elem.data("long_definition_html", Glossary.definitions[term].long_definition_html);
          // }
          // once = true;

          elem.text(matches[n-1]).insertBefore(node);
        }
        if (parts[n])
          $(document.createTextNode(parts[n])).insertBefore(node);
      }
      $(node).remove();
    }
  }
}