# Evidence and reconstruction boundaries

## Target identity

Supplied artifact: `yaoshibao.apk`, package `com.bluelight.elevatorguard`, version name **4.5.0**, version code **40450**, minimum Android SDK 21 / target SDK 31.

- SHA-256: `575343454ffde12921b1a78fb6cc9d192e25d68c139f67ceb0d8d9b08aceda95`.
- MD5: `79b34c67b2f999eedeaef669b93dc4ba`, matching the advertised MD5 in the saved Tencent store page. This comparison does not authenticate the APK signing certificate; certificate verification was not performed.
- REA `open_binary` identified the APK and its SHA-256. REA's `inspect_android_package` returned `capability_unavailable`: this session lacks its separately supplied `jadx-headless-mcp 0.7.1` bridge. No claim is made that REA produced the decompiled Java.
- Fallback: portable upstream JADX **1.5.6**, downloaded from the `skylot/jadx` GitHub release through its asset API, Java 21, static decompilation with four workers. JADX reported **110 errors across the full app**. The functions cited below were readable; coverage of the entire application is incomplete. No APK execution, emulator, or live service requests occurred.

The earlier supplied DMG contained Tencent's installer rather than the APK. Its inventory Evidence IDs are retained separately in `../yaoshibao-evidence.json` relative to the project directory:

- `ev_0b9cf6551b719587f0e3452f0fa9abfbd03aad84aea03929369def9976248582` (inventory).
- `ev_aa80c27ebfd5fca2bf2df23331ef218fbc569a1468e375a5fb90def203d69081` (inspection).

## Observed static behavior

Paths below are relative to `../yaoshibao-research/decompiled/sources/` on the development machine.

| Question | Source | Observation |
| --- | --- | --- |
| Login and SMS | `com/bluelight/elevatorguard/activities/LoginActivity.java`, methods `x`, `y`, `C`, `D`; `common/utils/network/v.java`, method `I` | `captcha01` receives mobile and an encrypted seconds timestamp; `auth` receives mobile, captcha, model, device ID. Code `100` is success. |
| Transport | `constant/e.java`; `common/utils/network/v.java`, method `C` | Base URL `http://app.keyboot.com:8667/`; POST form field `jiami_data`; responses are encrypted base64 strings. |
| AES envelope | `common/utils/p.java`, method `d`; `common/utils/o.java`, methods `G`, `m`, `z`; `common/j.java` | AES-256-CBC, UTF-8 fixed 32-byte key / 16-byte IV, PKCS padding. Static interoperability constants are embedded in the app. They are not an account token. |
| Refresh | `common/utils/network/v.java`, methods `R0`, `x0`; `common/utils/a0.java` | `renew02` carries mobile/device/token/model/appversion and can return rotated token and server time. |
| Authorized doors | `bean/MyKeyDataBean.java`, `bean/KeyBean.java`; `common/v.java`, method `q` | `owner_keys`, `gate_keys`, `visitor_keys`; project/license, floor or floor masks, expiry, ID and type determine a request. Types 6/7 call `key_verification`. |
| Bluetooth selection | `common/e.java`, callbacks `b` and `c` | 14-character local names; exact project/license names or a project-wide prefix; RSSI above -85. The prototype excludes wildcard/test names found in one callback. |
| Challenge | `service/BleService.java`, `getEncryptToken`, callback `AnonymousClass5`; `common/utils/o.java`, method `C`; `p1/g.java` | FFC0 service, read an 18-byte FFC1 value, reverse bytes 8–15, TEA 32 rounds, write framed response to FFC2. |
| Opening payload | `common/utils/o.java`, methods `D`, `E`, `Y`; `common/j.java`; `service/BleService.java`, method `sendMsgToPeriferal` | 40-byte authorization/time packet, two TEA layers with per-challenge derived key; FFC3 writes in 20-byte chunks. |
| What success means | `service/BleService.java`, `sendMsgToPeriferal`; `common/v.java`, receiver `d` | The central path reports completion after sends/disconnect, not verified physical opening. Optional FFD2 notifications are used for lock/battery information. |
| Sound path | `service/ElevatorPlayer.java`; `voice/encoder/VoicePlayer.java` | Separate native sound SDK with no recovered Java waveform encoder. Not ported. |

## Reconstruction choices, not observations

- Native SwiftUI iPhone app, Chinese UI, local favorite order and aliases.
- Account tokens and a generated installation identifier use Keychain (`WhenUnlockedThisDeviceOnly`). Door lists stay in memory. UI preferences are scoped by account in UserDefaults.
- Online refresh before every request; server clock anchored to monotonic uptime. No time-invalid or expired requests. No automatic background actions.
- Unsupported counted visitor keys are displayed but cannot open. Their backend accounting has not been ported.
- User-editable configuration does not contain protocol credentials, arbitrary device IDs, floors or authorization masks.
- Bluetooth response errors, disconnects, cancellation and missing characteristics abort the request. Write completion is labeled “request sent”, never “door unlocked”.

## Verification and limits

