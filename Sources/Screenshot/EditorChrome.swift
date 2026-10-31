import AppKit
import ScreenshotCore

/// Let AppKit own glass, appearance and accessibility-material adaptation.
final class EditorSurface: NSGlassEffectView {
  let content = NSView()
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    style = .regular
    cornerRadius = 16
    contentView = content
  }
  required init?(coder: NSCoder) { fatalError() }
}

final class ColorSwatchButton: NSButton {
  let color: RGBA
  private var hovering = false
  init(color: RGBA, name: String, target: AnyObject, action: Selector) {
    self.color = color
    super.init(frame: .zero)
    title = ""
    self.target = target
    self.action = action
    setButtonType(.pushOnPushOff)
    isBordered = false
    focusRingType = .exterior
    toolTip = name
    setAccessibilityLabel(name)
    widthAnchor.constraint(equalToConstant: 26).isActive = true
    heightAnchor.constraint(equalToConstant: 26).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override var allowsVibrancy: Bool { false }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways], owner: self))
  }
  override func mouseEntered(with event: NSEvent) {
    hovering = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovering = false
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    if hovering || isHighlighted {
      NSColor.quaternaryLabelColor.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
    let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
    color.nsColor.setFill()
    circle.fill()
    NSColor.separatorColor.setStroke()
    circle.lineWidth = 1
    circle.stroke()
    if state == .on {
      let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
      NSColor.controlAccentColor.setStroke()
      ring.lineWidth = 2
      ring.stroke()
      let brightness = color.red * 0.299 + color.green * 0.587 + color.blue * 0.114
      let contrast: NSColor = brightness > 0.6 ? .black : .white
      let symbol = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))?
        .withSymbolConfiguration(.init(paletteColors: [contrast]))
      symbol?.draw(in: bounds.insetBy(dx: 7, dy: 7))
    }
  }
  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
  }
}
