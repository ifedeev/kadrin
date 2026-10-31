---
name: Kadrin
description: Native macOS screenshot capture and annotation
typography:
  settings-title:
    fontFamily: "SF system (NSFont.systemFont)"
    fontSize: "22pt"
    fontWeight: 600
  capture-title:
    fontFamily: "SF system (NSFont.systemFont)"
    fontSize: "15pt"
    fontWeight: 600
  body:
    fontFamily: "SF system (NSFont.systemFont)"
    fontSize: "13pt"
    fontWeight: 400
  section-action:
    fontFamily: "SF system (NSFont.systemFont)"
    fontSize: "12pt"
    fontWeight: 600
  detail:
    fontFamily: "SF system (NSFont.systemFont)"
    fontSize: "11pt"
    fontWeight: 400
  context:
    fontFamily: "SF system (NSFont.systemFont)"
    fontSize: "11pt"
    fontWeight: 500
  dimensions:
    fontFamily: "SF system monospaced digits (NSFont.monospacedDigitSystemFont)"
    fontSize: "11pt"
    fontWeight: 500
  shortcut:
    fontFamily: "SF system monospaced (NSFont.monospacedSystemFont)"
    fontSize: "13pt"
    fontWeight: 500
rounded:
  editor-surface: "16pt"
  settings-group: "10pt"
  swatch-feedback: "7pt"
spacing:
  tool-gap: "1pt"
  export-gap: "4pt"
  group-gap: "4pt"
  context-gap: "10pt"
  panel-inset: "12pt"
  settings-group-inline: "14pt"
  settings-section-gap: "22pt"
  settings-inline: "24pt"
components:
  editor-surface:
    rounded: "{rounded.editor-surface}"
    padding: "10pt 12pt"
    width: "620pt"
    height: "90pt"
  button-copy:
    typography: "{typography.section-action}"
    width: "100pt"
    height: "32pt"
  button-icon:
    width: "30pt"
    height: "32pt"
  color-swatch:
    width: "26pt"
    height: "26pt"
  settings-group:
    rounded: "{rounded.settings-group}"
    padding: "12pt 14pt"
  shortcut-recorder:
    typography: "{typography.shortcut}"
    width: "164pt"
    height: "30pt"
---

# Design System: Kadrin

## Overview

**Creative North Star: "Native Apple/macOS"**

Kadrin follows the user-selected native Apple/macOS direction: compact, quiet controls with the captured image as the primary content. AppKit owns control rendering, system typography, inherited appearance and the regular glass material. The interface uses Russian labels and familiar SF Symbols.

This is a code-led record of the implemented macOS 26 design, not a translation of an approved visual comp. The former purple shell is superseded by native materials and semantic colors. Annotation pigments remain document content, separate from interface accent and text colors.

**Key Characteristics:**
- Native AppKit controls and regular glass.
- Compact contextual editing beside the selection.
- System typography, semantic colors and SF Symbols.
- Selection cues combine shape, state and color.

This specification uses AppKit logical points, not CSS pixels or CSS physical points. Frontmatter records observed dimensions and type roles; numeric font weights denote regular, medium and semibold. Dynamic native colors and control recipes live in `.impeccable/design.json` extensions because CSS color strings and HTML previews cannot faithfully encode them.

## Colors

The interface inherits the system appearance; semantic roles describe intent without pinning their resolved appearance to a hex value.

### Primary
- **System Accent** (`NSColor.controlAccentColor`): Copy button bezel, selected swatch ring, and selected annotation outline/handles.

### Neutral
- **Primary Label** (`NSColor.labelColor`): toolbar symbol tint; native labels retain their default system treatment.
- **Secondary Label** (`NSColor.secondaryLabelColor`): contextual labels, dimensions, instructions and settings detail.
- **Quiet Feedback** (`NSColor.quaternaryLabelColor`): swatch hover/press backing.
- **Separator** (`NSColor.separatorColor`): swatch circle outline; toolbar dividers are native `NSBox` separators.
- **Control Background** (`NSColor.controlBackgroundColor`): settings groups.
- **Text / Text Background** (`NSColor.textColor`, `NSColor.textBackgroundColor`): temporary annotation text entry. The stored annotation color is preserved for rendered output.

### Status and document content
- **Allowed / Attention** (`NSColor.systemGreen`, `NSColor.systemOrange`): permission status symbols paired with explicit status text.
- Capture shading is black at 45% opacity; the capture boundary and its handles are white. These fixed overlays belong to the captured-image canvas, not the interface theme.
- Annotation swatches are fixed document pigments: red, orange, yellow, green, blue, white and black. Their source values are defined in `EditorView.palette` and `RGBA.accent`; they are not a UI brand palette.

**The Semantic Color Rule.** Keep native interface roles dynamic; never substitute sampled appearance values as their source of truth.

## Typography

**Body Font:** the SF system font obtained through `NSFont.systemFont`.
**Label/Mono Font:** system monospaced digits for pixel dimensions; the system monospaced font for recorded shortcuts.

**Character:** compact and legible, with weight and native spacing providing hierarchy. No bundled display font, custom line-height system or letter-spacing scale is present.

### Hierarchy
- **Settings title:** `settings-title`.
- **Capture instruction title:** `capture-title`.
- **Settings row text:** `body`; permission status uses medium weight at the same size.
- **Section headings and Copy:** `section-action`.
- **Supporting instructions and popup labels:** `detail`; the capture hint detail uses the system regular font at 12 points.
- **Active tool name:** `context`.
- **Capture dimensions:** `dimensions`.
- **Shortcut recorder:** `shortcut`.

