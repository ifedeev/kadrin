import AppKit
import XCTest

@testable import ScreenshotCore

final class BlurTests: XCTestCase {
  private let size = CGSize(width: 120, height: 100)
  private var blur: Annotation {
    Annotation(tool: .blur, points: [CGPoint(x: 20, y: 60), CGPoint(x: 80, y: 90)])
  }
  private func source(scale: Int = 1) throws -> CGImage {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 120 * scale, height: 100 * scale, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setFillColor(NSColor.blue.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    for x in stride(from: 0, to: 120, by: 4) {
      context.setFillColor((x % 8 == 0 ? NSColor.black : NSColor.white).cgColor)
      context.fill(CGRect(x: x, y: 50, width: 4, height: 50))
    }
    return try XCTUnwrap(context.makeImage())
  }
  private func sample(_ image: CGImage, _ x: Int, _ y: Int) throws -> NSColor {
    try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
  }
  func testBlurChangesOnlyItsRegionAtBothDisplayScalesAndCropsCorrectly() throws {
    var intensities: [CGFloat] = []
    for scale in [1, 2] {
      let image = try source(scale: scale)
      var doc = EditorDocument(selection: CGRect(origin: .zero, size: size), annotations: [blur])
      let result = try ImageRenderer.render(image: image, pointSize: size, document: doc)
      let softened = try sample(result, 50 * scale, 20 * scale)
      XCTAssertGreaterThan(softened.redComponent, 0.2)
      XCTAssertLessThan(softened.redComponent, 0.9)
      XCTAssertEqual(softened.alphaComponent, 1, accuracy: 0.01)
      intensities.append(softened.redComponent)
      for (x, y) in [(10, 20), (50, 75), (95, 10)] {
        let actual = try sample(result, x * scale, y * scale)
        let original = try sample(image, x * scale, y * scale)
        XCTAssertEqual(actual.redComponent, original.redComponent, accuracy: 0.01)
        XCTAssertEqual(actual.blueComponent, original.blueComponent, accuracy: 0.01)
      }
      doc.selection = CGRect(x: 40, y: 70, width: 20, height: 20)
      let cropped = try ImageRenderer.render(image: image, pointSize: size, document: doc)
      XCTAssertEqual(cropped.width, 20 * scale)
      XCTAssertEqual(cropped.height, 20 * scale)
      XCTAssertEqual(
        try sample(cropped, 10 * scale, 10 * scale).redComponent,
        softened.redComponent, accuracy: 0.01)
      let png = try ImageRenderer.png(cropped)
      let decoded = try XCTUnwrap(NSBitmapImageRep(data: png)?.cgImage)
      XCTAssertEqual(
        try sample(decoded, 10 * scale, 10 * scale).redComponent,
        softened.redComponent, accuracy: 0.01)
    }
    XCTAssertEqual(intensities[0], intensities[1], accuracy: 0.04)
  }
  func testPreviewAndExportShareBlurAndPreserveAnnotationsAndConcealment() throws {
    let image = try source()
    var line = Annotation(tool: .line, points: [CGPoint(x: 25, y: 75), CGPoint(x: 75, y: 75)])
    line.color = RGBA(red: 1, green: 0, blue: 0)
    line.width = 4
    var conceal = Annotation(
      tool: .conceal, points: [CGPoint(x: 40, y: 65), CGPoint(x: 60, y: 85)])
    conceal.color = RGBA(red: 0, green: 0, blue: 0)
    let annotations = [conceal, line, blur, blur]
    let result = try ImageRenderer.render(
      image: image, pointSize: size,
      document: EditorDocument(
        selection: CGRect(origin: .zero, size: size), annotations: annotations))
    XCTAssertEqual(try sample(result, 50, 25).redComponent, 0, accuracy: 0.01)
    let sharp = try ImageRenderer.render(
      image: image, pointSize: size,
      document: EditorDocument(selection: CGRect(origin: .zero, size: size), annotations: [line]))
    XCTAssertEqual(
      try sample(result, 30, 25).redComponent,
      try sample(sharp, 30, 25).redComponent, accuracy: 0.01)
    XCTAssertEqual(
      try sample(result, 30, 25).greenComponent,
      try sample(sharp, 30, 25).greenComponent, accuracy: 0.01)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 120, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(origin: .zero, size: size))
    ImageRenderer.draw(
      annotations, in: context,
      blurredImage: try ImageRenderer.blurredImage(image, pointSize: size), pointSize: size)
    let preview = try XCTUnwrap(context.makeImage())
    XCTAssertEqual(try ImageRenderer.png(preview), try ImageRenderer.png(result))
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent(".impeccable/review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try ImageRenderer.png(result).write(to: directory.appendingPathComponent("blur-render.png"))
  }
  func testBlurAtImageEdgesStaysOpaqueAndInvalidSizeFails() throws {
    let image = try source()
    let blurred = try ImageRenderer.blurredImage(image, pointSize: size)
    for (x, y) in [(0, 0), (119, 0), (0, 99), (119, 99)] {
      XCTAssertEqual(try sample(blurred, x, y).alphaComponent, 1, accuracy: 0.01)
    }
    XCTAssertThrowsError(try ImageRenderer.blurredImage(image, pointSize: .zero))
  }
  func testBlurCanMoveResizeAndUndoAsOneEdit() {
    var doc = EditorDocument(selection: CGRect(origin: .zero, size: size), annotations: [blur])
    let initial = doc
    var history = EditHistory(initial: doc)
    doc.annotations[0].move(by: CGSize(width: 5, height: -10))
    doc.annotations[0].resize(to: CGRect(x: 25, y: 50, width: 40, height: 20))
    XCTAssertTrue(doc.annotations[0].contains(CGPoint(x: 45, y: 60)))
    XCTAssertEqual(doc.annotations[0].bounds, CGRect(x: 25, y: 50, width: 40, height: 20))
    history.commit(doc)
    history.undo()
    XCTAssertEqual(history.current, initial)
    history.redo()
    XCTAssertEqual(history.current, doc)
  }
}
