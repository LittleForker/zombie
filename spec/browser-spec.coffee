require "./helpers"
{ vows: vows, assert: assert, zombie: zombie, brains: brains } = require("vows")
jsdom = require("jsdom")


brains.get "/scripted", (req, res)-> res.send """
  <html>
    <head>
      <title>Whatever</title>
      <script src="/jquery.js"></script>
    </head>
    <body>Hello World</body>
    <script>
      document.title = "Nice";
      $(function() { $("title").text("Awesome") })
    </script>
  </html>
  """

brains.get "/living", (req, res)-> res.send """
  <html>
    <head>
      <script src="/jquery.js"></script>
      <script src="/sammy.js"></script>
      <script src="/app.js"></script>
    </head>
    <body>
      <div id="main">
        <a href="/dead">Kill</a>
        <form action="#/dead" method="post">
          <label>Email <input type="text" name="email"></label>
          <label>Password <input type="password" name="password"></label>
          <button>Sign Me Up</button>
        </form>
      </div>
      <div class="now">Walking Aimlessly</div>
    </body>
  </html>
  """
brains.get "/app.js", (req, res)-> res.send """
  Sammy("#main", function(app) {
    app.get("#/", function(context) {
      document.title = "The Living";
    });
    app.get("#/dead", function(context) {
      context.swap("The Living Dead");
    });
    app.post("#/dead", function(context) {
      document.title = "Signed up";
    });
  });
  $(function() { Sammy("#main").run("#/") });
  """

brains.get "/dead", (req, res)-> res.send """
  <html>
    <head>
      <script src="/jquery.js"></script>
    </head>
    <body>
      <script>
        $(function() { document.title = "The Dead" });
      </script>
    </body>
  </html>
  """

brains.get "/soup", (req, res)-> res.send """
  <h1>Tag soup</h1>
  <p>One paragraph
  <p>And another
  """

brains.get "/useragent", (req, res)-> res.send "<body>#{req.headers["user-agent"]}</body>"

brains.get "/title.js", (req, res)-> res.send """
  document.title = "Foobar";
  """

brains.get /\/popup(\/.*)?/, (req, res)-> res.send """
  <html>
    <head>
      <title>#{req.params[0]}</title>
      <script src="/jquery.js"></script>
    </head>
    <body>
      <a href="#popup">Pop up</a>
      <a href="#named-popup">Named pop up</a>
      <a href="#close">Close</a>

      <script>
        function loadScript() {
          var script = document.createElement("script");
          script.src = "http://localhost:3003/title.js";
          document.getElementsByTagName("head")[0].appendChild(script);
        }

        $(function() {
          $("a[href='#popup']").click(function() {
            window.open("http://localhost:3003/popup/two");
            loadScript();

            return false;
          });

          $("a[href='#named-popup']").click(function() {
            window.open("http://localhost:3003/popup/named", "named");
            loadScript();
            return false;
          });

          $("a[href='#close']").click(function() {
            window.close();
            return false;
          });
        });
      </script>
    </body>
  </html>
  """


