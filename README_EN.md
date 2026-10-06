# StashScrubber (HarmonyOS)

A native HarmonyOS NEXT client (Flutter) for the [Stash](https://github.com/stashapp/stash) media manager, compatible with **Stash 0.31.x**.

[中文说明](README.md) | [Download Releases](https://github.com/GTX2090ti/StashScrubber-Harmony/releases)

---

## Features

### Scenes
- Two-column grid cards: cover, duration, resolution, favorite star, **subtitle badge** (shown when external captions are detected)
- Infinite scroll with position restore on back; no paging buttons
- Combined search: title / path / details + performer name + tag + studio
- Sort: date added / date modified / title / file size / duration / rating / studio, etc. (0.31.1 enums)
- Filters: rating / date / duration / organized / studio / performer / tag (multi-select + search)
- Batch actions: favorite, rating, tags, **merge**, **generate covers**, select all
- Detail page: cover, info, links to performers / studio / tags, edit, scrape, generate cover, favorite
- **File section**: full path on its own line with size / duration / modified time; multi-file blocks; set default file

### Performers · Studios · Tags
- Grid/list cards + infinite scroll + search + **sort**
- Performer detail: basic info, **aliases** (5 shown by default, expandable), related scenes
- **Performer merge**: from the detail page, multi-select source performers and merge into the current one — resolves duplicates / name clashes
- **Add** (list page) / **Delete** (detail page, with confirmation)
- Edit: basic fields, tags (multi-select + search), dedupe on create

### Scraping
- Three modes: fragment / name / URL scraping
- Sources: local scrapers + **Stash-box** (StashDB etc.); fragment mode auto-queries box using the local performer name
- Preview: name / aliases / birthdate / country / measurements / career / tags + image, "Apply & write back" on top
- Keeps the original performer name by default; write-back compatible with 0.31.1 (`height_cm` / `alias_list` / `performer_input`)
- **Friendly Chinese error messages** (404 / timeout / not implemented / site fetch failure)
- **Name-clash protection on write-back**: if another performer already has the same name, the name field is skipped and the rest are saved

### Scan · Jobs · Generate
- Scan: all or **selected sub-folders**; optional cover / preview / sprite / phash generation
- Live Stash job queue: scan / generate / clean task progress
- **Generate covers**: single (detail page) / batch (multi-select) / global (tasks page) — 0.31.1 `metadataGenerate` + `sceneIDs`

### Search & Input
- **Clear button** on every search bar (scenes / performers / studios / tags / filters / merge / jobs / scrape)
- **Auto date dashes**: type 20261003 → automatically formatted as 2026-10-03

### Servers & Settings
- Multiple server profiles: LAN / WAN address + API key, auto routing by latency
- Server-related settings grouped under a sub-menu
- Diagnostics: profile / routing / latency / Stash version

---

## Install

- Unsigned HAP: `hdc install -r StashScrubber-Flutter-vX.Y.Z-unsigned.hap`
  (or install via DevEco Studio with your debug signing profile)
- Requires HarmonyOS NEXT (API 18+)

## Download

Releases: <https://github.com/GTX2090ti/StashScrubber-Harmony/releases>

## Development

```bash
flutter pub get        # fetch dependencies
flutter analyze        # static analysis
cd ohos && hvigorw assembleHap -p product=default -p buildMode=release   # build HAP
```

## Changelog

- **v1.6.57**: Performer merge (⧉ button on detail page — multi-select source performers, merge into the current one; resolves duplicates / name clashes); name-clash protection on write-back (UNIQUE conflict → skip the name, save the rest)
- **v1.6.55**: Friendly Chinese scrape errors (404 / timeout / not implemented / site fetch failure); auto date dashes (YYYY-MM-DD); file-section divider
- **v1.6.52**: Performer fragment scraping fixed (0.31.1 returns not implemented for performer_id → now sends performer_input)
- **v1.6.51**: Clear button on every search bar (scenes / performers / studios / tags / filters / merge / jobs / scrape)
- **v1.6.50**: Simplified Chinese terminology (phash / sprite / preview); generate-cover query field fix (interactiveHeatmaps)
- **v1.6.48**: Sort for performer / studio main lists; sort for related scenes; scene detail file section (full path wrapping, size / duration / modified time, multi-file blocks, set default file)
- **v1.6.46**: Generate covers for scenes (detail + batch); Stash-box fragment scraping (uses local performer name); keep original performer name on scrape by default; performer aliases on detail (5 shown, expandable); subtitle badge on scene covers; add/delete performers & studios; fix performer detail 422 (`Performer.alias_list`)
- Earlier: bottom navigation, infinite scroll, paging removed, favorites, 0.31.1 sort enums, scrape write-back field compatibility, Chinese-localized copy & paste

> Note: Starting from v1.6.46 this repository hosts the full Flutter source code; the earlier ArkTS version remains in git history (tag v1.6.1 and before).
