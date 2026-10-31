import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem!
  let capture = CaptureCoordinator()
  let hotkeys = Hotkeys()
  lazy var settings = SettingsController(hotkeys: hotkeys)
  func applicationDidFinishLaunching(_ notification: Notification) {
    installEditMenu()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = Self.menuBarIcon()
    statusItem.button?.toolTip = "Kadrin — захват экрана"
    let menu = NSMenu()
    for (title, action) in [
      ("Выделить область", #selector(region)), ("Весь экран под курсором", #selector(full)),
      ("Настройки…", #selector(openSettings)), ("Завершить Kadrin", #selector(quit)),
    ] {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
    }
    statusItem.menu = menu
    capture.showError = { [weak self] in self?.alert($0) }
    hotkeys.onCapture = { [weak self] mode in
      guard let self else { return }
      if let recorder = self.settings.window?.firstResponder as? ShortcutButton, recorder.recording
      {
        recorder.receiveRegisteredShortcut(self.hotkeys.shortcut(mode))
        return
      }
      self.settings.window?.orderOut(nil)
      self.capture.start(mode)
    }
    for mode in CaptureMode.allCases {
      do { try hotkeys.register(hotkeys.shortcut(mode), for: mode) } catch {
        alert(error.localizedDescription)
      }
    }
    if !UserDefaults.standard.bool(forKey: "onboarding.shown") {
      UserDefaults.standard.set(true, forKey: "onboarding.shown")
      settings.present()
    }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    openSettings()
    return false
  }
  func applicationWillTerminate(_ notification: Notification) { capture.cancel() }
  static func menuBarIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: NSRect(x: 6, y: 7, width: 13, height: 10), xRadius: 2, yRadius: 2)
        .fill()
      // Cut a transparent gutter so both frames remain distinct in template rendering.
      NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
      NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: 16, height: 13), xRadius: 3, yRadius: 3)
        .fill()
      NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
      NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 13, height: 10), xRadius: 2, yRadius: 2)
        .fill()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Kadrin"
    return image
  }
  private func installEditMenu() {
    let main = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "Kadrin")
    for (title, action) in [
      ("Выделить область", #selector(region)), ("Весь экран под курсором", #selector(full)),
      ("Настройки…", #selector(openSettings)), ("Завершить Kadrin", #selector(quit)),
    ] {
      let item = applicationMenu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
    }
    applicationItem.submenu = applicationMenu
    main.addItem(applicationItem)
    let root = NSMenuItem()
    let edit = NSMenu(title: "Правка")
    let actions: [(String, Selector, String)] = [
      ("Вырезать", #selector(NSText.cut(_:)), "x"), ("Копировать", #selector(NSText.copy(_:)), "c"),
      ("Вставить", #selector(NSText.paste(_:)), "v"),
      ("Выделить всё", #selector(NSText.selectAll(_:)), "a"),
    ]
    for (title, action, key) in actions {
      edit.addItem(withTitle: title, action: action, keyEquivalent: key)
    }
    root.submenu = edit
    main.addItem(root)
    NSApp.mainMenu = main
  }
  private func alert(_ text: String) {
    let alert = NSAlert()
    alert.messageText = "Kadrin"
    alert.informativeText = text
    alert.addButton(withTitle: "Понятно")
    alert.addButton(withTitle: "Настройки")
    if alert.runModal() == .alertSecondButtonReturn { openSettings() }
  }
  private func menuCapture(_ mode: CaptureMode) {
    settings.window?.orderOut(nil)
    // Wait for the menu to disappear before freezing the desktop.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.capture.start(mode)
    }
  }
  @objc private func region() { menuCapture(.region) }
  @objc private func full() { menuCapture(.fullDisplay) }
  @objc private func openSettings() {
    capture.cancel()
    settings.present()
  }
  @objc private func quit() { NSApp.terminate(nil) }
}
MainActor.assumeIsolated {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = AppDelegate()
  app.delegate = delegate
  withExtendedLifetime(delegate) { app.run() }
}
