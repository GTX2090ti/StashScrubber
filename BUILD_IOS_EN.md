# StashScrubber iOS Build Guide

This project is the cross-platform Flutter source (iOS / HarmonyOS) of StashScrubber.
Below are the steps to build the iOS version on a Mac.

## 1. Prerequisites (on macOS)

- macOS 13+ (Ventura or later)
- Xcode 15+ (from App Store; accept the license and install command-line tools on first run)
- Flutter SDK (≥ 3.24; this project requires Dart ^3.9.2)
  - Install: `git clone -b stable https://github.com/flutter/flutter.git ~/flutter`, add `~/flutter/bin` to PATH, then run `flutter doctor`
- CocoaPods: `sudo gem install cocoapods` (or `brew install cocoapods`)
- An Apple ID (required for running on a real device; a paid developer account ($99/yr) is required for App Store release)

## 2. One-time environment check

```bash
flutter doctor
```
Confirm that `Xcode`, `CocoaPods`, and `Connected device` (with your iPhone connected) are all green.

## 3. Fetch dependencies

```bash
cd stash_scrubber_ios
flutter pub get
cd ios && pod install && cd ..
```

## 4. Build for a real device (recommended first run)

```bash
# Connect your iPhone and tap "Trust" on the phone when prompted
flutter build ios --release --no-codesign
```
This produces `build/ios/iphoneos/*.app` (unsigned; verifies the build compiles).

Sign and install with a personal Apple ID (free signing, valid 7 days):
```bash
flutter build ios --release
flutter install
```
Or open Xcode:
```bash
open ios/Runner.xcworkspace
```
In Xcode: Signing & Capabilities → Team: select your Apple ID → change the Bundle
Identifier if needed (currently `com.gtx2090ti.stashscrubber`; free accounts usually
need a unique one like `com.<yourid>.stashscrubber`) → select your iPhone → Run.

## 5. Version number

Sync in one place:
- `pubspec.yaml` → `version: 1.6.57+567` (first part = CFBundleShortVersionString, second = CFBundleVersion)
- The iOS build reads the version from pubspec automatically; no manual Info.plist edit needed.

## 6. App icon

Icons live in `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (currently a generated
StashScrubber "SS" icon). To replace: overwrite `Icon-App-1024x1024@1x.png` with your
1024×1024 PNG and let Xcode regenerate, or drag each size into the AppIcon editor in Xcode.

## 7. Network permissions (already configured)

`ios/Runner/Info.plist` includes:
- `NSAppTransportSecurity → NSAllowsArbitraryLoads = true`: allows HTTP LAN servers
  (e.g. `http://192.168.2.180:9999`) and self-signed HTTPS servers
- `NSLocalNetworkUsageDescription`: required by iOS 14+ to access the LAN (internal
  Stash server); approve the prompt on first connection

## 8. Troubleshooting

- `pod install` fails: update CocoaPods (`sudo gem update cocoapods`) or clear cache (`pod cache clean --all`)
- "Unable to launch" on device: trust the developer certificate in
  Settings → General → VPN & Device Management
- Free signing expires after 7 days: rebuild and reinstall (`flutter build ios`)
- Cannot reach the LAN server: make sure the iPhone and the Stash server are on the
  same network, and allow the "Local Network" permission on first connection

## 9. App Store release

Requires a paid developer account. Run `flutter build ipa`, then upload via Xcode
Organizer / Transporter (Archive → Upload).
