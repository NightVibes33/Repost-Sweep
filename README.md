# Repost Sweep

Repost Sweep is an iPhone and iPad app for clearing TikTok reposts in bulk. You sign in on TikTok’s own website inside the app, review the reposts, and remove the ones you choose. Original videos stay up. Removing a repost only takes it off your reposts tab.

**Repost Sweep is not affiliated with, endorsed by, or sponsored by TikTok or ByteDance.**

The app never asks for, reads, or stores your TikTok password. The sign-in session stays in an in-app browser (`WKWebView`). Cookies are not copied into app storage.

## Requirements

- iOS 16 or later
- Xcode 16 or later, with the iOS SDK, for a local build
- No manual Xcode clicking. The project is `project.yml` (XcodeGen). CI generates the Xcode project and builds it.

## Build an unsigned IPA

The build script downloads XcodeGen 2.46.0 on first run (the binary plus its settings files), generates `RepostSweep.xcodeproj`, runs one `xcodebuild`, and zips `Payload/RepostSweep.app` into `RepostSweep-unsigned.ipa`. Signing is off (`CODE_SIGNING_ALLOWED=NO`).

### GitHub Actions

Workflow: [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)

- Runs on `macos-latest`
- Triggers: **Run workflow** (`workflow_dispatch`) and **pushes to `main`**
- Cancels an in-progress run when a newer one starts on the same ref
- Caches XcodeGen and Swift Package Manager
- 20 minute job timeout
- One build step, then uploads `RepostSweep-unsigned-ipa`

On a private free GitHub account, macOS minutes are billed at 10x, which is why the workflow does not install extra tools, run tests, or cache DerivedData.

Open the Actions tab, run **Unsigned IPA** (or push to `main`), and download the artifact. Artifacts are kept for 14 days.

### On a Mac

```bash
bash scripts/build-unsigned-ipa.sh
```

The IPA is written to `RepostSweep-unsigned.ipa`. You need full Xcode, not just the Command Line Tools. The first run downloads XcodeGen. Later runs reuse `.tools/xcodegen` (gitignored).

`RepostSweep.storekit` is attached to the generated scheme so a local Run in Xcode can load the placeholder subscriptions. CI does not need that file to compile.

## Sideload the IPA

An unsigned IPA will not install by itself. Re-sign it with an Apple ID, then trust the certificate on the device.

**Sideloadly (Mac or Windows)**

