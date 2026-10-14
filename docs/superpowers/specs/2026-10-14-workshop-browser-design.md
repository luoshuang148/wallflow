# Embedded Workshop browsing

The user selected an embedded official Steam Workshop page with search, filters, sorting, details, and a WallFlow download button. Implement that selection directly in the existing Chinese app.

- Add “浏览工坊…” alongside existing subscription/local-import actions. Open a large embedded browser sheet with Back, Forward, Reload, Workshop Home, and Close.
- Use `WKWebsiteDataStore.default()` to reuse the current subscription browser's Steam web login. SteamCMD remains the separate download session; never copy cookies, credentials, or tokens between them.
- Start at Wallpaper Engine's official Workshop browse page, filtered to Video. Users can change official filters and navigate details; “all” means content Steam makes visible to the logged-in account, not deleted/private/inaccessible works.
- On a valid official details URL, obtain metadata through the existing item lookup. Enable “下载此作品” only for a successful `431960` Video item and while neither import nor download is busy. Show the current title, unsupported state, lookup errors, and existing task progress/cancellation concisely.
- Invoke the existing validated SteamCMD download/conversion/import pipeline using a captured `WorkshopID`, without modifying the manual link field or applying a wallpaper automatically. Recheck metadata when download starts.
- Navigation away, reload, rapid item switches, closing the browser, or canceling metadata lookup invalidates old results immediately. Reject malformed IDs, wrong applications/types, unexpected metadata IDs, HTTP, lookalike domains, custom schemes, credentials, and nondefault ports. Only existing official Steam navigation hosts are allowed.
- Preserve the current video-only playback scope, user library/settings/media, old subscription/import entry points, and the newly approved logo. No API key or external Swift dependency.
- Tests cover strict URL selection, stale and canceled lookups, errors/wrong IDs/types, persistent shared web storage, captured download IDs, manual input preservation, and busy/cancellation gates. Real public-page browsing is checked separately; actual account downloads require a user-accessible work and valid SteamCMD session.

Implementation choices left to the builder: exact toolbar spacing and icons, lifecycle method names, testing injection shape, and local staging paths. Use the established Swift 6 toolchain / Swift 5 language mode and macOS 14 minimum.
