# Hidden playback and default login startup

The user explicitly requires ordinary menu Quit and Command-Q to remove management and its menu-bar icon while continuing wallpapers. Reopen the installed app to manage wallpapers or use Settings to stop wallpapers and completely exit. Default login startup should play wallpapers in the background.

Builder decisions:
- Management owns the existing status item. Player never creates one; keep its accessory activation policy so frame-save errors can still present native alerts on explicit complete exit.
- Use SMAppService.mainApp for login startup. Identify login launch using the documented open-application Apple event keyAEPropData/keyAELaunchedAsLogInItem; launch/reuse the player using the existing startupTask, then exit management without showing window or icon. Manual reopen during startup switches to ordinary management. Failed playback startup shows management with an actionable error.
- On the first launch of this version, enable login startup by default; persist a one-time configuration marker in management UserDefaults. Explicit user disable or external system disable must remain respected on subsequent launches. Failed initial registration remains retryable; pending approval is displayed and not repeatedly registered.
- Reuse existing main-app login registration; disabling it does not kill currently playing wallpapers. Surface errors; do not bypass macOS approval.
- Preserve media, state/workshop files, current static-frame exit behavior and user detail navigation. Keep macOS14+, Swift5 language mode, no external dependencies. Version0.9.2/build21. Do not change GitHub releases for this local request.
