# Apologion on iPhone (native app, free Apple ID)

> With the paid Apple Developer Program you can skip all of this and install builds from
> TestFlight instead: see **TESTFLIGHT.md**.

The repo has an **iOS export preset** (Project > Export > iOS) with everything set up:
bundle id `com.veritasvanguard.apologion`, name **Apologion**, landscape only, icons
(made from `icon.svg`, in `icons/ios/`), the microphone message and the local-network message
(needed so friends' phones can join over Wi-Fi). There are no passwords or certificates
in the repo. Your Apple ID signs the app on your Mac.

## What you need
- A Mac with **Xcode** (free from the Mac App Store, about 10 GB).
- Your **Apple ID** (the free one works).
- The iPhone and its USB/USB-C cable.
- **iOS 18.5 or newer** on the iPhone (the voice library needs it).
- Godot **4.7.2** with its **export templates** (only needed for option B).

## Option A: open the ready-made Xcode project (fastest)
1. Unzip `apologion_ios_xcode.zip` (you get the `apologion_ios` folder).
2. Double-click `apologion_ios/Apologion.xcodeproj` to open it in Xcode.
3. On the left, click the blue **Apologion** project, then the **Apologion** target, then the
   **Signing & Capabilities** tab.
4. Tick **Automatically manage signing**. Under **Team**, pick **Add an Account...** and sign
   in with your Apple ID, then pick "*Your Name (Personal Team)*". (The project has a
   placeholder team `ABCDE12345`; choosing your team replaces it.)
   - If Xcode says the bundle id is taken, change the **Bundle Identifier** to something
     unique, e.g. `com.veritasvanguard.apologion.yourname`.
5. Plug in the iPhone and tap **Trust** on the phone.
6. On the iPhone, turn on **Developer Mode**: Settings > Privacy & Security > Developer Mode,
   then restart the phone and confirm. (The option only appears after the phone has been
   plugged into Xcode once.)
7. At the top of the Xcode window, pick your iPhone as the run destination and press **Run** (the play button).
8. The first time, the phone says "Untrusted Developer". Go to Settings > General >
   **VPN & Device Management**, tap your Apple ID, then tap **Trust**. Press Run again.

## Option B: export it yourself from Godot on the Mac (after you change the game)
1. Install the export templates: Godot > Editor > **Manage Export Templates** > Download and Install.
2. Project > Export > **iOS**. Under **Application > App Store Team ID**, type your 10-character
   Team ID. Xcode shows it in Settings > Accounts > your Apple ID > your team. It's also
   in the Team ID field of any project you've signed.
3. Set **Export Project Only** on, then click **Export Project...** and save it in `build/ios/`.
   (`build/` is git-ignored.)
4. Open `build/ios/Apologion.xcodeproj` and follow steps 3–8 of Option A.
   (With "Export Project Only" off and your Team ID filled in, Godot can build and install
   it for you with the **Remote Debug / one-click deploy** button too.)

## Things to know
- **Free Apple ID: the app stops opening after 7 days.** Plug the phone in and press Run
  again to renew it for another 7 days. A free account can have up to 3 of your own apps on a phone.
- **Your friend's iPhone:** plug it into the same Mac, trust it, turn on Developer Mode,
  pick it in Xcode and press Run. It's signed with your Apple ID (same 7-day limit).
- **TestFlight** (friends install over the internet, builds last 90 days) needs the paid
  **Apple Developer Program, $99/year**. Then: Product > Archive > Distribute App > TestFlight,
  and invite them by email in App Store Connect.
- **Playing together:** one phone hosts (Multiplayer button). The other phones open the
  address or QR code in **Safari**, on the same Wi-Fi (see MULTIPLAYER.md). The first time
  you host, iPhone asks "Allow Apologion to find devices on your local network?" Tap **Allow**.
  Keep the host's app open on screen: iOS pauses apps in the background, and that also pauses the server.
- **Voice:** hold **Mic** and speak. The first time, iOS asks to use the microphone.
  Speech is turned into text on the phone (Whisper tiny model, ~32 MB, inside the app).
  If voice can't start on a phone, the game says so. Tap **Type** and use the
  microphone key on the iPhone keyboard instead.
- **Touch controls** show up on touch screens: < > to walk, ^ to talk or enter doors, Jump,
  Ram (hold until the bar fills), II pause, Verses (the Tab list), Bag (inventory), Type (opens
  the keyboard), Mic (hold to talk). In battles the Skip / Target buttons are on the right.
  Turn them off in Settings > "Touch controls (phones and tablets)".

## Option C: ad-hoc build from GitHub Actions (no Mac, no TestFlight review)

An ad-hoc build installs only on iPhones whose UDIDs are registered in the Apple
Developer account and listed in the Ad Hoc provisioning profile. No App Review and no
TestFlight. On iOS 16+ the phone may say "Developer Mode Required" the first time: turn it on
in Settings > Privacy & Security > Developer Mode (the phone restarts, then confirm with the passcode).

**Build it:** Actions > "iOS TestFlight" > Run workflow > distribution = `ad-hoc`, or

    gh workflow run ios-testflight.yml -R veritasvanguardvv/apologion --ref main -f distribution=ad-hoc

The signed `.ipa` is attached to the run as the `Apologion-adhoc-<run>` artifact (kept 30 days).
Nothing is uploaded to TestFlight. Install it with Apple Configurator / Finder (cable), or
over the air from an HTTPS `itms-services://` link (an `.ipa` plus a `manifest.plist`).

**Add an iPhone:** get its UDID (Finder/Apple Configurator, or a UDID-profile site), then
regenerate the profile, which includes every enabled registered iPhone, and update the secret:

    python3 tools/ios_ci/asc_setup.py --key-id KEY_ID --issuer-id ISSUER_ID --p8 AuthKey_KEY_ID.p8 \
      adhoc --device "Name iPhone=UDID" --out ~/.apologion-ios-signing --set-secrets

Then rerun the ad-hoc workflow; builds made before the device was added will not install on it.
Apple allows 100 iPhones per membership year. The profile expires after a year (or when the
distribution certificate does); rerun the `adhoc` command without `--device` to renew it.
