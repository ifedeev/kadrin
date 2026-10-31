import AppKit
import Carbon
import ServiceManagement

final class ShortcutButton: NSButton {
  var shortcut: Shortcut = .region { didSet { title = shortcut.label } }
  var onChange: ((Shortcut) throws -> Void)?
  private(set) var recording = false
  func receiveRegisteredShortcut(_ value: Shortcut) {
    guard recording else { return }
    do {
      try onChange?(value)
      shortcut = value
    } catch {
      title = shortcut.label
      let alert = NSAlert()
      alert.messageText = "Не удалось изменить сочетание"
      alert.informativeText = error.localizedDescription
      if let window { alert.beginSheetModal(for: window) }
    }
    recording = false
    title = shortcut.label
  }
  override var acceptsFirstResponder: Bool { true }
  init() {
    super.init(frame: .zero)
    bezelStyle = .rounded
    target = self
    action = #selector(record)
    setAccessibilityLabel("Изменить сочетание клавиш")
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func record() {
    recording = true
    title = "Нажмите сочетание…"
    window?.makeFirstResponder(self)
  }
  override func resignFirstResponder() -> Bool {
    recording = false
    title = shortcut.label
    return true
  }
  override func keyDown(with event: NSEvent) {
    guard recording else {
      super.keyDown(with: event)
      return
    }
    if event.keyCode == 53 {
      recording = false
      title = shortcut.label
      return
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !flags.intersection([.command, .control, .option]).isEmpty else {
      NSSound.beep()
      return
    }
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    let newValue = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    receiveRegisteredShortcut(newValue)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if recording {
      keyDown(with: event)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
@MainActor final class SettingsController: NSWindowController {
  let hotkeys: Hotkeys
  private let loginSwitch = NSSwitch()
  private let loginStatus = NSTextField(wrappingLabelWithString: "")
  private let permissionStatus = NSTextField(labelWithString: "")
  private let permissionIcon = NSImageView()
  private let permissionButton = NSButton()
  private let permissionDetail = NSTextField(wrappingLabelWithString: "")
  private var activationObserver: NSObjectProtocol?

  init(hotkeys: Hotkeys) {
    self.hotkeys = hotkeys
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 526), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.title = "Настройки Kadrin"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    let heading = NSTextField(labelWithString: "Kadrin")
    heading.font = .systemFont(ofSize: 22, weight: .semibold)
    let subtitle = detail("Быстрый снимок. Всё остаётся на вашем Mac.")
    let titles = NSStackView(views: [heading, subtitle])
    titles.orientation = .vertical
    titles.alignment = .leading
    titles.spacing = 6
    let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.setAccessibilityElement(false)
    icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
    let header = NSStackView(views: [icon, titles])
    header.spacing = 14
    var shortcutRows: [NSView] = []
    for mode in CaptureMode.allCases {
      let button = ShortcutButton()
      button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
      button.shortcut = hotkeys.shortcut(mode)
      button.widthAnchor.constraint(equalToConstant: 164).isActive = true
      button.heightAnchor.constraint(equalToConstant: 30).isActive = true
      button.onChange = { [weak hotkeys] value in try hotkeys?.register(value, for: mode) }
      let label = mode == .region ? "Выделить область" : "Весь экран под курсором"
      button.setAccessibilityLabel("Изменить сочетание: " + label)
      shortcutRows.append(row(label, control: button))
    }
    shortcutRows.append(detail("Нажмите сочетание, чтобы изменить его. Esc — отмена."))
    loginSwitch.target = self
    loginSwitch.action = #selector(toggleLogin)
    loginSwitch.setAccessibilityLabel("Запускать при входе в macOS")
    configureDetail(loginStatus)
    let general = section(
      "Основные", rows: [row("Запускать при входе в macOS", control: loginSwitch), loginStatus])

    permissionStatus.font = .systemFont(ofSize: 13, weight: .medium)
    permissionIcon.symbolConfiguration = .init(pointSize: 16, weight: .medium)
    permissionIcon.widthAnchor.constraint(equalToConstant: 20).isActive = true
    permissionIcon.heightAnchor.constraint(equalToConstant: 20).isActive = true
    let permissionLabel = NSStackView(views: [permissionIcon, permissionStatus])
    permissionLabel.spacing = 7
    permissionButton.bezelStyle = .push
    permissionButton.font = .systemFont(ofSize: 12)
    permissionButton.target = self
    permissionButton.action = #selector(permission)
    permissionButton.widthAnchor.constraint(equalToConstant: 164).isActive = true
    let permissionRow = NSStackView(views: [permissionLabel, NSView(), permissionButton])
    permissionRow.spacing = 8
    configureDetail(permissionDetail)
    let permissions = section("Запись экрана", rows: [permissionRow, permissionDetail])

    let stack = NSStackView(views: [
      header, section("Сочетания клавиш", rows: shortcutRows), general, permissions,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 22
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView?.addSubview(stack)
    if let content = window.contentView {
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
        stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
        stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
      ])
    }
    for item in stack.arrangedSubviews {
      item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    refreshLogin()
    refreshPermission()
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshPermission()
        self?.refreshLogin()
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
  }
  private func configureDetail(_ label: NSTextField) {
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }
  private func detail(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    configureDetail(label)
    return label
  }
  private func row(_ text: String, control: NSView) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 13)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    let row = NSStackView(views: [label, NSView(), control])
    row.spacing = 12
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    return row
  }
  private func section(_ title: String, rows: [NSView]) -> NSView {
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 12, weight: .semibold)
    let box = NSBox()
    box.titlePosition = .noTitle
    box.boxType = .custom
    box.borderWidth = 0
    box.fillColor = .controlBackgroundColor
    box.cornerRadius = 10
    let content = NSView()
    box.contentView = content
    let fields = NSStackView(views: rows)
    fields.orientation = .vertical
    fields.alignment = .leading
    fields.spacing = 10
    fields.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(fields)
    NSLayoutConstraint.activate([
      fields.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
      fields.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
      fields.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
      fields.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
    ])
    for row in rows { row.widthAnchor.constraint(equalTo: fields.widthAnchor).isActive = true }
    let group = NSStackView(views: [heading, box])
    group.orientation = .vertical
    group.alignment = .leading
    group.spacing = 8
    box.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
    return group
  }
  func present() {
    refreshLogin()
    refreshPermission()
    window?.center()
    showWindow(nil)
    NSApp.activate()
  }
  private func refreshPermission() {
    let allowed = CGPreflightScreenCaptureAccess()
    permissionStatus.stringValue = allowed ? "Доступ разрешён" : "Требуется разрешение"
    permissionIcon.image = NSImage(
      systemSymbolName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
      accessibilityDescription: nil)
    permissionIcon.contentTintColor = allowed ? .systemGreen : .systemOrange
    permissionButton.title = allowed ? "Открыть настройки…" : "Разрешить…"
    permissionDetail.stringValue =
      allowed
      ? "Можно захватывать область или весь экран."
      : "Разрешите доступ в настройках macOS. После этого может потребоваться перезапуск Kadrin."
  }
  private func refreshLogin() {
    let state = SMAppService.mainApp.status
    loginSwitch.state = state == .enabled ? .on : .off
    loginStatus.stringValue =
      state == .requiresApproval
      ? "Подтвердите автозапуск в macOS → Основные → Объекты входа."
      : "Kadrin будет доступен в строке меню после входа."
  }
  @objc private func toggleLogin() {
    do {
      if loginSwitch.state == .on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      let alert = NSAlert()
      alert.messageText = "Не удалось изменить автозапуск"
      alert.informativeText = error.localizedDescription
      if let window { alert.beginSheetModal(for: window) }
    }
    refreshLogin()
  }
  @objc private func permission() {
    if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(url)
    }
  }
}
