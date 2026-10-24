# Apologion on TestFlight (no Mac needed)

Every TestFlight build is made on a GitHub-hosted Mac by `.github/workflows/ios-testflight.yml`:
Godot 4.7.2 exports the Xcode project, Xcode 26 archives and signs it, and the `.ipa` is uploaded
to App Store Connect. You install it from the **TestFlight** app on your iPhone.

## One-time setup (you, in a browser)
1. **App Store Connect > Apps > + > New App**: platform iOS, name *Apologion* (or any free name),
   language, bundle ID **com.veritasvanguard.apologion** (if it isn't in the list yet, it gets
   registered by step 3, then refresh), SKU e.g. `apologion`. Apple's API can't create this record.
2. **Users and Access > Integrations > App Store Connect API > Team Keys > +**:
   name "Apologion CI", access **Admin** (needed to create the signing certificate and profile).
   Download the `.p8` file (only once) and note the **Key ID** and the **Issuer ID**.
3. Hand those three over. `tools/ios_ci/asc_setup.py signing --set-secrets` then registers the
   bundle ID, creates an Apple Distribution certificate and an App Store profile, and stores the
   six repo secrets. `asc_setup.py testers --email you@example.com` makes an internal group that
   gets every build automatically.
4. On the iPhone: install **TestFlight** from the App Store and sign in with the same Apple ID.

## Making a build
Actions tab > **iOS TestFlight** > **Run workflow** (or `gh workflow run ios-testflight.yml`).
About 10 minutes on the Mac, then 5-30 minutes of Apple processing; TestFlight shows the new build.
Build numbers come from the run number; the version comes from the iOS export preset.

## Repo secrets
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `IOS_DIST_P12_BASE64`, `IOS_DIST_P12_PASSWORD`,
`IOS_PROFILE_BASE64`. The certificate and profile last one year; re-run `asc_setup.py signing`
to renew them.
