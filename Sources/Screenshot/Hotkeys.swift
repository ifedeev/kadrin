import AppKit
import Carbon

enum CaptureMode: Int, CaseIterable {
  case region = 1
  case fullDisplay = 2
}
struct Shortcut: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  static let region = Shortcut(keyCode: 1, modifiers: UInt32(optionKey | shiftKey))
  static let fullDisplay = Shortcut(keyCode: 3, modifiers: UInt32(optionKey | shiftKey))
  var label: String {
    let keys: [UInt32: String] = [
      0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
      12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
      22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P",
      37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
    ]
    return (modifiers & UInt32(controlKey) != 0 ? "⌃" : "")
      + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "")
      + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "")
      + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + (keys[keyCode] ?? "Key \(keyCode)")
  }
}
final class Hotkeys {
  var onCapture: ((CaptureMode) -> Void)?
  private var refs: [CaptureMode: EventHotKeyRef] = [:]
  private var values: [CaptureMode: Shortcut] = [:]
  private var handler: EventHandlerRef?
  init() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
        if let mode = CaptureMode(rawValue: Int(id.id)) { owner.onCapture?(mode) }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }
  func shortcut(_ mode: CaptureMode) -> Shortcut {
    if let data = UserDefaults.standard.data(forKey: "shortcut.\(mode.rawValue)"),
      let value = try? JSONDecoder().decode(Shortcut.self, from: data)
    {
      return value
    }
    return mode == .region ? .region : .fullDisplay
  }
  func register(_ value: Shortcut, for mode: CaptureMode) throws {
    if values[mode] == value { return }
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      value.keyCode, value.modifiers,
      EventHotKeyID(signature: 0x5343_524E, id: UInt32(mode.rawValue)), GetApplicationEventTarget(),
      OptionBits(kEventHotKeyExclusive), &ref)
    guard status == noErr, let ref else {
      throw NSError(
        domain: "Screenshot", code: Int(status),
        userInfo: [
          NSLocalizedDescriptionKey:
            "Сочетание \(value.label) недоступно (код \(status)). Выберите другое; прежнее сочетание сохранено."
        ])
    }
    if let old = refs[mode] { UnregisterEventHotKey(old) }
    refs[mode] = ref
    values[mode] = value
    UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "shortcut.\(mode.rawValue)")
  }
  deinit {
    for ref in refs.values { UnregisterEventHotKey(ref) }
    if let handler { RemoveEventHandler(handler) }
  }
}
