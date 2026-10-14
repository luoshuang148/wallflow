# Independent background playback

The user explicitly wants Command-Q to exit the management program while wallpapers continue playing, plus “停止壁纸并完全退出” in Settings. Implement this with a genuinely separate process.

## User behavior

- Main window Close hides management; Command-Q terminates the manager process and its previews/download work, while the background process and its current desktop players continue uninterrupted.
- The background process owns the existing menu-bar entry. “管理壁纸…” launches/raises the manager. Pause/resume remains usable without the manager.
- Settings provides “停止壁纸并完全退出”. This stops pending playback/playlist operations, captures the currently applied frames using existing static-wallpaper behavior, ends the background process, then terminates the manager. A matching menu-bar complete-exit item is available when only the background process remains.
- Reopening management connects to the existing player, preserves playback positions and audio ownership, and does not create duplicate desktop windows or a second menu-bar icon.
- Existing assignments, audio, manual pause, playlist, power/app rules, media references, Steam sessions, concise Chinese UI, and approved icon remain compatible. Full quit keeps the existing Space/static-frame limitations.
- Login startup remains the existing opt-in `SMAppService.mainApp` registration; do not silently enable or change the user's login registration. Launching the manager starts/reuses the helper.

## Architecture

- Embed `WallFlowPlayer.app` under `Contents/Library/LoginItems`, with bundle ID `local.zongzihao.VideoWallpaper.Player`. Build/sign it before the containing app. The existing main bundle/module/data identity remains unchanged.
- Only the helper owns desktop playback, application/power/system monitoring, rotation and the menu-bar item. The management LibraryModel validates/imports media and edits settings but never prepares desktop sessions; its silent UI preview stays independent.
- Keep legacy standalone LibraryModel behavior as the default for existing tests; add explicit management/player modes for the shipped app.
- Both models use a coordinated state store: serialize read/merge/write with a same-user file lock; merge changes against each model's base snapshot, preserve unrelated current fields, and reject conflicting concurrent edits instead of overwriting newer settings. The persisted AppState schema stays unchanged.
- Local notifications plus a periodic fallback reload shared state; do not restart a matching desktop player when management opens, closes, or changes a nonplayback setting. The helper reloads policies and only prepares changed media/assignments.
- Private runtime files hold a singleton lease, a session-bound complete-quit command, and lightweight player status (PID/session/phase/display status/time/rate). Only process metadata and playback state are stored; no credentials. Create runtime files with same-user permissions.
- Use a held nonblocking lock for single helper ownership; never trust a stale PID alone. Quit commands carry the current helper session and are ignored by a new session. Manager checks readiness and waits for complete exit; connection/shutdown failures are visible rather than faking success.
- Helpers launched from old application copies must be detected; an incompatible helper reports that full exit is required before update/relaunch. App updates must completely stop the helper before replacing its executable bundle.

## Validation

Tests must prove coordinated independent edits, conflict rejection, optional-field deletion, singleton lease lifetime, stale-session quit rejection, manager models never creating desktop sessions, helper reload/policy behavior, and closing management not stopping helper playback. Existing tests retain standalone behavior. Package verification checks both executable architectures, versions and nested signatures. Actual process verification checks manager gone, helper still alive and advancing video time after Command-Q; reopening retains helper PID and playing session; complete exit leaves neither process alive. Do not write real user state in unit tests or claim unexercised login/multi-screen environments.

Implementation details such as file names, polling intervals, test injection shapes and staging paths are builder choices. Use Swift 6 tooling/Swift 5 language mode, macOS14+, no new external dependency. Version this development change as0.9.0/build19; do not replace published GitHub tags/assets in this task.