vows.describe("Browser").addBatch(
  "open page":
    zombie.wants "http://localhost:3003/scripted"
      "should create HTML document": (browser)-> assert.instanceOf browser.document, jsdom.dom.level3.html.HTMLDocument
      "should load document from server": (browser)-> assert.match browser.html(), /<body>Hello World/
      "should load external scripts": (browser)->
        assert.ok jQuery = browser.window.jQuery, "window.jQuery not available"
        assert.typeOf jQuery.ajax, "function"
      "should run jQuery.onready": (browser)-> assert.equal browser.document.title, "Awesome"

  "event emitter":
    "successful":
      topic: ->
        brains.ready =>
          browser = new zombie.Browser
          browser.on "loaded", (browser)=> @callback null, browser
          browser.window.location = "http://localhost:3003/"
      "should fire load event": (browser)-> assert.ok browser.visit
    "error":
      topic: ->
        brains.ready =>
          browser = new zombie.Browser
          browser.on "error", (err)=> @callback null, err
          browser.window.location = "http://localhost:3003/deadend"
      "should fire onerror event": (err)->
        assert.ok err.message && err.stack
        assert.equal err.message, "Could not load document at http://localhost:3003/deadend, got 404"
    "wait over":
      topic: ->
        brains.ready =>
          browser = new zombie.Browser
          browser.on "done", (browser)=> @callback null, browser
          browser.window.location = "http://localhost:3003/"
          browser.wait()
      "should fire done event": (browser)-> assert.ok browser.visit

  "content selection":
    zombie.wants "http://localhost:3003/living"
      "query text":
        topic: (browser)-> browser
        "should query from document": (browser)-> assert.equal browser.text(".now"), "Walking Aimlessly"
        "should query from context": (browser)-> assert.equal browser.text(".now", browser.body), "Walking Aimlessly"
        "should query from context": (browser)-> assert.equal browser.text(".now", browser.querySelector("#main")), ""
        "should combine multiple elements": (browser)-> assert.equal browser.text("form label"), "Email Password "
      "query html":
        topic: (browser)-> browser
        "should query from document": (browser)-> assert.equal browser.html(".now"), "<div class=\"now\">Walking Aimlessly</div>"
        "should query from context": (browser)-> assert.equal browser.html(".now", browser.body), "Walking Aimlessly"
        "should query from context": (browser)-> assert.equal browser.html(".now", browser.querySelector("#main")), ""
        "should combine multiple elements": (browser)-> assert.equal browser.html("title, #main a"), "<title>The Living</title><a href=\"/dead\">Kill</a>"

  "click link":
    zombie.wants "http://localhost:3003/living"
      topic: (browser)->
        browser.clickLink "Kill", @callback
      "should change location": (browser)-> assert.equal browser.location, "http://localhost:3003/dead"
      "should run all events": (browser)-> assert.equal browser.document.title, "The Dead"

  "tag soup":
    zombie.wants "http://localhost:3003/soup"
      "should parse to complete HTML": (browser)->
        assert.ok browser.querySelector("html head")
        assert.equal browser.text("html body h1"), "Tag soup"
      "should close tags": (browser)->
        paras = browser.querySelectorAll("body p").toArray().map((e)-> e.textContent.trim())
        assert.deepEqual paras, ["One paragraph", "And another"]

  "with options":
    topic: ->
      browser = new zombie.Browser
      browser.wants "http://localhost:3003/scripted", { runScripts: false }, @callback
    "should set options for the duration of the request": (browser)-> assert.equal browser.document.title, "Whatever"
    "should reset options following the request": (browser)-> assert.isTrue browser.runScripts

  "user agent":
    topic: ->
      browser = new zombie.Browser
      browser.wants "http://localhost:3003/useragent", @callback
    "should send own version": (browser)-> assert.match browser.text("body"), /Zombie.js\/\d\.\d/
    "specified":
      topic: (browser)->
        browser.visit "http://localhost:3003/useragent", { userAgent: "imposter" }, @callback
      "should send user agent to browser": (browser)-> assert.equal browser.text("body"), "imposter"

  "URL without path":
    zombie.wants "http://localhost:3003"
      "should resolve URL": (browser)-> assert.equal browser.location.href, "http://localhost:3003"
      "should load page": (browser)-> assert.equal browser.text("title"), "Tap, Tap"

  "popups":
    zombie.wants "http://localhost:3003/popup"
      topic: (browser)->
        browser.clickLink "Pop up", @callback
      "should open": (browser)->
        assert.equal browser.windows[1].location.href, "http://localhost:3003/popup/two"
        assert.match browser.windows[1].document.title, /two/
      "should not change the opener": (browser)->
        assert.equal browser.windows[0].location.href, "http://localhost:3003/popup"
      "should be the default window": (browser)->
        assert.equal browser.window, browser.windows[1]
      "should reference its opener": (browser)->
        assert.ok browser.window.opener == browser.windows[0]
      "should evaluate code in the right context": (browser)->
        assert.equal browser.windows[0].document.title, "Foobar"
      "when closed":
        topic: (browser)->
          browser.clickLink "Close", @callback
        "should return focus to its opener": (browser)->
          assert.equal browser.window.document.title, "Foobar"
        "should not exist anymore": (browser)->
          assert.ok !browser.windows[1]

  "named popups":
    zombie.wants "http://localhost:3003/popup"
      topic: (browser)->
        browser.clickLink "Named pop up", @callback
      "should be accessible by name": (browser)->
        assert.equal browser.windows["named"].location.href, "http://localhost:3003/popup/named"
      "when closed":
        topic: (browser)->
          browser.clickLink "Close", @callback
        "should return focus to its opener": (browser)->
          assert.equal browser.window.document.title, "Foobar"
        "should not exist anymore": (browser)->
          assert.ok !browser.windows["named"]

).export(module)
