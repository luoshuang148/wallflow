# Hidden playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Quit management and menu icon together, retain playback, and default to background playback at login.
**Architecture:** Management owns menu UI; standalone player owns desktop playback. A system login event starts/reuses the player through the existing management startupTask, then exits without management UI.
**Tech Stack:** SwiftPM, AppKit, ServiceManagement, macOS14+.
**Spec:** docs/superpowers/specs/2026-10-14-hidden-player-design.md

## Global Constraints
- Swift5 language mode, macOS14+, no external dependencies.
- Preserve user state, workshop config, media, approved icon and detail navigation.
- Version0.9.2/build21; no GitHub release changes.

## Review Focus
- Startup failure/approval: show real status; retry failed default once on later launch.
- User opt-out/system disable: no default re-registration on reopen.
- Startup and manual launch races: reuse the player's existing lease; manual reopen must present management and prevent automatic manager quit.
- Complete exit: login bootstrap uses the same startupTask awaited by complete exit; no independent delayed launcher.
- Updating a registered login service: stop active playback normally and preserve registration/data.

## Task1: Login launch policy
Files: SystemIntegration.swift, SystemIntegrationTests.swift, ManagementLaunchPolicy.swift, ManagementLaunchTests.swift, VideoWallpaperApp/App.swift.
- [x] Write and run RED tests for default enable, saved opt-out, pending approval and failed registration retry, with isolated UserDefaults and simulated OS service.
- [x] Implement minimal policy; retain mainApp registration; classify login vs manual launch using real Apple event descriptors; no independent registration-launch task.
- [x] Run focused GREEN tests; build/sign player and manager; inspect real registration after install.

## Task2: Management owns status menu
Files: VideoWallpaperApp/App.swift, WallFlowPlayer/App.swift, DesktopPlaybackHost.swift, BackgroundPlayer.swift, obsolete menu-notification tests, README files, CHANGELOG, Settings copy.
- [x] Move menu ownership to management, delete obsolete cross-process ordinary-quit route; keep player stop IPC unchanged.
- [x] Update user-facing docs/settings; run default suite and packaged-player process integration.
- [x] Read-only code review and resolve blockers before merging local main.
- [x] Normally stop installed0.9.1, backup/deploy0.9.2, verify ordinary exit leaves only active player/no management icon; reopen reuses player; Settings full exit stops all processes.
- [x] Verify login registration, data byte equality; synchronize primary source and installed copies, update handoff.
