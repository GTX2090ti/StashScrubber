# StashScrubber (iOS)

An **iOS client (Flutter)** for the [Stash](https://github.com/stashapp/stash) media manager, compatible with **Stash 0.31.x**. Ported from the HarmonyOS Flutter version (StashScrubber-Harmony), feature-synced to v1.6.64.

> The original SwiftUI native iOS app (v1.6.0) is archived on branch `backup/native-ios-1.6.0`.

[中文说明](README.md) | [iOS 构建说明（中文）](BUILD_IOS_ZH.md) | [iOS Build Guide (EN)](BUILD_IOS_EN.md)

---

## Features

### Scenes
- Two-column grid cards: cover, duration, resolution, favorite star, **subtitle badge** (shown when external captions are detected)
- Infinite scroll with position restore on back; no paging buttons
- Combined search: title / path / details + performer name + tag + studio
- Sort (date newest-first, etc.) + filters (studio/performer/tag with search & multi-select) + batch actions (favorite / rating / tags / merge / generate covers)
- Detail: scrape (**keeps existing studio**), edit, favorite, merge, generate cover, copy file path, performer/studio links
- **Favorites page with 3 tabs**: Scenes (organized) / Performers (starred) / Studios (starred)

### Performers
- Grid cards + infinite scroll + search; detail shows aliases (default 5, expandable), merge, delete, **favorite star**
- Scrape (Stash-box / JavDB etc., keeps original name by default), edit, manual create

### Studios
- Grid cards + infinite scroll + search; detail shows **parent / child studios** (navigable), **favorite star**, delete
- Scrape, edit, manual create

### Tags
- Browse all tags + scenes per tag; related scenes on detail

### Servers
- Multi-profile (LAN / WAN, path prefix support) + one-tap switch + server settings in a submenu
- API Key auth, connection test, network log, diagnostics

### Scan / Tasks
- Selective folder scanning (scenes + images), live task list, cleanup tasks

### Other
- 3-mode theme (system / light / dark), generate covers, subtitle detection

## Build

Requires macOS + Xcode 15+, see [BUILD_IOS_EN.md](BUILD_IOS_EN.md). CI uses CodeMagic (`codemagic.yaml`) — pushing `main` auto-builds an unsigned IPA.

## Server config

1. Add a profile in **Settings**:
   - LAN: `http://<NAS-IP>:9999`
   - WAN: `https://stash.example.com` (path prefix supported; `/graphql` is appended automatically)
2. If Stash uses an API Key, fill it in for the profile.
3. Tap **Test connection**, then switch LAN/WAN profiles from any list page.
