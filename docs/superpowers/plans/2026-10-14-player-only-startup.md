# Player-only startup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** System login starts WallFlowPlayer directly.
**Architecture:** Player-owned mainApp login registration is controlled through a bounded CLI; manager migrates its old registration.
**Tech Stack:** SwiftPM/AppKit/ServiceManagement, macOS14+.
**Spec:** docs/superpowers/specs/2026-10-14-player-only-startup-design.md

## Global Constraints
- Preserve data, default enable/saved disable, silent playback, no icon after ordinary quit.
- No third executable or external dependencies; version0.9.3/build22.
- Keep manager-to-player complete-exit identity/session gate.

## Review Focus
- A control query must not claim the playback lease/start UI or kill active playback.
- Legacy migration failures preserve a working login item and remain retryable.
- Old default marker must not skip migration; saved off state must remain off.
- System registration must identify the nested player executable rather than management.
- CLI errors/timeouts must be visible; management reopening/full exit still use existing background session.

## Task1: Player registration boundary
- [x] RED migration-policy tests and actual packaged control query test; implement smallest CLI/service adapter and migration wrapper; focused GREEN.
- [x] Build/sign, normally stop old app, backup/deploy new app; inspect pre-migration player status versus legacy registration.
- [x] Verify real OS record points at player; toggle off/on while playing without killing the player; direct cold launch creates no manager.
- [x] Run default suite and packaged-helper process checks; read-only code review, fix blockers.
- [x] Commit and sync local main/installed copies; private handoff records native evidence and limits.