Annotation text uses a system medium font at its document size. Text/number size choices are 14, 18, 24, 32, 48 and 64 points; these belong to annotation content rather than interface hierarchy.

## Layout

The eleven-tool editor uses a single two-row floating panel adjacent to the selection. Its nominal dimensions are recorded by `editor-surface`; actual width is `min(620, displayWidth - 24)` logical points. It is horizontally centered on the selection and clamped within the display's 12-point inset. It prefers the area below the selection, then above, then the lower display inset when neither fits. The native AppKit coordinate system places its origin at the lower left.

The top row groups ten tools, undo/redo, and Copy/Save/Cancel with native separators. The second row contains active tool name, annotation colors, applicable thickness or text size, a selection instruction when no object is targeted, and pixel dimensions. Thickness appears for pen, line, arrow, rectangle, ellipse and marker; size appears for text and numbers. Hidden contextual controls collapse through `NSStackView` without changing panel height.

Before selection, a centered instruction surface replaces the toolbar. Settings use a 560 × 526-point titled window with aligned native rows under Сочетания клавиш, Основные and Запись экрана. The frontmatter spacing roles describe observed stack gaps and insets; there is no web breakpoint or page grid system.

## Elevation & Depth

`EditorSurface` is a native `NSGlassEffectView` with `.regular` style and a content view. AppKit owns its material composition and accessibility adaptation, including the system's handling of transparency and contrast preferences. No custom shadow, blur kernel, glass gradient, tint layer or motion timing is specified. Settings group depth comes from the semantic control background inside the native window.

The implementation delegates adaptation to the platform; that is not a claim that accessibility preferences have been visually tested. The live dark settings capture is `.impeccable/review/live-settings.png`. Offscreen editor/settings images are layout evidence only because they omit live compositor effects. The live dark toolbar was subsequently captured in `.impeccable/review/live-toolbar-dark.png` and received a scoped dark-appearance review sign-off. Live light appearance and full keyboard/fullscreen verification remain pending.

## Shapes

The glass surface and settings group radii are explicit frontmatter tokens. Native buttons retain their AppKit bezel shapes rather than adopting a project-wide button radius. Custom color swatches are circular, with an accent selection ring and checkmark; their hover backing and exterior focus mask use `swatch-feedback`. Canvas selection handles are small squares, and selected annotation bounds use a dashed accent outline. The screenshot remains rectangular.

## Components

### Blur tool

Размытие uses the native `drop.halffull` symbol. Drag a rectangular region; the selection tool can move, resize or delete it. Color, line width and font controls are hidden for blur. A fixed 12-point Gaussian radius scales to display pixels; image edges are clamped. Blur affects the source capture, underneath annotations and opaque concealment. The source blur is cached for interactive drawing. Tool gaps are 1 point and top-row group gaps 4 points to retain the 620-point panel width.

### Brand icon

The approved two-frame image (`assets/branding/frames-icon-v6.png`) is packaged into an ICNS family from 16 to 1024 pixels, without regenerating its artwork. The settings header uses the bundle icon at 56 points. The menu bar uses a 20 × 18 point monochrome template drawn with native paths, retaining a transparent gutter between the frames. macOS owns its light/dark tint.


### Buttons

Familiar native controls, with Copy visibly labeled as the primary action. Copy uses an `NSButton` push bezel and the system accent. Tool buttons use `.accessoryBar`, push-on/push-off state and SF Symbols. Undo/redo, Save and Cancel use `.accessoryBarAction`; history availability controls their enabled state. Toolbar icons use regular 14-point SF Symbols with semantic label tint. Accessible names and tooltips explain icon actions; exterior focus rings are retained. Native bezels own hover, press and disabled rendering.

### Cards / Containers

The editor and pre-selection hint share `EditorSurface`. Settings sections use an `NSBox` with no title or border, semantic control fill and the documented group radius/insets. These are native container recipes, not portable HTML cards.

### Inputs / Fields

Thickness and text size use small `NSPopUpButton` controls, labeled and accessible, with 54-point widths. Thickness choices are 1, 2, 3, 5, 8 and 12. The temporary text editor is an `NSTextView` in a line-bordered `NSScrollView`, with a vertical scroller, semantic text/background and a 6-point text inset. Return commits; Shift-Return inserts a newline; Escape cancels capture. Output uses the preserved annotation pigment.

Settings use an `NSSwitch` for login launch and a native rounded button for shortcut recording. Recording temporarily displays “Нажмите сочетание…”, accepts a modified shortcut, and restores the current value on Escape or lost focus. Failures use native `NSAlert` sheets. Screen Recording status comes from actual authorization state and includes explicit recovery text and an action button.

### Color Swatches

`ColorSwatchButton` disables vibrancy for document pigments. Selection combines a 2-point accent ring, native on/off state and a checkmark whose black/white contrast follows pigment brightness. Hover and press add quiet semantic backing; focus uses an exterior ring. Each swatch has a Russian accessible color name. This custom drawing is limited to the pigment picker.

## Do's and Don'ts

### Do:

- **Do** use AppKit semantic colors and inherited appearance for interface surfaces and text.
- **Do** keep annotation pigments independent from interface accent and temporary text-entry colors.
- **Do** preserve native focus rings, accessible labels and native selected/disabled states.
- **Do** use SF Symbols for interface icons and runtime captures for verification.

### Don't:

- **Don't** replace regular native glass with a bitmap, gradient or custom blur simulation.
- **Don't** freeze dynamic NSColor roles into light/dark hex palettes.
- **Don't** add a custom display font or revive the superseded purple shell.
