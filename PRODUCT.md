# Kadrin

<!-- impeccable:product-schema 1 -->

## Platform
macOS — native AppKit desktop application. The skill's web/iOS/Android taxonomy does not cover this platform; do not reinterpret it as a web or mobile application.

## Users
The owner of this Mac, taking frequent screenshots for everyday communication. Personal local use first.

## Product Purpose
Capture an area or entire display, annotate it and copy or save without leaving the current Space or fullscreen application.

## Capabilities and Constraints
Swift/AppKit, ScreenCaptureKit, Apple Silicon, macOS 26+. Russian UI. Region capture on any single display; full-display capture under the pointer. Editable annotations, rectangular blur, opaque concealment, undo/redo, native PNG save and clipboard. Configurable global shortcuts, optional login launch. No cloud, OCR, video, account or persistent screenshot history.

## Brand Commitments
Kadrin («Кадрин»), from кадр/frame. The user approved the flat two-frame mark in assets/branding/frames-icon-v6.png. The brand icon is flat with solid blue/navy forms; fire, glass and sculptural effects were rejected for the logo. This does not change the native editor material.

The user's current request supersedes the earlier Flameshot-like purple appearance: use native Apple/macOS design. Preserve the agreed capture workflow, tools, screen-local coordinates and nonactivating window behavior.

## Evidence on Hand
Runnable build/Kadrin.app. Tests and docs/TESTING.md record tested behavior. build/qa-region.png was produced by the real app; /tmp/screenshot-editor-preview.png is an isolated AppKit render of the original toolbar.

## Product Principles
- The screenshot is primary; controls should stay out of its way.
- Native behavior and fast direct manipulation matter more than decorative expression.
- Local processing; permission and failure states must be understandable.
- Preserve working capture/export behavior during visual changes.
