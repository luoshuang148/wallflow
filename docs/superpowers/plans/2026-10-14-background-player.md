# Background Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Command-Q exits management while an independent player continues; Settings can stop both processes completely.

**Architecture:** A packaged helper is the sole desktop playback owner. Coordinated shared-state edits, a singleton lease, private session commands and status connect the management model to it without duplicating AVPlayers or resetting user preferences.

**Tech Stack:** Swift6/Swift5 mode, AppKit, SwiftUI, AVFoundation, Foundation, POSIX file locks, XCTest, macOS14+.

**Spec:** `docs/superpowers/specs/2026-10-14-background-player-design.md`

## Global Constraints

- Management Command-Q must actually terminate its process; background desktop playback continues.
- Existing AppState schema, bundle/data identity, audio/power/app policies and approved logo remain compatible.
- Singleton helper, current-session shutdown commands, coordinated state writes, no external dependency or credential transfer.
- Complete exit preserves existing static-frame/Space behavior; login registration remains opt-in and unchanged.

## Review Focus

- A stale manager/playlist write must not lose unrelated newer state or silently overwrite a concurrent assignment.
- Management launch/quit must not install a second desktop player or mute/resume the existing one.
- Stale PID/status/quit files or two simultaneous launches must not produce duplicate helpers or stop a new session.
- Helper failure, startup timeout, blocked persistence or full-exit failure must not be reported as successful playback/exit.
- Full exit during media preparation/import/rotation must invalidate late work before installing static frames or terminating.

### Task 1: Coordinated state and explicit playback ownership

**Files:** Create `Sources/WallpaperCore/SharedStateStore.swift`; modify `Sources/WallpaperRuntime/LibraryModel.swift`; create core/runtime background-state tests.

**Interfaces:** `SharedStateStore.saveChanges(base:next:to:) -> AppState`; `LibraryModel.Mode` standalone/management/player; `reloadSharedState()`; external playback status; default standalone behavior unchanged.

- [ ] Write tests for independent mute/assignment edits, nested setting merge, conflicting writes, deletion, and management restore/apply/policy paths never creating desktop sessions.
- [ ] Run targeted tests and observe RED for missing interfaces.
- [ ] Implement locked three-way state merge and manager/player roles; add efficient external reload without overwriting newer state or revalidating unchanged media.
- [ ] Run targeted tests and existing media/exit/playlist regressions; expected zero failures; commit.

### Task 2: Helper protocol, lifecycle and signed bundle

**Files:** Create `BackgroundPlayer.swift` runtime controller/protocol, `DesktopPlaybackHost.swift`, `Sources/WallFlowPlayer/App.swift`, `Resources/PlayerInfo.plist`; modify Package.swift/build.sh; add helper protocol tests.

**Interfaces:** Shared runtime paths, held singleton lease, session-bound command/status, `BackgroundPlayerController.ensureRunning()/stopAndWait()`, playback host lifecycle/telemetry, parent app reopening.

- [ ] Write tests for duplicate lease exclusion/release, stale-session commands, status ownership/compatibility, startup/shutdown failures, and shared-state refresh.
- [ ] Run targeted tests and observe RED.
- [ ] Implement protocol, background host with existing monitors/rotation/menu behavior, controller and helper entry; package/sign nested helper before main.
- [ ] Run targeted tests/full suite and release build; expected zero new failures and valid nested signatures; commit.

### Task 3: Management/Settings integration and live process proof

**Files:** Modify management App.swift, LibraryView/SettingsView, version/docs; add lifecycle regression/integration tests where appropriate.

**Interfaces:** Manager uses management LibraryModel and controller; Settings exposes complete exit; helper provides persistent menu entry; manager observes helper status and complete-exit events.

- [ ] Write behavior tests for management shutdown preserving playback ownership and complete-exit state gates; observe RED before new behavior.
- [ ] Connect management launch/quit/reopen and Settings action; bump0.9.0/build19 and document update/full-exit behavior.
- [ ] Run full tests, build both apps and verify nested signatures/version/icon; obtain a fresh independent review and fix important findings with regression coverage.
- [ ] Normally quit current0.8.0, deploy staged0.9.0, verify helper PID/session/time across management Command-Q/reopen, then verify complete exit leaves no process. Preserve user data and relaunch the usable app.
- [ ] Commit verified work on codex/background-player; update private handoff with source/deployment/testing boundaries. Do not publish/merge remote release assets.
