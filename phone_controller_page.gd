extends RefCounted
# The web page a friend's phone shows (served by phone_server.gd).
# -----------------------------------------------------------------
# It's plain HTML + CSS + JavaScript in one string, so it gets exported with
# the game automatically (no extra files). The host replaces these words
# before sending it:
#   __WS_PORT__  -> the WebSocket port (http port + 1)
#   __LANG__     -> "en", "es" or "pl" (the host's language)
#   __UI_JSON__  -> the page's texts, translated with tr() (see UI_KEYS)
#
# The phone and the game talk with small JSON messages over a WebSocket:
#   phone -> game: {"t":"join","name":..,"room":..}  {"t":"verse","text":..,"target":i}  {"t":"skip"}
#                  (target = index in the state's party list: who a heal / Guard goes to)
#   game -> phone: {"t":"joined",..}  {"t":"error","text":..}  {"t":"note","text":..}
#                  {"t":"state", ...everything the page shows...}
#
# Speech: browsers only allow the Web Speech API on secure (https) pages, and
# this page is plain http on your Wi-Fi, so the "Speak" button usually hides
# itself and the page suggests the microphone key on the phone's keyboard
# (dictation), which works everywhere.

# English keys; the host sends tr(key) for each one (General/translations/strings.csv)
const UI_KEYS = [
	"Join the game", "Your name", "Room code", "Join", "Type or say a verse...",
	"Recite", "Speak", "Skip turn", "Your turn!", "Waiting for %s", "Not in a battle",
	"Discovered verses", "Battle", "Party", "used", "Reconnecting...", "Knocked out",
	"Tip: tap the microphone on your phone's keyboard to dictate a verse.",
	"Listening...", "%d s left", "Each verse can be used once per cycle (yours).",
	"No messages yet", "No verses discovered yet",
	"Target for heal / Guard:", "(you)", "any time",
	"Not your turn - heal, Guard and buff verses work now (1 per round)",
	"You helped this round - wait for the next round",
]

