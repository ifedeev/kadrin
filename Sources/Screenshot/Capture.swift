import AppKit
import ScreenCaptureKit
import ScreenshotCore

struct ScreenSnapshot {
  let screen: NSScreen
  let image: CGImage
}
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  init(screen: NSScreen) {
    super.init(
      contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    level = .screenSaver
    collectionBehavior = [
      .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle,
    ]
    isOpaque = true
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .none
  }
}
@MainActor final class CaptureCoordinator {
  private var gate = CaptureGate()
  private var panels: [OverlayPanel] = []
  private var observers: [NSObjectProtocol] = []
  var showError: ((String) -> Void)?
  init() {
    observers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
  }
  func cancel() {
    gate.cancel()
    panels.forEach { panel in
      if let sheet = panel.attachedSheet { panel.endSheet(sheet, returnCode: .cancel) }
      panel.orderOut(nil)
      panel.close()
    }
    panels.removeAll()
  }
  func start(_ mode: CaptureMode) {
    guard let token = gate.begin() else { return }
    let pointer = NSEvent.mouseLocation
    guard CGPreflightScreenCaptureAccess() else {
      gate.cancel()
      showError?(
        "Разрешите Kadrin запись экрана: Системные настройки → Конфиденциальность и безопасность → Запись экрана и системного аудио. Затем перезапустите Kadrin."
      )
      return
    }
    Task {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        let screens = NSScreen.screens
        var snapshots: [ScreenSnapshot] = []
        for screen in screens {
          guard gate.accepts(token) else { return }
          guard
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
            let display = content.displays.first(where: { $0.displayID == id })
          else {
            throw NSError(
              domain: "Screenshot", code: 1,
              userInfo: [
                NSLocalizedDescriptionKey: "Не удалось получить изображение одного из экранов."
              ])
          }
          let filter = SCContentFilter(display: display, excludingWindows: [])
          let config = SCScreenshotConfiguration()
          config.dynamicRange = .sdr
          config.showsCursor = false
          config.width = Int(screen.frame.width * screen.backingScaleFactor)
          config.height = Int(screen.frame.height * screen.backingScaleFactor)
          let output = try await SCScreenshotManager.captureScreenshot(
            contentFilter: filter, configuration: config)
          guard let image = output.sdrImage else {
            throw NSError(
              domain: "Screenshot", code: 2,
              userInfo: [NSLocalizedDescriptionKey: "macOS вернула пустой снимок."])
          }
          snapshots.append(ScreenSnapshot(screen: screen, image: image))
        }
        guard gate.accepts(token) else { return }
        present(snapshots, mode: mode, pointer: pointer)
      } catch {
        guard gate.accepts(token) else { return }
        cancel()
        showError?(error.localizedDescription)
      }
    }
  }
  private func present(_ snapshots: [ScreenSnapshot], mode: CaptureMode, pointer: NSPoint) {
    for snapshot in snapshots {
      if mode == .fullDisplay && !snapshot.screen.frame.contains(pointer) { continue }
      let panel = OverlayPanel(screen: snapshot.screen)
      let view = EditorView(
        frame: NSRect(origin: .zero, size: snapshot.screen.frame.size), image: snapshot.image,
        fullDisplay: mode == .fullDisplay)
      view.onCancel = { [weak self] in self?.cancel() }
      view.onClaimScreen = { [weak self, weak panel] in
        guard let self, let panel else { return }
        for other in self.panels where other !== panel { other.orderOut(nil) }
      }
      panel.contentView = view
      panels.append(panel)
      panel.orderFrontRegardless()
      if snapshot.screen.frame.contains(pointer) {
        panel.makeKey()
        panel.makeFirstResponder(view)
      }
    }
    if panels.isEmpty {
      cancel()
      showError?("Не удалось определить экран под курсором.")
    }
  }
}
