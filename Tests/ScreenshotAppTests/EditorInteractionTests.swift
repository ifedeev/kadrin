import AppKit
import ScreenshotCore
import XCTest

@testable import Screenshot

final class EditorInteractionTests: XCTestCase {
  @MainActor func testMenuBarIconPreservesTransparentSeparation() throws {
    let image = AppDelegate.menuBarIcon()
    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.size, NSSize(width: 20, height: 18))
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 3, y: 9)).alphaComponent, 0.9)
    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 17, y: 3)).alphaComponent, 0.9)
    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 15, y: 7)).alphaComponent, 0.1)
  }
  @MainActor private func view(width: CGFloat = 800, fullDisplay: Bool = true) throws -> EditorView
  {
    _ = NSApplication.shared
    let c = try XCTUnwrap(
      CGContext(
        data: nil, width: Int(width), height: 600, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    c.setFillColor(NSColor.white.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: width, height: 600))
    return EditorView(
      frame: CGRect(x: 0, y: 0, width: width, height: 600), image: try XCTUnwrap(c.makeImage()),
      fullDisplay: fullDisplay)
  }
  private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
  }
  @MainActor func testUndoDuringDrawingDoesNotCrashOnNextDrag() throws {
    let editor = try view()
    func buttons(_ view: NSView) -> [NSButton] {
      (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
    try XCTUnwrap(buttons(editor).first { $0.toolTip == Tool.arrow.title }).performClick(nil)
    editor.mouseDown(with: try mouse(.leftMouseDown, 200, 200))
    editor.mouseDragged(with: try mouse(.leftMouseDragged, 300, 300))
    let undo = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
        context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false,
        keyCode: 6))
    XCTAssertTrue(editor.performKeyEquivalent(with: undo))
    editor.mouseDragged(with: try mouse(.leftMouseDragged, 400, 300))
    editor.mouseUp(with: try mouse(.leftMouseUp, 400, 300))
    XCTAssertNotNil(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
  }
  @MainActor func testShortcutRecordingAppliesOnlyAcceptedValues() {
    let button = ShortcutButton()
    button.shortcut = .region
    button.onChange = { _ in }
    button.performClick(nil)
    button.receiveRegisteredShortcut(.fullDisplay)
    XCTAssertEqual(button.shortcut, .fullDisplay)
    XCTAssertFalse(button.recording)
    button.onChange = { _ in throw NSError(domain: "HotkeyTest", code: 1) }
    button.performClick(nil)
    button.receiveRegisteredShortcut(.region)
    XCTAssertEqual(
      button.shortcut, .fullDisplay, "Failed registration must preserve the working shortcut")
    XCTAssertFalse(button.recording)
  }
  @MainActor func testNativeToolbarAppearanceSelectionAndContext() throws {
    let editor = try view()
    editor.appearance = NSAppearance(named: .aqua)
    let toolbar = try XCTUnwrap(editor.subviews.first)
    XCTAssertNotEqual(
      toolbar.appearance?.name, .darkAqua, "Toolbar must inherit the user's appearance")
    func controls(_ view: NSView) -> [NSControl] {
      (view as? NSControl).map { [$0] } ?? view.subviews.flatMap(controls)
    }
    let buttons = controls(toolbar).compactMap { $0 as? NSButton }
    let select = try XCTUnwrap(buttons.first { $0.toolTip == Tool.select.title })
    XCTAssertEqual(select.state, .on)
    let arrow = try XCTUnwrap(buttons.first { $0.toolTip == Tool.arrow.title })
    XCTAssertEqual(arrow.state, .off)
    let font = try XCTUnwrap(controls(toolbar).first { $0.toolTip == "Размер текста" })
    let width = try XCTUnwrap(controls(toolbar).first { $0.toolTip == "Толщина линии" })
    XCTAssertTrue(font.isHiddenOrHasHiddenAncestor)
    XCTAssertTrue(width.isHiddenOrHasHiddenAncestor)
    arrow.performClick(nil)
    XCTAssertFalse(width.isHiddenOrHasHiddenAncestor)
    try XCTUnwrap(buttons.first { $0.toolTip == Tool.text.title }).performClick(nil)
    XCTAssertFalse(font.isHiddenOrHasHiddenAncestor)
    XCTAssertTrue(width.isHiddenOrHasHiddenAncestor)
    XCTAssertEqual(arrow.state, .off)
    let nextEditor = try view()
    let nextSelect = try XCTUnwrap(
      controls(nextEditor).compactMap { $0 as? NSButton }.first { $0.toolTip == Tool.select.title })
    XCTAssertEqual(nextSelect.state, .on)
  }
  @MainActor func testToolbarAppearsOnlyAfterRegionSelectionFinishes() throws {
    let editor = try view(fullDisplay: false)
    let toolbar = try XCTUnwrap(editor.subviews.first)
    XCTAssertTrue(toolbar.isHidden)
    editor.mouseDown(with: try mouse(.leftMouseDown, 300, 200))
    editor.mouseDragged(with: try mouse(.leftMouseDragged, 500, 400))
    XCTAssertTrue(toolbar.isHidden)
    editor.mouseUp(with: try mouse(.leftMouseUp, 500, 400))
    XCTAssertFalse(toolbar.isHidden)

    let previousOrigin = toolbar.frame.origin
    editor.mouseDown(with: try mouse(.leftMouseDown, 400, 300))
    editor.mouseDragged(with: try mouse(.leftMouseDragged, 450, 350))
    editor.mouseUp(with: try mouse(.leftMouseUp, 450, 350))
    XCTAssertEqual(toolbar.frame.minX, previousOrigin.x + 50)
    XCTAssertEqual(toolbar.frame.minY, previousOrigin.y + 50)
  }
  @MainActor func testRejectedRegionSelectionKeepsToolbarHidden() throws {
    let editor = try view(fullDisplay: false)
    let toolbar = try XCTUnwrap(editor.subviews.first)
    editor.mouseDown(with: try mouse(.leftMouseDown, 200, 200))
    editor.mouseDragged(with: try mouse(.leftMouseDragged, 201, 300))
    XCTAssertTrue(toolbar.isHidden)
    editor.mouseUp(with: try mouse(.leftMouseUp, 201, 300))
    XCTAssertTrue(toolbar.isHidden)
  }
  @MainActor func testBlurToolHidesUnrelatedControlsAndSupportsUndo() throws {
    let editor = try view()
    func controls(_ view: NSView) -> [NSControl] {
      (view as? NSControl).map { [$0] } ?? view.subviews.flatMap(controls)
    }
    XCTAssertNotNil(NSImage(systemSymbolName: Tool.blur.symbol, accessibilityDescription: nil))
    let all = controls(editor)
    let blur = try XCTUnwrap(
      all.compactMap { $0 as? NSButton }.first { $0.toolTip == Tool.blur.title })
    blur.performClick(nil)
    XCTAssertEqual(blur.state, .on)
    for label in ["Красный", "Толщина линии", "Размер текста"] {
      XCTAssertTrue(try XCTUnwrap(all.first { $0.toolTip == label }).isHiddenOrHasHiddenAncestor)
    }
    let undo = try XCTUnwrap(
      all.compactMap { $0 as? NSButton }.first { $0.toolTip == "Отменить (⌘Z)" })
    let redo = try XCTUnwrap(
      all.compactMap { $0 as? NSButton }.first { $0.toolTip == "Повторить (⇧⌘Z)" })
    editor.mouseDown(with: try mouse(.leftMouseDown, 200, 200))
    editor.mouseDragged(with: try mouse(.leftMouseDragged, 350, 300))
    editor.mouseUp(with: try mouse(.leftMouseUp, 350, 300))
    XCTAssertTrue(undo.isEnabled)
    undo.performClick(nil)
    XCTAssertFalse(undo.isEnabled)
    XCTAssertTrue(redo.isEnabled)
    redo.performClick(nil)
    XCTAssertTrue(undo.isEnabled)
  }
  @MainActor private func capture(_ view: NSView, name: String) throws {
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      view.cacheDisplay(in: view.bounds, to: bitmap)
    }
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent(".impeccable/review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
  }
  @MainActor func testToolbarLayoutAndPreview() throws {
    for (theme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
      for width: CGFloat in [640, 800] {
        let editor = try view(width: width)
        editor.appearance = NSAppearance(named: theme)
        editor.layoutSubtreeIfNeeded()
        let toolbar = try XCTUnwrap(editor.subviews.first)
        func checkControls(_ view: NSView) {
          guard !view.isHiddenOrHasHiddenAncestor else { return }
          if view is NSControl {
            let rect = view.convert(view.bounds, to: toolbar)
            XCTAssertGreaterThanOrEqual(rect.minX, -1)
            XCTAssertLessThanOrEqual(rect.maxX, toolbar.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(rect.minY, -1)
            XCTAssertLessThanOrEqual(rect.maxY, toolbar.bounds.maxY + 1)
          }
          view.subviews.forEach(checkControls)
        }
        func toolButtons(_ view: NSView) -> [NSButton] {
          (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(toolButtons)
        }
        for tool in Tool.allCases {
          try XCTUnwrap(toolButtons(toolbar).first { $0.toolTip == tool.title }).performClick(nil)
          editor.layoutSubtreeIfNeeded()
          checkControls(toolbar)
        }
        try XCTUnwrap(toolButtons(toolbar).first { $0.toolTip == Tool.arrow.title }).performClick(
          nil)
        XCTAssertLessThanOrEqual(toolbar.frame.maxX, editor.bounds.maxX - 11)
        try capture(editor, name: "editor-\(name)-\(Int(width))")
      }
      let empty = try view(fullDisplay: false)
      empty.appearance = NSAppearance(named: theme)
      try capture(empty, name: "selection-" + name)
    }
  }
  @MainActor func testSettingsLayoutAndPreview() throws {
    let controller = SettingsController(hotkeys: Hotkeys())
    let window = try XCTUnwrap(controller.window)
    let content = try XCTUnwrap(window.contentView)
    for (theme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
      window.appearance = NSAppearance(named: theme)
      content.layoutSubtreeIfNeeded()
      func checkControls(_ view: NSView) {
        if view is NSControl {
          let rect = view.convert(view.bounds, to: content)
          XCTAssertGreaterThanOrEqual(rect.minY, 0)
          XCTAssertLessThanOrEqual(rect.maxY, content.bounds.height)
          XCTAssertGreaterThanOrEqual(rect.minX, 0)
          XCTAssertLessThanOrEqual(rect.maxX, content.bounds.width)
        }
        view.subviews.forEach(checkControls)
      }
      checkControls(content)
      try capture(content, name: "settings-" + name)
    }
  }
  @MainActor func testTextEntryStaysInsideRightEdge() throws {
    let editor = try view()
    func findTextButton(_ view: NSView) -> NSButton? {
      if let button = view as? NSButton, button.toolTip == Tool.text.title { return button }
      return view.subviews.compactMap(findTextButton).first
    }
    try XCTUnwrap(findTextButton(editor)).performClick(nil)
    editor.mouseDown(with: try mouse(.leftMouseDown, 790, 400))
    let scroll = try XCTUnwrap(editor.subviews.first { $0 is NSScrollView })
    XCTAssertLessThanOrEqual(scroll.frame.maxX, editor.bounds.maxX)
    XCTAssertGreaterThanOrEqual(scroll.frame.minX, 0)
  }
  @MainActor func testTextEntryRemainsReadableWithWhiteAndBlackAnnotations() throws {
    let savedColor = UserDefaults.standard.object(forKey: "drawing.color")
    defer { UserDefaults.standard.set(savedColor, forKey: "drawing.color") }
    for (theme, colorName) in [(NSAppearance.Name.aqua, "Белый"), (.darkAqua, "Чёрный")] {
      let editor = try view()
      editor.appearance = NSAppearance(named: theme)
      func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
      }
      try XCTUnwrap(buttons(editor).first { $0.toolTip == Tool.text.title }).performClick(nil)
      try XCTUnwrap(buttons(editor).first { $0.toolTip == colorName }).performClick(nil)
      editor.mouseDown(with: try mouse(.leftMouseDown, 300, 300))
      let scroll = try XCTUnwrap(editor.subviews.compactMap { $0 as? NSScrollView }.first)
      let text = try XCTUnwrap(scroll.documentView as? NSTextView)
      XCTAssertEqual(text.textColor, NSColor.textColor)
      XCTAssertEqual(scroll.backgroundColor, NSColor.textBackgroundColor)
    }
  }
}