const HTML = r"""<!DOCTYPE html>
<html lang="__LANG__">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>Apologion</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         background: #111; color: #eee; font-size: 17px; }
  header { background: #1d1d2b; padding: 10px 14px; display: flex; align-items: center; gap: 10px; }
  header h1 { font-size: 20px; margin: 0; flex: 1; letter-spacing: 1px; }
  .dot { width: 16px; height: 16px; border-radius: 50%; display: inline-block; }
  main { padding: 12px; max-width: 560px; margin: 0 auto; }
  .card { background: #1c1c1c; border-radius: 12px; padding: 12px; margin-bottom: 12px; }
  label { display: block; margin: 8px 0 4px; color: #bbb; font-size: 15px; }
  input, textarea { width: 100%; font-size: 20px; padding: 12px; border-radius: 10px;
                    border: 2px solid #444; background: #000; color: #fff; }
  textarea { min-height: 110px; resize: vertical; }
  button { font-size: 20px; padding: 14px; border-radius: 10px; border: none; cursor: pointer;
           background: #f0c040; color: #111; font-weight: bold; }
  button:disabled { opacity: 0.4; }
  button.secondary { background: #444; color: #eee; }
  .row { display: flex; gap: 8px; margin-top: 8px; }
  .row button { flex: 1; }
  #turn { font-size: 22px; font-weight: bold; text-align: center; padding: 14px; border-radius: 12px;
          background: #2a2a2a; margin-bottom: 12px; }
  #turn.mine { background: #2f7d32; animation: pulse 1s infinite alternate; }
  @keyframes pulse { from { filter: brightness(1); } to { filter: brightness(1.25); } }
  .hpbar { height: 14px; background: #400; border-radius: 7px; overflow: hidden; }
  .hpbar div { height: 100%; background: #3c3; }
  .member .st { font-size: 12px; color: #9cf; margin-top: 2px; }
  .member { margin: 6px 0; }
  .member .name { display: flex; justify-content: space-between; font-size: 15px; }
  .verse { border-bottom: 1px solid #333; padding: 8px 0; }
  .verse.used { opacity: 0.45; }
  .verse b { color: #f0c040; }
  .verse small { color: #9cf; display: block; }
  #messages div { padding: 4px 0; border-bottom: 1px solid #2a2a2a; font-size: 15px; }
  #note { min-height: 22px; color: #ffcc66; margin-top: 8px; }
  #error { color: #ff6b6b; min-height: 22px; margin-top: 8px; }
  #status { font-size: 14px; color: #aaa; }
  .hint { color: #999; font-size: 14px; margin-top: 6px; }
  h2 { font-size: 17px; margin: 0 0 6px; color: #ccc; }
  .hidden { display: none !important; }
  #targets { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
  #targets button { flex: 0 0 auto; font-size: 16px; padding: 10px 12px; background: #333; color: #eee; }
  #targets button.sel { background: #5aa0ff; color: #000; }
  #supportInfo { color: #8fd18f; font-size: 15px; margin-top: 6px; min-height: 18px; }
  .tag { background: #2f5d2f; color: #cfc; border-radius: 6px; padding: 1px 6px; font-size: 12px; margin-left: 6px; }
</style>
</head>
<body>
<header><span class="dot" id="mydot" style="background:#666"></span><h1>APOLOGION</h1><span id="status"></span></header>
<main>
  <section id="joinScreen" class="card">
    <h2 data-ui="Join the game"></h2>
    <label data-ui="Your name"></label>
    <input id="nameInput" maxlength="16" autocomplete="nickname">
    <label data-ui="Room code"></label>
    <input id="roomInput" maxlength="4" autocapitalize="characters" style="text-transform:uppercase">
    <div class="row"><button id="joinButton" data-ui="Join"></button></div>
    <div id="error"></div>
  </section>

  <section id="gameScreen" class="hidden">
    <div id="turn"></div>
    <div class="card">
      <textarea id="verseInput"></textarea>
      <div class="row">
        <button id="reciteButton" data-ui="Recite"></button>
        <button id="speakButton" class="secondary hidden" data-ui="Speak"></button>
        <button id="skipButton" class="secondary" data-ui="Skip turn"></button>
      </div>
      <div id="supportInfo"></div>
      <div class="hint" data-ui="Target for heal / Guard:"></div>
      <div id="targets"></div>
      <div id="speechHint" class="hint" data-ui="Tip: tap the microphone on your phone's keyboard to dictate a verse."></div>
      <div id="note"></div>
    </div>
    <div class="card"><h2 data-ui="Party"></h2><div id="party"></div></div>
    <div class="card"><h2 data-ui="Battle"></h2><div id="messages"></div></div>
    <div class="card"><h2 data-ui="Discovered verses"></h2>
      <div class="hint" data-ui="Each verse can be used once per cycle (yours)."></div>
      <div id="verses"></div></div>
  </section>
</main>
<script>
var WS_PORT = "__WS_PORT__";
var lang = "__LANG__";
var ui = __UI_JSON__;
var ws = null, joined = false, myName = "", myRoom = "", lastState = null, retryTimer = null, target = -1;
var $ = function (id) { return document.getElementById(id); };

function t(key) { return (ui && ui[key]) ? ui[key] : key; }
function applyUi() {
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-ui]").forEach(function (el) { el.textContent = t(el.getAttribute("data-ui")); });
  $("verseInput").placeholder = t("Type or say a verse...");
}

// Room code from the QR code link (?r=ABCD), name remembered on this phone
var params = new URLSearchParams(location.search);
$("roomInput").value = (params.get("r") || localStorage.getItem("apologion_room") || "").toUpperCase();
$("nameInput").value = localStorage.getItem("apologion_name") || "";
applyUi();

function send(obj) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj)); }

function connect() {
  clearTimeout(retryTimer);
  ws = new WebSocket("ws://" + location.hostname + ":" + WS_PORT + "/");
  ws.onopen = function () {
    $("status").textContent = "";
    if (myName) send({ t: "join", name: myName, room: myRoom });   // (re)join the same slot by name
  };
  ws.onmessage = function (e) {
    var msg; try { msg = JSON.parse(e.data); } catch (err) { return; }
    if (msg.t === "joined") {
      joined = true;
      localStorage.setItem("apologion_name", myName);
      localStorage.setItem("apologion_room", myRoom);
      $("joinScreen").classList.add("hidden");
      $("gameScreen").classList.remove("hidden");
      $("mydot").style.background = msg.color;
    } else if (msg.t === "error") {
      $("error").textContent = msg.text;
      if (!joined) { myName = ""; $("joinButton").disabled = false; }
    } else if (msg.t === "note") {
      $("note").textContent = msg.text;
    } else if (msg.t === "state") {
      render(msg);
    }
  };
  ws.onclose = function () {
    $("status").textContent = t("Reconnecting...");
    retryTimer = setTimeout(connect, 2000);
  };
}

$("joinButton").onclick = function () {
  myName = $("nameInput").value.trim();
  myRoom = $("roomInput").value.trim().toUpperCase();
  $("error").textContent = "";
  if (!ws || ws.readyState !== 1) { connect(); } else { send({ t: "join", name: myName, room: myRoom }); }
  $("joinButton").disabled = true;
  setTimeout(function () { $("joinButton").disabled = false; }, 1500);
};

$("reciteButton").onclick = function () {
  var text = $("verseInput").value.trim();
  if (!text) return;
  send({ t: "verse", text: text, target: target });
  $("note").textContent = "";
};
$("verseInput").addEventListener("keydown", function (e) {
  if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); $("reciteButton").click(); }
});
$("skipButton").onclick = function () { send({ t: "skip" }); };

// Speech (only where the browser allows it: Chrome/Safari on https or localhost)
var Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
if (Recognition && window.isSecureContext) {
  $("speakButton").classList.remove("hidden");
  $("speechHint").classList.add("hidden");
  $("speakButton").onclick = function () {
    var rec = new Recognition();
    rec.lang = (lang === "es") ? "es-ES" : (lang === "pl") ? "pl-PL" : "en-US";
    rec.interimResults = false;
    $("speakButton").textContent = t("Listening...");
    rec.onresult = function (e) { $("verseInput").value = e.results[0][0].transcript; };
    rec.onend = function () { $("speakButton").textContent = t("Speak"); };
    rec.onerror = function () { $("speakButton").textContent = t("Speak"); };
    rec.start();
  };
}

function bar(hp, max) {
  var pct = max > 0 ? Math.max(0, Math.min(100, hp / max * 100)) : 0;
  return '<div class="hpbar"><div style="width:' + pct + '%"></div></div>';
}
function esc(s) { var d = document.createElement("div"); d.textContent = s; return d.innerHTML; }

function render(s) {
  lastState = s;
  if (s.lang !== lang || JSON.stringify(s.ui) !== JSON.stringify(ui)) { lang = s.lang; ui = s.ui; applyUi(); }
  var turn = $("turn");
  if (s.your_turn) {
    turn.className = "mine";
    turn.textContent = t("Your turn!") + "  " + t("%d s left").replace("%d", s.time_left);
  } else {
    turn.className = "";
    turn.textContent = s.in_battle ? t("Waiting for %s").replace("%s", s.turn_name) : t("Not in a battle");
  }
  $("reciteButton").disabled = !(s.your_turn || s.support_ready);
  $("skipButton").disabled = !s.your_turn;
  $("supportInfo").textContent = (s.in_battle && !s.your_turn) ? (s.support_ready ? t("Not your turn - heal, Guard and buff verses work now (1 per round)") : t("You helped this round - wait for the next round")) : "";
  var tg = "";
  if (target < 0 || target >= s.party.length) target = s.me;
  s.party.forEach(function (m) {
    tg += '<button data-i="' + m.i + '" class="' + (m.i === target ? "sel" : "") + '">' + esc(m.name) + (m.i === s.me ? " " + esc(t("(you)")) : "") + "</button>";
  });
  $("targets").innerHTML = tg;
  $("targets").querySelectorAll("button").forEach(function (b) {
    b.onclick = function () { target = parseInt(b.getAttribute("data-i")); render(lastState); };
  });
  var party = "";
  s.party.forEach(function (m) {
    party += '<div class="member"><div class="name"><span>' + (m.color ? '<span class="dot" style="width:10px;height:10px;background:' + m.color + '"></span> ' : '') +
      esc(m.name) + (m.ko ? " (" + esc(t("Knocked out")) + ")" : "") + '</span><span>' + Math.round(m.hp) + " / " + m.max_hp + '</span></div>' + bar(m.hp, m.max_hp) +
      (m.st && m.st.length ? '<div class="st">' + esc(m.st.join("  ")) + '</div>' : '') + '</div>';
  });
  $("party").innerHTML = party;
  var msgs = "";
  s.messages.slice().reverse().forEach(function (m) { msgs += "<div>" + esc(m) + "</div>"; });
  $("messages").innerHTML = msgs || '<div class="hint">' + esc(t("No messages yet")) + "</div>";
  var verses = "";
  s.verses.forEach(function (v) {
    verses += '<div class="verse' + (v.used ? " used" : "") + '"><b>' + esc(v.ref) + "</b>" + (v.support ? '<span class="tag">' + esc(t("any time")) + "</span>" : "") + (v.used ? " (" + esc(t("used")) + ")" : "") +
      "<small>" + esc(v.power) + "</small>" + esc(v.text) + "</div>";
  });
  $("verses").innerHTML = verses || '<div class="hint">' + esc(t("No verses discovered yet")) + "</div>";
}

connect();
</script>
</body>
</html>
"""


# The page with the port, language and texts filled in
static func build(ws_port: int, lang: String, ui: Dictionary) -> String:
	return HTML.replace("__WS_PORT__", str(ws_port)).replace("__LANG__", lang).replace("__UI_JSON__", JSON.stringify(ui))