The decompiled `p1/g.java` TEA code and `o.java` methods `C`, `D`, `E`, `J`, `Y`, and hex parser `g` were compiled as a standalone Java oracle with Android constants substituted and time fixed to `1700000000`. All IDs, licenses and challenges are synthetic. Original methods/oracle are retained in `../yaoshibao-research/oracle/` on the development machine, including `vectors.txt`. Java Cipher generated the AES fixture. The Swift XCTest sources embed these independent expected outputs.

Verified here:

- Swift package builds with installed command-line Swift.
- All **10 test cases pass**, including Java-derived protocol vectors and intercepted API requests. No test contacted the vendor.
- Keychain, app model and CoreBluetooth implementation type-check against the installed macOS SDK.
- SwiftUI source type-checks against that SDK with a temporary adapter for iOS-only keyboard/content modifiers and EditButton. This is **not an iPhone SDK build or UI rendering test**.
- Xcode project and Info.plist syntax validate with `plutil`.

Unresolved requirements for a verified working iPhone app:

1. Build/sign using full Xcode and an iPhone SDK. Full Xcode and XCTest are absent here; no IPA is supplied.
2. Observe a successful login and refresh on the intended account. Server device binding, account switching behavior, optional nested collections, and iOS acceptance of the recovered Android-compatible requests remain unverified.
3. Test the intended controller. A matching Bluetooth family, advertisement visibility on iOS, firmware compatibility, write timing and actual unlocking remain unverified.
4. If the door is sound-only or requires FFE peripheral/server mode, implement that separate transport. Hardware type cannot be determined from an APK alone.

Checklist: artifact identity **answered**; static login/door selection/central packet path **answered within cited functions**; app with configurable favorites **implemented in source**; signed install and physical door opening **unresolved**; sound and other transports **not implemented**.

## Xcode installation and build update — 2026-11-03

Xcode 27.2 (27B52) was installed from Apple's Mac App Store. First-launch status is clear and iOS 27.2 SDK is present. The physical-device target compiled successfully with signing disabled. The simulator target compiled with normal ad-hoc simulator signing, installed, and launched on the iPhone 18 Pro / iOS 27.2 simulator. The initial unsigned simulator run reported Keychain OSStatus -34018; normal simulator signing resolved this without weakening storage. The login screen now shows its normal status and no storage error. No login/SMS or door request was submitted.

Full XCTest execution: 10 tests, 0 failures. The device and simulator build logs each end with BUILD SUCCEEDED. The only build warning was AppIntents metadata extraction being skipped because the app does not depend on AppIntents.

At the latest signing check there were no valid code-signing identities and no connected physical iPhone. Xcode's Apple Accounts page showed Sign In. Device installation and a signed IPA remain pending these user-controlled setup steps. Earlier notes about Xcode being absent describe the initial development environment, not the current one.

Account update: the Apple account subsequently signed in and its Personal Team loaded. That team is selected in the project. Xcode reports 0 provisioned physical devices, so a device-signed build/IPA is still pending connection and trust of the intended iPhone.

## Device build and installation update — 2026-11-03

Developer Mode was enabled on the paired iPhone 17 Pro Max. Xcode signed the device build using the available Apple Development identity. The build succeeded, codesign strict verification passed, and the embedded profile was checked to include the intended device. `devicectl device install app` reported successful installation of `local.keypocket.iphone`. The signed IPA was created at `../KeyPocket-iPhone.ipa`; ZIP integrity passed. Provisioning expiration: 2026-11-10T00:40:52Z.

The initial launch command was denied by iOS with a security/profile trust error; the phone owner was asked to explicitly trust the Developer App profile. No login or physical opening was attempted.

## Login regression fix — version 1.0.1 / build 2

The user's real login received a successful auth response without a top-level key collection. The previous implementation incorrectly ran that auth response through the key-synchronization parser, producing “响应没有钥匙列表” and rejecting an otherwise valid login. This was an implementation assumption, not an established service requirement.

Rechecked static sources: LoginActivity.D accepts code 100, saves the token and opens MainMenuActivity; HomeFragment and MoreKeysActivity invoke NetUtils.R0 (renew02) for synchronization. KeysActivity.initData treats absent owner_keys and gate_keys as empty collections.

The auth API now returns an Account session independently of key data or server time. AppModel persists that session and explicitly calls renew02. Non-session sync errors preserve the successful login and show a retry message. Missing collections in a successful sync produce an empty current snapshot and never reuse stale permissions. A missing session token is still rejected.

Added regression tests for a session-only auth response followed by a populated renew02 response, missing-token rejection, and missing-collection empty snapshots. All 12 XCTest cases pass, and the signed iPhone build succeeds. No user credentials were read and no live SMS/login/opening requests were made during this fix. The fix still needs a real-account retest on the phone.

## Version 1.1 / build 3 — sound and reliability

Supersedes the earlier sound-not-implemented boundary for key types 0, 3 and 100. Sound protocol, controlled native replay, audio route safeguards, BLE retry boundaries, test results and remaining hardware unknowns are documented in SOUND_AND_RELIABILITY.md. The original official iOS app has not been analyzed, so Android source observations remain separate from hypotheses about the user's reported iPhone behavior.
