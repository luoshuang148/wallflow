# Workshop Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Browse the official Workshop inside WallFlow and download an eligible video directly from its details page.

**Architecture:** A dedicated `WorkshopBrowser` owns a WKWebView and cancellable, generation-guarded metadata lookup. A new SwiftUI sheet presents it; `WorkshopModel` accepts an explicit ID and reuses the existing validated download/import pipeline.

**Tech Stack:** Swift 6 toolchain, Swift 5 mode, SwiftUI, AppKit, WebKit, XCTest, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-14-workshop-browser-design.md`

## Global Constraints

- Chinese concise UI; video-only downloads; Wallpaper Engine app ID `431960`.
- Shared persistent `.default()` web storage; independent SteamCMD session; no new dependencies/API key.
- Preserve approved logo, real user data, existing workflows, and published version tags/assets.

## Review Focus

- Stale detail metadata after navigation must never enable the wrong item's download.
- Wrong app, Scene, missing metadata, or mismatched returned ID must not reach SteamCMD.
- Closing/canceling while a lookup ignores cancellation must not publish its late result.
- Manual link input and existing busy operation must not be overwritten by browser actions.
- Loading errors and nonofficial/new-window/custom-scheme navigation must leave an accurate disabled state.

### Task 1: Embedded browsing and direct download

**Files:**
- Create: `Sources/WallpaperRuntime/WorkshopBrowser.swift`
- Create: `Sources/VideoWallpaperApp/WorkshopBrowserView.swift`
- Modify: `Sources/VideoWallpaperApp/WorkshopView.swift`
- Modify: `Sources/WallpaperRuntime/WorkshopModel.swift`
- Test: `Tests/WallpaperRuntimeTests/WorkshopBrowserTests.swift`
- Modify: `Resources/Info.plist`, `README.md`, `README.en.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `WorkshopID`, `WorkshopItem.isVideo`, `SubscriptionBrowser.isOfficial(_:)`, `WorkshopModel.fetchItems(_:)`, current busy/progress/import API.
- Produces: `WorkshopBrowser` with `webView`, navigation/loading/current-item state, `goHome()`, `goBack()`, `goForward()`, `reload()`, `close()`, internal testable `inspectPage(at:)`; `WorkshopModel.downloadItem(_ id: WorkshopID)` and an injectable metadata loader.

- [x] Write focused tests for valid/invalid detail selection, shared web storage, asynchronous stale results, close/navigation cancellation, metadata failures and mismatched IDs, captured ID download validation, busy gating, and manual input preservation.
- [x] Run `swift test --filter WorkshopBrowserTests` and confirm failure because new interfaces do not exist.
- [x] Implement browser lifecycle and metadata validation, explicit-ID download route, and the embedded sheet with navigation, status, download, and cancel controls.
- [x] Run focused tests; expected: 0 failures. Run full `swift test`; expected: no new failures, report skips.
- [x] Update local app version to 0.8.0/build 17 and docs describing browsing and independent sessions; retain published 0.7.1 download links. Add an Unreleased changelog entry.
- [x] Run `./build.sh` using a clean staged output, verify signature and approved icon; inspect UI/public browsing, navigation, and eligible video button. Do not claim a live account download without exercising it.
- [x] Obtain a fresh read-only review, resolve important findings with regression tests, commit the verified feature on `codex/workshop-browser`.
- [x] Normally quit the running local app, deploy the staged app, relaunch and compare user settings. Do not push/merge or replace published Release assets in this feature task.

Runtime verification: Native UI automation failed with the pre-existing Sky pipe crash on WorkshopView; app process stayed alive. Public WebKit browse/details integration passed after adapting the test to Steam's current page structure. Actual account download was not performed.
