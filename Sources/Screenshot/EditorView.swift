import AppKit
import ScreenshotCore
import UniformTypeIdentifiers

private final class CaptureTextView: NSTextView {
  var finish: (() -> Void)?
  var cancel: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      cancel?()
    } else if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
      finish?()
    } else {
      super.keyDown(with: event)
    }
  }
}
final class EditorView: NSView {
  let image: CGImage
  private var blurredImage: CGImage?
  var onCancel: (() -> Void)?
  var onClaimScreen: (() -> Void)?
  private var document: EditorDocument
  private var history: EditHistory
  private var selected: UUID?
  private var tool: Tool = .select
  private var color = RGBA.accent
  private var lineWidth: CGFloat = 3
  private var fontSize: CGFloat = 24
  private var dragStart = CGPoint.zero
  private var dragDocument = EditorDocument()
  private enum Drag {
    case none, selection, moveRegion
    case resizeRegion(Int)
    case drawing(Int)
    case moveObject(Int)
    case resizeObject(Int, Int)
  }
  private var drag: Drag = .none
  private var spaceDown = false
  private let toolbar = EditorSurface()
  private let captureHint = EditorSurface()
  private let toolLabel = NSTextField(labelWithString: "")
  private let selectionHint = NSTextField(labelWithString: "Выберите объект для изменения")
  private let colorsRow = NSStackView()
  private let widthRow = NSStackView()
  private let fontRow = NSStackView()
  private var colorButtons: [ColorSwatchButton] = []
  private let sizeLabel = NSTextField(labelWithString: "")
  private var toolButtons: [Tool: NSButton] = [:]
  private var undoButton: NSButton!
  private var redoButton: NSButton!
  private let widths = NSPopUpButton(frame: .zero, pullsDown: false)
  private let fonts = NSPopUpButton(frame: .zero, pullsDown: false)
  private var textEditor: CaptureTextView?
  private var textContainerView: NSScrollView?
  private var editingID: UUID?
  private var panelOpen = false
  private let palette: [RGBA] = [
    .accent, RGBA(red: 1, green: 0.65, blue: 0.1), RGBA(red: 1, green: 0.9, blue: 0.2),
    RGBA(red: 0.2, green: 0.85, blue: 0.45), RGBA(red: 0.2, green: 0.65, blue: 1),
    RGBA(red: 1, green: 1, blue: 1), RGBA(red: 0, green: 0, blue: 0),
  ]
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  init(frame: CGRect, image: CGImage, fullDisplay: Bool) {
    self.image = image
    document = EditorDocument(
      selection: fullDisplay ? CGRect(origin: .zero, size: frame.size) : .zero)
    history = EditHistory(initial: document)
    super.init(frame: frame)
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: "drawing.color"),
      let saved = try? JSONDecoder().decode(RGBA.self, from: data)
    {
      color = saved
    }
    lineWidth = CGFloat(defaults.object(forKey: "drawing.width") as? Double ?? 3)
    fontSize = CGFloat(defaults.object(forKey: "drawing.font") as? Double ?? 24)
    makeToolbar()
    refresh()
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(
      "Редактор скриншота. Выделите область мышью. Пробел и перетаскивание — перемещение области. Escape — отмена."
    )
  }
  required init?(coder: NSCoder) { fatalError() }
  private func makeToolbar() {
    let tools = NSStackView()
    tools.spacing = 1
    for (index, item) in Tool.allCases.enumerated() {
      let button = icon(item.symbol, item.title, action: #selector(chooseTool(_:)))
      button.setButtonType(.pushOnPushOff)
      button.bezelStyle = .accessoryBar
      button.tag = index
      tools.addArrangedSubview(button)
      toolButtons[item] = button
    }
    undoButton = icon("arrow.uturn.backward", "Отменить (⌘Z)", action: #selector(undoAction))
    redoButton = icon("arrow.uturn.forward", "Повторить (⇧⌘Z)", action: #selector(redoAction))
    let historyRow = NSStackView(views: [undoButton, redoButton])
    historyRow.spacing = 2
    let copy = NSButton(title: "Копировать", target: self, action: #selector(copyImage))
    copy.bezelStyle = .push
    copy.bezelColor = .controlAccentColor
    copy.font = .systemFont(ofSize: 12, weight: .semibold)
    copy.toolTip = "Копировать изображение (⌘C)"
    copy.setAccessibilityLabel("Копировать изображение")
    copy.widthAnchor.constraint(equalToConstant: 100).isActive = true
    copy.heightAnchor.constraint(equalToConstant: 32).isActive = true
    let export = NSStackView(views: [
      copy,
      icon("square.and.arrow.down", "Сохранить PNG (⌘S)", action: #selector(saveImage)),
      icon("xmark", "Отменить захват (Esc)", action: #selector(cancelCapture)),
    ])
    export.spacing = 4
    let top = NSStackView(views: [tools, divider(), historyRow, divider(), export])
    top.spacing = 4
    top.distribution = .fill

    colorsRow.spacing = 2
    let names = ["Красный", "Оранжевый", "Жёлтый", "Зелёный", "Синий", "Белый", "Чёрный"]
    for (index, value) in palette.enumerated() {
      let button = ColorSwatchButton(
        color: value, name: names[index], target: self, action: #selector(chooseColor(_:)))
      button.tag = index
      colorButtons.append(button)
      colorsRow.addArrangedSubview(button)
    }
    configure(
      widths, titles: ["1", "2", "3", "5", "8", "12"], value: lineWidth, label: "Толщина линии")
    configure(
      fonts, titles: ["14", "18", "24", "32", "48", "64"], value: fontSize, label: "Размер текста")
    for (row, label, popup) in [(widthRow, "Толщина", widths), (fontRow, "Размер", fonts)] {
      let text = NSTextField(labelWithString: label)
      text.font = .systemFont(ofSize: 11)
      text.textColor = .secondaryLabelColor
      row.spacing = 5
      row.addArrangedSubview(text)
      row.addArrangedSubview(popup)
    }
    toolLabel.font = .systemFont(ofSize: 11, weight: .medium)
    toolLabel.textColor = .secondaryLabelColor
    toolLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    selectionHint.font = .systemFont(ofSize: 11)
    selectionHint.textColor = .secondaryLabelColor
    sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    sizeLabel.textColor = .secondaryLabelColor
    sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let bottom = NSStackView(views: [
      toolLabel, colorsRow, widthRow, fontRow, selectionHint, spacer, sizeLabel,
    ])
    bottom.spacing = 10
    let stack = NSStackView(views: [top, bottom])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    toolbar.content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: toolbar.content.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: toolbar.content.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: toolbar.content.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: toolbar.content.bottomAnchor, constant: -10),
      bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    addSubview(toolbar)

    let hintTitle = NSTextField(labelWithString: "Выделите область")
    hintTitle.font = .systemFont(ofSize: 15, weight: .semibold)
    let hintDetail = NSTextField(labelWithString: "Потяните мышью · Esc — отмена")
    hintDetail.font = .systemFont(ofSize: 12)
    hintDetail.textColor = .secondaryLabelColor
    let hintStack = NSStackView(views: [hintTitle, hintDetail])
    hintStack.orientation = .vertical
    hintStack.spacing = 5
    hintStack.translatesAutoresizingMaskIntoConstraints = false
    captureHint.content.addSubview(hintStack)
    NSLayoutConstraint.activate([
      hintStack.centerXAnchor.constraint(equalTo: captureHint.content.centerXAnchor),
      hintStack.centerYAnchor.constraint(equalTo: captureHint.content.centerYAnchor),
    ])
    addSubview(captureHint)
  }
  private func divider() -> NSView {
    let line = NSBox()
    line.boxType = .separator
    line.widthAnchor.constraint(equalToConstant: 1).isActive = true
    line.heightAnchor.constraint(equalToConstant: 20).isActive = true
    return line
  }
  private func configure(_ popup: NSPopUpButton, titles: [String], value: CGFloat, label: String) {
    popup.addItems(withTitles: titles)
    popup.selectItem(withTitle: String(Int(value)))
    popup.controlSize = .small
    popup.font = .systemFont(ofSize: 11)
    popup.target = self
    popup.action = #selector(changeStyle(_:))
    popup.toolTip = label
    popup.setAccessibilityLabel(label)
    popup.widthAnchor.constraint(equalToConstant: 54).isActive = true
  }
  private func icon(_ symbol: String, _ title: String, action: Selector) -> NSButton {
    let button = NSButton(
      image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(),
      target: self, action: action)
    button.bezelStyle = .accessoryBarAction
    button.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    button.contentTintColor = .labelColor
    button.toolTip = title
    button.setAccessibilityLabel(title)
    button.focusRingType = .exterior
    button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return button
  }
  private func refresh() {
    needsDisplay = true
    toolbar.isHidden = document.selection.isEmpty
    if case .selection = drag { toolbar.isHidden = true }
    captureHint.isHidden = !document.selection.isEmpty
    captureHint.frame = CGRect(
      x: max(12, (bounds.width - 360) / 2), y: 60, width: min(360, bounds.width - 24), height: 68)
    undoButton.isEnabled = history.canUndo
    redoButton.isEnabled = history.canRedo
    for (value, button) in toolButtons { button.state = value == tool ? .on : .off }
    for (index, button) in colorButtons.enumerated() {
      button.state = palette[index] == color ? .on : .off
      button.needsDisplay = true
    }
    let activeTool = selectedObject?.tool ?? tool
    let hasTarget = activeTool != .select
    colorsRow.isHidden = !hasTarget || activeTool == .blur
    toolLabel.isHidden = !hasTarget
    selectionHint.isHidden = hasTarget
    toolLabel.stringValue = activeTool.title
    widthRow.isHidden = ![.pen, .line, .arrow, .rectangle, .ellipse, .marker].contains(activeTool)
    fontRow.isHidden = ![.text, .number].contains(activeTool)
    if let rect = ImageGeometry(
      pointSize: bounds.size, pixelSize: CGSize(width: image.width, height: image.height)
    ).pixelRect(for: document.selection) {
      sizeLabel.stringValue = "\(Int(rect.width)) × \(Int(rect.height))"
    }
    let w = min(620, bounds.width - 24)
    let h: CGFloat = 90
    var y = document.selection.minY - h - 12
    if y < 12 { y = document.selection.maxY + 12 }
    if y + h > bounds.height - 12 { y = 12 }
    toolbar.frame = CGRect(
      x: max(12, min(document.selection.midX - w / 2, bounds.width - w - 12)), y: y, width: w,
      height: h)
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let c = NSGraphicsContext.current?.cgContext else { return }
    c.draw(image, in: bounds)
    c.saveGState()
    c.clip(to: document.selection)
    ImageRenderer.draw(
      document.annotations.filter { $0.id != editingID }, in: c,
      blurredImage: blurredImage, pointSize: bounds.size)
    c.restoreGState()
    c.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
    let region = document.selection
    if region.isEmpty {
      c.fill(bounds)
    } else {
      let shade = CGMutablePath()
      shade.addRect(bounds)
      shade.addRect(region)
      c.addPath(shade)
      c.fillPath(using: .evenOdd)
      c.setStrokeColor(NSColor.white.cgColor)
      c.setLineWidth(1)
      c.stroke(region)
      drawHandles(region, color: .white, all: true, in: c)
      if let object = selectedObject {
        c.setStrokeColor(NSColor.controlAccentColor.cgColor)
        c.setLineDash(phase: 0, lengths: [4, 3])
        c.stroke(object.bounds.insetBy(dx: -3, dy: -3))
        c.setLineDash(phase: 0, lengths: [])
        drawHandles(object.bounds, color: .controlAccentColor, all: false, in: c)
      }
    }
  }
  private var selectedObject: Annotation? { document.annotations.first { $0.id == selected } }
  private func handles(_ rect: CGRect, all: Bool) -> [CGPoint] {
    let corners = [
      CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
    ]
    return all
      ? corners + [
        CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
        CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY),
      ] : corners
  }
  private func handle(at point: CGPoint, rect: CGRect, all: Bool) -> Int? {
    handles(rect, all: all).firstIndex { hypot($0.x - point.x, $0.y - point.y) < 8 }
  }
  private func drawHandles(_ rect: CGRect, color: NSColor, all: Bool, in c: CGContext) {
    c.setFillColor(color.cgColor)
    for p in handles(rect, all: all) { c.fill(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)) }
  }
  private func clamp(_ p: CGPoint) -> CGPoint {
    CGPoint(x: max(0, min(bounds.width, p.x)), y: max(0, min(bounds.height, p.y)))
  }
  private func box(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }
  private func resized(_ rect: CGRect, handle: Int, to p: CGPoint) -> CGRect {
    var x0 = rect.minX
    var x1 = rect.maxX
    var y0 = rect.minY
    var y1 = rect.maxY
    if [0, 3, 7].contains(handle) { x0 = min(p.x, x1 - 2) }
    if [1, 2, 5].contains(handle) { x1 = max(p.x, x0 + 2) }
    if [0, 1, 4].contains(handle) { y0 = min(p.y, y1 - 2) }
    if [2, 3, 6].contains(handle) { y1 = max(p.y, y0 + 2) }
    return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }
  override func mouseDown(with event: NSEvent) {
    guard !panelOpen else { return }
    commitText()
    window?.makeKey()
    window?.makeFirstResponder(self)
    onClaimScreen?()
    let p = clamp(convert(event.locationInWindow, from: nil))
    dragStart = p
    dragDocument = document
    if document.selection.isEmpty {
      drag = .selection
      return
    }
    if let i = document.annotations.firstIndex(where: { $0.id == selected }),
      let h = handle(at: p, rect: document.annotations[i].bounds, all: false), tool == .select
    {
      drag = .resizeObject(i, h)
      return
    }
    if let h = handle(at: p, rect: document.selection, all: true) {
      drag = .resizeRegion(h)
      return
    }
    if spaceDown && document.selection.contains(p) {
      drag = .moveRegion
      return
    }
    guard document.selection.contains(p) else {
      selected = nil
      refresh()
      return
    }
    if tool == .select {
      if let i = document.annotations.lastIndex(where: { $0.tool == .conceal && $0.contains(p) })
        ?? document.annotations.lastIndex(where: { $0.tool != .blur && $0.contains(p) })
        ?? document.annotations.lastIndex(where: { $0.tool == .blur && $0.contains(p) })
      {
        selected = document.annotations[i].id
        if event.clickCount == 2 && document.annotations[i].tool == .text {
          beginText(at: p, index: i)
          return
        }
        drag = .moveObject(i)
        syncStyleFromSelection()
      } else {
        selected = nil
        drag = .moveRegion
      }
      refresh()
      return
    }
    selected = nil
    if tool == .text {
      beginText(at: p, index: nil)
      return
    }
    var object = Annotation(tool: tool, points: [p, p])
    object.color = color
    object.width = lineWidth
    object.fontSize = fontSize
    if tool == .number {
      object.points = [p]
      object.number =
        (document.annotations.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1
    }
    document.annotations.append(object)
    drag = .drawing(document.annotations.count - 1)
    refresh()
  }
  override func mouseDragged(with event: NSEvent) {
    let p = clamp(convert(event.locationInWindow, from: nil))
    let delta = CGSize(width: p.x - dragStart.x, height: p.y - dragStart.y)
    switch drag {
    case .none: return
    case .selection: document.selection = box(dragStart, p)
    case .moveRegion:
      let old = dragDocument.selection
      document.selection = CGRect(
        x: max(0, min(bounds.width - old.width, old.minX + delta.width)),
        y: max(0, min(bounds.height - old.height, old.minY + delta.height)), width: old.width,
        height: old.height)
    case .resizeRegion(let h):
      document.selection = resized(dragDocument.selection, handle: h, to: p).intersection(bounds)
    case .drawing(let i):
      guard document.annotations.indices.contains(i) else {
        drag = .none
        return
      }
      if document.annotations[i].tool == .pen || document.annotations[i].tool == .marker {
        document.annotations[i].points.append(p)
      } else if document.annotations[i].tool != .number {
        document.annotations[i].points = [dragStart, p]
      }
    case .moveObject(let i):
      guard document.annotations.indices.contains(i), dragDocument.annotations.indices.contains(i)
      else {
        drag = .none
        return
      }
      document.annotations[i] = dragDocument.annotations[i]
      document.annotations[i].move(by: delta)
    case .resizeObject(let i, let h):
      guard document.annotations.indices.contains(i), dragDocument.annotations.indices.contains(i)
      else {
        drag = .none
        return
      }
      document.annotations[i] = dragDocument.annotations[i]
      document.annotations[i].resize(
        to: resized(dragDocument.annotations[i].bounds, handle: h, to: p))
    }
    refresh()
  }
  override func mouseUp(with event: NSEvent) { finishDrag() }
  private func finishDrag() {
    guard case .none = drag else {
      if document.selection.width < 2 || document.selection.height < 2 { document = dragDocument }
      history.commit(document)
      drag = .none
      refresh()
      return
    }
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      cancelCapture()
      return
    }
    if event.keyCode == 49 {
      spaceDown = true
      NSCursor.openHand.set()
      return
    }
    if event.keyCode == 51 || event.keyCode == 117 {
      finishDrag()
      if let selected {
        document.annotations.removeAll { $0.id == selected }
        self.selected = nil
        history.commit(document)
        refresh()
      }
      return
    }
    super.keyDown(with: event)
  }
  override func keyUp(with event: NSEvent) {
    if event.keyCode == 49 {
      spaceDown = false
      NSCursor.crosshair.set()
    } else {
      super.keyUp(with: event)
    }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command) else {
      return super.performKeyEquivalent(with: event)
    }
    if textEditor != nil && [6, 7, 8, 9, 0].contains(event.keyCode) {
      return super.performKeyEquivalent(with: event)
    }
    switch event.keyCode {
    case 8:
      copyImage()
      return true
    case 1:
      saveImage()
      return true
    case 6:
      event.modifierFlags.contains(.shift) ? redoAction() : undoAction()
      return true
    default: return super.performKeyEquivalent(with: event)
    }
  }
  override func cancelOperation(_ sender: Any?) { cancelCapture() }
  @objc private func cancelCapture() { onCancel?() }
  @objc private func chooseTool(_ sender: NSButton) {
    finishDrag()
    commitText()
    let nextTool = Tool.allCases[sender.tag]
    if nextTool == .blur && blurredImage == nil {
      do {
        blurredImage = try ImageRenderer.blurredImage(image, pointSize: bounds.size)
      } catch {
        refresh()
        showError(error.localizedDescription)
        return
      }
    }
    tool = nextTool
    selected = nil
    window?.makeFirstResponder(self)
    refresh()
  }
  private func syncStyleFromSelection() {
    guard let object = selectedObject else { return }
    color = object.color
    lineWidth = object.width
    fontSize = object.fontSize
    widths.selectItem(withTitle: String(Int(lineWidth)))
    fonts.selectItem(withTitle: String(Int(fontSize)))
  }
  @objc private func chooseColor(_ sender: NSButton) {
    commitText()
    color = palette[sender.tag]
    applyStyle(colorOnly: true)
  }
  @objc private func changeStyle(_ sender: NSPopUpButton) {
    commitText()
    if sender === widths { lineWidth = CGFloat(Double(widths.titleOfSelectedItem ?? "3") ?? 3) }
    if sender === fonts { fontSize = CGFloat(Double(fonts.titleOfSelectedItem ?? "24") ?? 24) }
    applyStyle(colorOnly: false)
  }
  private func applyStyle(colorOnly: Bool) {
    if let i = document.annotations.firstIndex(where: { $0.id == selected }) {
      document.annotations[i].color = color
      if !colorOnly {
        document.annotations[i].width = lineWidth
        document.annotations[i].fontSize = fontSize
      }
      history.commit(document)
    }
    let defaults = UserDefaults.standard
    defaults.set(try? JSONEncoder().encode(color), forKey: "drawing.color")
    defaults.set(Double(lineWidth), forKey: "drawing.width")
    defaults.set(Double(fontSize), forKey: "drawing.font")
    window?.makeFirstResponder(self)
    refresh()
  }
  @objc private func undoAction() {
    finishDrag()
    commitText()
    history.undo()
    document = history.current
    selected = nil
    refresh()
  }
  @objc private func redoAction() {
    finishDrag()
    commitText()
    history.redo()
    document = history.current
    selected = nil
    refresh()
  }
  private func beginText(at p: CGPoint, index: Int?) {
    let object: Annotation
    if let index {
      object = document.annotations[index]
    } else {
      var a = Annotation(tool: .text, points: [p])
      a.color = color
      a.fontSize = fontSize
      document.annotations.append(a)
      object = a
    }
    editingID = object.id
    selected = object.id
    let editorWidth = min(360, bounds.width)
    let editorHeight = min(100, bounds.height)
    let scroll = NSScrollView(
      frame: CGRect(
        x: max(0, min(object.bounds.minX, bounds.width - editorWidth)),
        y: max(0, min(object.bounds.minY, bounds.height - editorHeight)), width: editorWidth,
        height: editorHeight))
    scroll.borderType = .lineBorder
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = true
    scroll.backgroundColor = .textBackgroundColor
    let editor = CaptureTextView(frame: CGRect(origin: .zero, size: scroll.contentSize))
    editor.isRichText = false
    editor.allowsUndo = true
    editor.font = .systemFont(ofSize: object.fontSize, weight: .medium)
    editor.textColor = .textColor
    editor.string = object.text
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.textContainer?.widthTracksTextView = true
    editor.textContainerInset = NSSize(width: 6, height: 6)
    editor.finish = { [weak self] in self?.commitText() }
    editor.cancel = { [weak self] in self?.onCancel?() }
    scroll.documentView = editor
    textEditor = editor
    textContainerView = scroll
    addSubview(scroll)
    window?.makeFirstResponder(editor)
    editor.selectAll(nil)
    refresh()
  }
  private func commitText() {
    guard let editor = textEditor, let id = editingID else { return }
    if let i = document.annotations.firstIndex(where: { $0.id == id }) {
      if editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        document.annotations.remove(at: i)
        selected = nil
      } else {
        document.annotations[i].text = editor.string
      }
    }
    textContainerView?.removeFromSuperview()
    textContainerView = nil
    textEditor = nil
    editingID = nil
    history.commit(document)
    window?.makeFirstResponder(self)
    refresh()
  }
  @objc private func copyImage() {
    guard !panelOpen else { return }
    finishDrag()
    commitText()
    do {
      let result = try ImageRenderer.render(
        image: image, pointSize: bounds.size, document: document)
      let item = NSPasteboardItem()
      item.setData(try ImageRenderer.png(result), forType: .png)
      if let tiff = NSBitmapImageRep(cgImage: result).tiffRepresentation {
        item.setData(tiff, forType: .tiff)
      }
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.writeObjects([item]) else {
        throw NSError(
          domain: "Screenshot", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Не удалось скопировать изображение."])
      }
      onCancel?()
    } catch { showError(error.localizedDescription) }
  }
  @objc private func saveImage() {
    guard !panelOpen, let window else { return }
    finishDrag()
    commitText()
    let data: Data
    do {
      data = try ImageRenderer.png(
        ImageRenderer.render(image: image, pointSize: bounds.size, document: document))
    } catch {
      showError(error.localizedDescription)
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.canCreateDirectories = true
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    panel.nameFieldStringValue = "Kadrin_\(formatter.string(from:Date())).png"
    if let path = UserDefaults.standard.string(forKey: "save.folder") {
      panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
    }
    panelOpen = true
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      self.panelOpen = false
      guard response == .OK, let url = panel.url else { return }
      do {
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "save.folder")
        self.onCancel?()
      } catch { self.showError(error.localizedDescription) }
    }
  }
  private func showError(_ message: String) {
    guard let window else { return }
    let alert = NSAlert()
    alert.messageText = "Не удалось завершить действие"
    alert.informativeText = message
    panelOpen = true
    alert.beginSheetModal(for: window) { [weak self] _ in self?.panelOpen = false }
  }
}
