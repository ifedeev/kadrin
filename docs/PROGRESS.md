# Screenshot implementation

Approved specification: the user-provided plan in this chat (2026-10-30).

- 1: Nonactivating overlay prototype: confirmed by user in ordinary and fullscreen Spaces. Actual region capture/edit/save verified after permission; full-display capture and copy action verified.
- 2: Selection/session geometry: implemented and tested.
- 3: Annotation editor: implemented; model and isolated AppKit interaction tests pass.
- 4: Export/settings: implemented; PNG tests and settings layout verified; live save/cancel sheet verified; login approval remains a manual check.
- 5: Local arm64 .app built and ad-hoc signature verified; remaining device checks listed in TESTING.md.

Ruling: This directory is empty and is not a Git repository; implement in the explicitly supplied workspace, without worktree machinery or unsolicited commits.
Ruling: Swift Package Manager plus a bundle script avoids a generated Xcode project and third-party project tools. The package can be opened in Xcode.

Prototype: debug tests and release bundle built successfully. Session gate test observed RED (3 failed assertions) then GREEN.
Prototype UI: user confirmed text entry without a Space switch. Fullscreen confirmation pending; computer-use API returned SCStreamError -3812 for Finder.
Settings implemented while waiting on the required fullscreen gate; annotation editor not started yet.

Fullscreen gate: user confirmed text input and Esc work without Space switching. Implemented editor on unchanged NSPanel behavior after this confirmation.
Core: tests first failed with 13 behavioral assertions, then 6 tests passed after implementation (2026-10-30).
Capture/editor/settings/export are integrated. Release bundle built. Live screen permission requested from user for end-to-end verification.
Whole implementation read-only review dispatched; drag interruption bug flagged, fix pending.

Final review: two actionable findings reproduced by AppKit tests, then fixed. Undo-during-drag produced an index-out-of-range crash before the fix; text-entry extent was 840 on an 800-point canvas before the fix. Both now pass.
Additional regression: line hit-testing no longer selects empty corners of a diagonal line’s bounding box.
Shortcut recorder now accepts an already-registered app shortcut through the Carbon callback, so conflicts do not accidentally start a capture; failed registration retains its previous value. Tested successful and failed acceptance.
Final review rulings: save/error sheet focus, actual capture pixels, mixed displays and login approval cannot be established by source review or the isolated tests. Keep these as explicit pending live checks, not speculative code defects or claimed successes.
No deferred source-review findings. Documentation progress corrected.

2026-10-30 live QA: user enabled Screen Recording. Region capture, arrow, Russian text, selection resize, save-panel cancellation, Cmd-S and PNG write verified through native UI. Export build/qa-region.png inspected at 1470×730, correct orientation/content and no editor chrome. Full-display capture showed 3024×1964; Cmd-C closed the editor following successful pasteboard write. Preview paste verification blocked by computer-use SCStreamError -3811; physical global shortcuts, final editor fullscreen save, mixed displays and login still explicitly unverified. No source code changed during this QA pass; prior 12-test/release/signature results remain applicable.

2026-10-30 branding: user approved flat two-frame mark frames-icon-v6.png. App renamed Kadrin in user-facing labels and bundle display name, stable identifier/module names retained. ICNS and monochrome menu-bar template integrated; settings displays bundle icon. 16 tests pass; release/signature/plist verified. Live Kadrin settings checked; user's custom shortcuts retained, enabled login registration migrated through UI. Current release needs renewed Screen Recording permission after ad-hoc signing.

2026-10-30 blur: rectangular Gaussian blur implemented with native Core Image, screen-scaled radius, source cache and shared preview/export composition. Existing annotation transforms/history reused; concealment remains last. Toolbar fits all11tools at640pt. 21 tests pass with graphics access; scoped source/render review accepted. Release3 signed and installed in /Applications with rollback ZIP retained.
