import AppKit
import XCTest

@testable import ScreenshotCore

final class EditorTests: XCTestCase {
  func testCropConvertsBottomLeftPointsToTopLeftPixelsAndClips() {
    let geometry = ImageGeometry(
      pointSize: CGSize(width: 100, height: 80), pixelSize: CGSize(width: 200, height: 160))
    XCTAssertEqual(
      geometry.pixelRect(for: CGRect(x: 10, y: 20, width: 30, height: 15)),
      CGRect(x: 20, y: 90, width: 60, height: 30))
    XCTAssertEqual(
      geometry.pixelRect(for: CGRect(x: -10, y: 70, width: 30, height: 30)),
      CGRect(x: 0, y: 0, width: 40, height: 20))
    XCTAssertNil(geometry.pixelRect(for: .zero))
    XCTAssertNil(geometry.pixelRect(for: CGRect(x: 200, y: 200, width: 10, height: 10)))
  }
  func testEachScreenUsesItsOwnScale() {
    let retina = ImageGeometry(
      pointSize: CGSize(width: 1440, height: 900), pixelSize: CGSize(width: 2880, height: 1800))
    let standard = ImageGeometry(
      pointSize: CGSize(width: 1920, height: 1080), pixelSize: CGSize(width: 1920, height: 1080))
    XCTAssertEqual(
      retina.pixelRect(for: CGRect(x: 0, y: 0, width: 100, height: 100))?.size,
      CGSize(width: 200, height: 200))
    XCTAssertEqual(
      standard.pixelRect(for: CGRect(x: 0, y: 0, width: 100, height: 100))?.size,
      CGSize(width: 100, height: 100))
  }
  func testUndoRedoAndNewEditDiscardRedo() {
    var history = EditHistory(
      initial: EditorDocument(selection: CGRect(x: 0, y: 0, width: 100, height: 80)))
    var drawing = history.current
    drawing.annotations = [
      Annotation(tool: .arrow, points: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)])
    ]
    history.commit(drawing)
    var cropped = drawing
    cropped.selection = CGRect(x: 15, y: 15, width: 20, height: 20)
    history.commit(cropped)
    XCTAssertEqual(history.current.annotations[0].points[0], CGPoint(x: 10, y: 20))
    history.undo()
    XCTAssertEqual(history.current, drawing)
    history.undo()
    XCTAssertTrue(history.current.annotations.isEmpty)
    history.redo()
    XCTAssertEqual(history.current, drawing)
    var replacement = drawing
    replacement.annotations[0].text = "changed"
    history.commit(replacement)
    history.redo()
    XCTAssertEqual(history.current, replacement)
  }
  func testObjectTransformsPreserveDirectionAndEditText() {
    var arrow = Annotation(tool: .arrow, points: [CGPoint(x: 30, y: 40), CGPoint(x: 10, y: 20)])
    arrow.resize(to: CGRect(x: 0, y: 0, width: 40, height: 60))
    XCTAssertEqual(arrow.points, [CGPoint(x: 40, y: 60), CGPoint(x: 0, y: 0)])
    arrow.move(by: CGSize(width: 5, height: -5))
    XCTAssertEqual(arrow.points[0], CGPoint(x: 45, y: 55))
  }
  func testLineHitTestingDoesNotSelectEmptyBoundingBox() {
    let line = Annotation(tool: .line, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
    XCTAssertTrue(line.contains(CGPoint(x: 50, y: 52)))
    XCTAssertFalse(line.contains(CGPoint(x: 10, y: 90)))
  }
  func testExportMaintainsVerticalOrientation() throws {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
    context.setFillColor(NSColor.blue.cgColor)
    context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
    let image = try XCTUnwrap(context.makeImage())
    let result = try ImageRenderer.render(
      image: image, pointSize: CGSize(width: 10, height: 10),
      document: EditorDocument(selection: CGRect(x: 0, y: 5, width: 10, height: 5)))
    let sample = try XCTUnwrap(
      CGContext(
        data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    sample.draw(result, in: CGRect(x: 0, y: 0, width: 20, height: 10))
    let bytes = try XCTUnwrap(sample.data).assumingMemoryBound(to: UInt8.self)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes + 400, count: 4)), [0, 0, 255, 255])
    XCTAssertThrowsError(
      try ImageRenderer.render(
        image: image, pointSize: CGSize(width: 10, height: 10), document: EditorDocument()))
  }
  func testExportCropsAtNativeResolutionAndRedactsLast() throws {
    let source = try XCTUnwrap(
      CGContext(
        data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    source.setFillColor(NSColor.white.cgColor)
    source.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
    let image = try XCTUnwrap(source.makeImage())
    var conceal = Annotation(
      tool: .conceal, points: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)])
    conceal.color = RGBA(red: 0, green: 0, blue: 0)
    var line = Annotation(tool: .line, points: [CGPoint(x: 10, y: 30), CGPoint(x: 30, y: 30)])
    line.color = RGBA(red: 1, green: 0, blue: 0)
    line.width = 8
    let doc = EditorDocument(
      selection: CGRect(x: 10, y: 20, width: 20, height: 20), annotations: [conceal, line])
    let result = try ImageRenderer.render(
      image: image, pointSize: CGSize(width: 100, height: 80), document: doc)
    XCTAssertEqual(result.width, 40)
    XCTAssertEqual(result.height, 40)
    let sample = try XCTUnwrap(
      CGContext(
        data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    sample.draw(result, in: CGRect(x: 0, y: 0, width: 40, height: 40))
    let bytes = try XCTUnwrap(sample.data).assumingMemoryBound(to: UInt8.self)
    let center = (20 * 40 + 20) * 4
    XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes + center, count: 4)), [0, 0, 0, 255])
    let png = try ImageRenderer.png(result)
    XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
  }
}