1. Download the artifact and unzip it if GitHub wrapped it.
2. Install [Sideloadly](https://sideloadly.io).
3. Connect the iPhone, drag `RepostSweep-unsigned.ipa` into Sideloadly, and sign in with an Apple ID.
4. Sideloadly signs the IPA and installs it.
5. On the device: Settings → General → VPN & Device Management → trust the developer.

**AltStore**

1. Install AltStore with AltServer.
2. Sideload `RepostSweep-unsigned.ipa` from AltStore. AltStore signs it with the Apple ID you used for AltServer.
3. Trust the certificate the same way as above.

A free Apple ID provisioning profile expires in about 7 days. Install again when it does. A paid Apple Developer account lasts about a year.

StoreKit purchases do not complete on a sideloaded build. The 10 free removals still work. Subscriptions start working on TestFlight or the App Store after the products below exist and the app is signed with bundle id `app.repostsweep.ios`.

## App Store Connect subscriptions

Product IDs live only in [`RepostSweep/Config/Monetization.swift`](RepostSweep/Config/Monetization.swift). Create the App Store products with these exact strings:

| | |
| --- | --- |
| Bundle ID | `app.repostsweep.ios` |
| Subscription group | `Repost Sweep Premium` |
| Weekly product ID | `app.repostsweep.premium.weekly` |
| Yearly product ID | `app.repostsweep.premium.yearly` |
| Free removals | 10 per device, then the subscription removes the cap |

Suggested starting prices, which you type into App Store Connect (the app displays the price StoreKit returns, not a hard-coded one):

- Weekly: $4.99, duration 1 week
- Yearly: $29.99, duration 1 year

Setup:

1. Enroll in the Apple Developer Program.
2. Register the App ID `app.repostsweep.ios` with In-App Purchase enabled.
3. Create the app record in App Store Connect.
4. Create a subscription group named **Repost Sweep Premium**.
5. Add two auto-renewable subscriptions using the product IDs above. Set display name and description (Weekly / Yearly is enough to start).
6. Add a paid-apps agreement, banking, and tax so products can be purchased.
7. Put the same product IDs in a new version’s In-App Purchases section.
8. For a local Xcode run, the scheme already points at `RepostSweep.storekit`, which mirrors those IDs at $4.99 and $29.99.
9. Archive a **signed** build for TestFlight. The CI workflow stays unsigned on purpose and is not the App Store upload.

The paywall states that payment is charged to the Apple ID, that the subscription renews until canceled at least 24 hours before the period ends, and that it is managed in App Store settings. Host the in-app privacy text at a URL before you submit. Settings → Privacy is the source copy.

The free-removal counter is on-device (`UserDefaults`). Deleting the app resets it. Subscriptions are checked with StoreKit 2.

## How a sweep works

1. The app opens `tiktok.com` in a `WKWebView`. Sign-in, including two-factor and any captcha, is TikTok’s page. The script does not read password fields.
2. After you are signed in, the page script reads your own account id from the page TikTok already rendered.
3. It asks TikTok’s website for your repost list (`/api/repost/item_list/`) from inside that page, so the website’s own request signing can run. Thumbnails are loaded through the same page when the cover URL allows it.
4. For each selected repost it calls TikTok’s unrepost action (`/tiktok/v1/upvote/delete/`, then `/api/repost/item/delete/` only if the first path is missing). It does not call a video-delete endpoint.
5. Removals are spaced about 2.2–3.4 seconds apart, with a longer pause and one retry if TikTok rate-limits. The progress screen can pause or stop. Stop does not undo removals that already succeeded.
6. If the repost list shape changes, the app tries the Reposts tab on your profile. It only uses that fallback after it finds the Reposts tab, so it does not treat your original posts as reposts.

The only TikTok-specific file is [`RepostSweep/Resources/TikTokBridge.js`](RepostSweep/Resources/TikTokBridge.js).

## When TikTok changes the site

The app shows a full explanation instead of a generic error: what happened, what was not changed (password, original videos, removals already finished), and what to do next (update the app, or remove a repost by hand with Share → Remove repost).

A short technical code is tucked under “Technical detail” for whoever ships the update. That update is a change to `TikTokBridge.js`, then a new IPA. There is no Xcode step beyond the build script.

## Known limits

- TikTok signs web requests inside its own page script (often called X-Bogus or X-Gnarly). Repost Sweep calls `fetch` from that signed-in page so TikTok’s script can attach them. If TikTok stops hooking `fetch`, or requires a new header, listing and removal break until `TikTokBridge.js` is updated. The app stops and explains that, rather than guessing.
- `/api/repost/item_list/` and the unrepost paths are private website endpoints, not a public API. TikTok can change them without notice.
- Reposts are not offered in every region or on every account. A real empty tab is an empty state. A page that no longer matches this version is the “TikTok changed the page” screen.
- Covers that TikTok’s CDN refuses to serve show a placeholder. The removal still uses the video id.
- Large tabs take real time because of the pause between removals. A few hundred reposts is a long sit. Pause and stop are there for that.
- The profile-grid fallback runs only if the Reposts tab control can be found, and its “Reposts” text match is English. The API path does not depend on English.
- Captchas and two-factor prompts are TikTok’s. You solve them in the web view. The app does not bypass them.
- The session can expire. Sign in again. Signing out clears the in-app browser data.
- The free tier is per device, not per TikTok account. Reinstalling resets the 10.
- Sideloaded builds cannot finish App Store purchases.
- This build has no analytics SDK.
- The iPhone UI is portrait. iPad can rotate.

## Launch and marketing

Positioning: clean the public repost tab in one sitting. The people who pay are the ones who reposted sounds and trends until the tab looked like a mess, and creators who want a reset before a brand look.

Do not use TikTok’s logo, do not say “official,” and keep the not-affiliated line in the App Store description. Use the name TikTok only to say what the app works with.

**Three videos to post**

1. Screen recording of a repost grid going from crowded to empty. On-screen text: “I didn’t know you could clear reposts in one pass.” 12–18 seconds, a trending sound, no App Store badge in the first second.
2. Talking head, before and after the profile. “Your reposts are public. Here’s mine.”
3. A reply to a high-view “how do I delete all my TikTok reposts” video. Show the manual Share → Remove repost once, then the sweep.

**Cadence**

Post one of those a day for two weeks from a creator account plus two UGC faces. Caption includes “Repost Sweep” and a link in bio. On other people’s videos, leave a useful manual answer first. Mention the app once. Don’t paste the same comment.

**App Store**

- Name: Repost Sweep
- Subtitle: Bulk remove TikTok reposts
- Keywords to try: repost, unrepost, delete reposts, clean profile, bulk remove
- Yearly plan selected by default on the paywall. Weekly is the impulse price for “I need this gone today.”
- Review notes should say the reviewer signs in with their own TikTok account, the app never sees the password, and removal does not delete original videos.

App Review can reject apps that automate a third-party service or imply a partnership. The in-app disclaimer, a non-TikTok icon, and nominative wording are the mitigations. Budget for a rejection and a resubmit.

## Next steps to ship

1. Run the IPA workflow and sideload it onto a phone.
2. Sign in to a TikTok account you own and confirm the repost list, thumbnails, and one removal. Confirm an original upload is still there afterward.
3. If the site-change screen appears on a current TikTok website, update `TikTokBridge.js` and ship another IPA.
4. Join the Apple Developer Program and create the App ID `app.repostsweep.ios`.
5. Create the subscription group and the two product IDs in App Store Connect.
6. Host the privacy text from Settings → Privacy at a public URL.
7. Produce a signed archive (Xcode archive or a later signing workflow) and upload to TestFlight. Keep the unsigned workflow for quick sideload builds.
8. Record the three videos above and submit the App Store listing with the disclaimer in the description.

## Project layout

```
project.yml                         XcodeGen spec
RepostSweep.storekit                Local StoreKit products for Xcode Run
scripts/build-unsigned-ipa.sh       The CI build
.github/workflows/build-ipa.yml     Unsigned IPA workflow
RepostSweep/Config/Monetization.swift
RepostSweep/Resources/TikTokBridge.js
RepostSweep/Assets.xcassets         Icon and launch color
```

The app icon is the opaque artwork in `RepostSweep/Assets.xcassets/AppIcon.appiconset`. `scripts/render-icon.py` does not draw or replace those files.
