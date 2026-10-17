# Multiplayer with phones (local, like Jackbox)

Friends play as extra party members using their **phone's web browser**:
no app to install, no internet, nothing paid. The game (on your Windows PC)
runs a tiny web server on your Wi-Fi.

## How a friend joins
1. Start the game on the PC and click **Multiplayer** (main menu or pause menu / Esc).
   The game starts hosting and shows a **QR code**, an **address** like
   `http://192.168.1.23:8080/` and a 4-letter **room code**.
2. The friend's phone must be on the **same Wi-Fi** as the PC.
3. They scan the QR code with the phone camera (or type the address in the browser).
4. They type their **name** (and the room code, already filled in when they
   scan the QR) and tap **Join**. A sheep in their color with their name appears
   behind you.
5. In battle, when the phone says **Your turn!**, they type (or dictate with the
   microphone key on the phone's keyboard) a verse and tap **Recite**. They have
   30 seconds, then the turn is skipped. **Skip turn** skips it right away.
6. If a phone disconnects (screen off, Wi-Fi drop), the page reconnects by itself;
   or open the address again and join with the **same name** to get the same sheep back.

Up to 3 phones join. Click **Stop hosting** in the Multiplayer window to end it
(the phone players leave the party).

## Windows firewall (first time only)
The first time you host, Windows shows "Windows Defender Firewall has blocked some
features of this app". Tick **Private networks** and click **Allow access**.
- From the editor the app is called "Godot Engine"; in an exported game it's your game's .exe.
- If you clicked Cancel: Control Panel > Windows Defender Firewall >
  "Allow an app or feature through Windows Defender Firewall" > Change settings >
  tick **Private** next to Godot / Apologion.
- Your Wi-Fi must be set to **Private** (Settings > Network & internet > Wi-Fi >
  your network > Private network). On "Public", phones can't reach the PC.
- Guest Wi-Fi networks often block devices from seeing each other; use the main Wi-Fi.
- If the address shown doesn't work (PCs with VPNs / virtual network adapters),
  try the other addresses listed under "Not working? Try:".

## Rules for phone players (design)
- **Party:** phone players are added to the computer companion (Pastor Ramuel /
  Baana), they don't replace it: you + companion + up to 3 phones.
- **Verses:** they share your **discovered** verses (the team's list - and a new
  verse a phone player says gets discovered for everyone), but each phone player
  has their **own verse cycle**, so they don't use up your verses or each other's.
- **Damage:** a phone player's verse does **full damage/healing** like yours (the
  computer companion does 25%), because a real person had to recite it.
  They always use the default targets (all enemies / whole party, split).
- **Helping out of turn (heal / Guard / buff verses):** during anyone else's turn in a
  battle, a phone player can recite a **support verse** right away. Support verses are heals,
  Guard (Psalm 17:8...), Faith (attack up for the team) and Zeal. Pick who it's for with the
  **Target** buttons on the phone (yourself, the host, the companion or another phone). Heals
  and Guard go to that one person. Faith boosts the whole team's attacks, and Zeal is the
  host's run/jump boost.
  **Anti-spam:** each phone player gets **one out-of-turn support verse per battle round**
  (a round ends after everyone has had a turn), and it still uses up that verse for their
  cycle. Attack verses only work on your own turn. The phone shows when your out-of-turn
  help is ready ("any time" verses are tagged in the list).
- **Turn order:** by battle speed: you (10), phone players (9), companion (8), enemies.
- **Enemies** still go for the party 25% of the time, picking any standing party member.
- The phone page follows the game's language (English / Español).
- Speech button: browsers only allow speech recognition on https pages, so on your
  home Wi-Fi (plain http) the page shows a tip to use the keyboard's microphone
  key instead. The button appears where the browser allows it.

## iPhone as the host
The iPhone app (see IOS_BUILD.md) can host too: tap Multiplayer, and friends open the
address in Safari on the same Wi-Fi. Allow "find devices on your local network" the first
time, and keep the app open on screen (iOS pauses apps in the background).
Everything stays on your Wi-Fi: **no internet hosting is needed** for this. Playing with
friends somewhere else (over the internet) would need a relay/server, which isn't set up.

## Settings
Project Settings > Phone: **Http Port** (default 8080; the live connection uses
the next port, 8081) and **Turn Timeout** (30 seconds). If the port is busy the
game tries 8082, 8084...
