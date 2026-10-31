import AppKit

public enum Tool: String, CaseIterable, Codable {
  case select, pen, line, arrow, rectangle, ellipse, marker, text, number, blur, conceal
  public var title: String {
    switch self {
    case .select: return "Выбор и перемещение"
    case .pen: return "Карандаш"
    case .line: return "Линия"
    case .arrow: return "Стрелка"
    case .rectangle: return "Прямоугольник"
    case .ellipse: return "Эллипс"
    case .marker: return "Маркер"
    case .text: return "Текст"
    case .number: return "Номер шага"
    case .blur: return "Размытие"
    case .conceal: return "Скрыть фрагмент"
    }
  }
  public var symbol: String {
    switch self {
    case .select: return "cursorarrow"
    case .pen: return "pencil.tip"
    case .line: return "line.diagonal"
    case .arrow: return "arrow.up.right"
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    case .marker: return "highlighter"
    case .text: return "textformat"
    case .number: return "1.circle"
    case .blur: return "drop.halffull"
    case .conceal: return "rectangle.fill"
    }
  }
}
public struct RGBA: Codable, Equatable {
  public var red: Double, green: Double, blue: Double
  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }
  public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
  public static let accent = RGBA(red: 1, green: 0.24, blue: 0.3)
}
public struct Annotation: Equatable, Identifiable {
  public let id: UUID
  public var tool: Tool
  public var points: [CGPoint]
  public var color: RGBA = .accent
  public var width: CGFloat = 3
  public var fontSize: CGFloat = 24
  public var text = ""
  public var number = 1
  public init(tool: Tool, points: [CGPoint]) {
    id = UUID()
    self.tool = tool
    self.points = points
  }
  public var bounds: CGRect {
    guard let first = points.first else { return .zero }
    if tool == .text {
      let size = (text.isEmpty ? " " : text as NSString).size(withAttributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
      ])
      return CGRect(
        origin: first,
        size: CGSize(width: max(12, size.width), height: max(fontSize + 4, size.height)))
    }
    if tool == .number {
      return CGRect(
        x: first.x - fontSize * 0.7, y: first.y - fontSize * 0.7, width: fontSize * 1.4,
        height: fontSize * 1.4)
    }
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    return CGRect(
      x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
  }
  public mutating func move(by delta: CGSize) {
    points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
  }
  public mutating func resize(to rect: CGRect) {
    let old = bounds
    if tool == .text || tool == .number {
      fontSize = max(8, min(240, fontSize * rect.height / max(1, old.height)))
      points = [tool == .number ? CGPoint(x: rect.midX, y: rect.midY) : rect.origin]
    } else {
      points = points.map {
        CGPoint(
          x: old.width > 0 ? rect.minX + ($0.x - old.minX) * rect.width / old.width : rect.midX,
          y: old.height > 0 ? rect.minY + ($0.y - old.minY) * rect.height / old.height : rect.midY)
      }
    }
  }
  public func contains(_ point: CGPoint) -> Bool {
    guard [.line, .arrow, .pen, .marker].contains(tool) else {
      return bounds.insetBy(dx: -6, dy: -6).contains(point)
    }
    let tolerance = max(6, tool == .marker ? width * 2 : width / 2 + 3)
    guard let first = points.first else { return false }
    if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= tolerance }
    for (a, b) in zip(points, points.dropFirst()) {
      let dx = b.x - a.x
      let dy = b.y - a.y
      let length = dx * dx + dy * dy
      let t =
        length > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
      if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance { return true }
    }
    return false
  }
}
public struct EditorDocument: Equatable {
  public var selection: CGRect
  public var annotations: [Annotation]
  public init(selection: CGRect = .zero, annotations: [Annotation] = []) {
    self.selection = selection
    self.annotations = annotations
  }
}
public struct EditHistory {
  public private(set) var current: EditorDocument
  private var past: [EditorDocument] = []
  private var future: [EditorDocument] = []
  public var canUndo: Bool { !past.isEmpty }
  public var canRedo: Bool { !future.isEmpty }
  public init(initial: EditorDocument) { current = initial }
  public mutating func commit(_ document: EditorDocument) {
    guard document != current else { return }
    past.append(current)
    current = document
    future.removeAll()
    if past.count > 100 { past.removeFirst() }
  }
  public mutating func undo() {
    guard let previous = past.popLast() else { return }
    future.append(current)
    current = previous
  }
  public mutating func redo() {
    guard let next = future.popLast() else { return }
    past.append(current)
    current = next
  }
}
public struct ImageGeometry {
  public let pointSize: CGSize, pixelSize: CGSize
  public init(pointSize: CGSize, pixelSize: CGSize) {
    self.pointSize = pointSize
    self.pixelSize = pixelSize
  }
  public func pixelRect(for rect: CGRect) -> CGRect? {
    guard pointSize.width > 0, pointSize.height > 0, pixelSize.width > 0, pixelSize.height > 0
    else { return nil }
    let clipped = rect.standardized.intersection(CGRect(origin: .zero, size: pointSize))
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
    let sx = pixelSize.width / pointSize.width
    let sy = pixelSize.height / pointSize.height
    let result = CGRect(
      x: clipped.minX * sx, y: (pointSize.height - clipped.maxY) * sy, width: clipped.width * sx,
      height: clipped.height * sy
    ).integral
    return result.intersection(CGRect(origin: .zero, size: pixelSize))
  }
}
