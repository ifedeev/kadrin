import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum ImageRenderer {
  private static let blurContext = CIContext()
  public static func blurredImage(_ image: CGImage, pointSize: CGSize) throws -> CGImage {
    guard pointSize.width > 0, pointSize.height > 0 else {
      throw failure("Не удалось определить размер снимка.")
    }
    let source = CIImage(cgImage: image)
    let blurred = source.clampedToExtent().applyingFilter(
      "CIGaussianBlur", parameters: [kCIInputRadiusKey: 12 * CGFloat(image.width) / pointSize.width]
    )
    guard let result = blurContext.createCGImage(blurred, from: source.extent) else {
      throw failure("Не удалось размыть снимок. Попробуйте повторить захват.")
    }
    return result
  }
  public static func render(image: CGImage, pointSize: CGSize, document: EditorDocument) throws
    -> CGImage
  {
    let geometry = ImageGeometry(
      pointSize: pointSize, pixelSize: CGSize(width: image.width, height: image.height))
    guard let crop = geometry.pixelRect(for: document.selection) else {
      throw failure("Сначала выделите область.")
    }
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw failure("Недостаточно памяти для изображения.") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.scaleBy(
      x: CGFloat(image.width) / pointSize.width, y: CGFloat(image.height) / pointSize.height)
    let blurred =
      document.annotations.contains { $0.tool == .blur }
      ? try blurredImage(image, pointSize: pointSize) : nil
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw(document.annotations, in: context, blurredImage: blurred, pointSize: pointSize)
    NSGraphicsContext.restoreGraphicsState()
    guard let result = context.makeImage()?.cropping(to: crop) else {
      throw failure("Не удалось сформировать изображение.")
    }
    return result
  }
  public static func png(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { throw failure("Не удалось создать PNG.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw failure("Не удалось записать PNG.") }
    return data as Data
  }
  public static func draw(
    _ annotations: [Annotation], in context: CGContext, blurredImage: CGImage?, pointSize: CGSize
  ) {
    let regions = annotations.filter { $0.tool == .blur && !$0.bounds.isEmpty }.map(\.bounds)
    if let blurredImage, !regions.isEmpty {
      context.saveGState()
      context.beginPath()
      context.addRects(regions)
      context.clip()
      context.draw(blurredImage, in: CGRect(origin: .zero, size: pointSize))
      context.restoreGState()
    }
    for annotation in annotations where annotation.tool != .conceal && annotation.tool != .blur {
      draw(annotation, in: context)
    }
    // Concealment must remain opaque even when later marks overlap it.
    for annotation in annotations where annotation.tool == .conceal {
      draw(annotation, in: context)
    }
  }
  private static func draw(_ a: Annotation, in c: CGContext) {
    guard let start = a.points.first else { return }
    c.saveGState()
    defer { c.restoreGState() }
    c.setStrokeColor(a.color.nsColor.cgColor)
    c.setFillColor(a.color.nsColor.cgColor)
    c.setLineWidth(a.width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    let end = a.points.last ?? start
    switch a.tool {
    case .select, .blur: break
    case .pen, .marker, .line, .arrow:
      if a.tool == .marker {
        c.setAlpha(0.3)
        c.setLineWidth(max(12, a.width * 4))
        c.setLineCap(.butt)
      }
      c.beginPath()
      c.move(to: start)
      if a.points.count == 1 {
        c.addLine(to: CGPoint(x: start.x + 0.1, y: start.y))
      } else {
        for point in a.points.dropFirst() { c.addLine(to: point) }
      }
      c.strokePath()
      if a.tool == .arrow {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, a.width * 4)
        c.move(
          to: CGPoint(x: end.x - length * cos(angle - 0.5), y: end.y - length * sin(angle - 0.5)))
        c.addLine(to: end)
        c.addLine(
          to: CGPoint(x: end.x - length * cos(angle + 0.5), y: end.y - length * sin(angle + 0.5)))
        c.strokePath()
      }
    case .rectangle: c.stroke(a.bounds)
    case .ellipse: c.strokeEllipse(in: a.bounds)
    case .conceal:
      c.setShouldAntialias(false)
      c.setAlpha(1)
      c.setBlendMode(.copy)
      c.fill(a.bounds)
    case .text:
      (a.text as NSString).draw(
        at: start,
        withAttributes: [
          .font: NSFont.systemFont(ofSize: a.fontSize, weight: .medium),
          .foregroundColor: a.color.nsColor,
        ])
    case .number:
      c.fillEllipse(in: a.bounds)
      let text = "\(a.number)" as NSString
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: a.fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
      ]
      let size = text.size(withAttributes: attributes)
      text.draw(
        at: CGPoint(x: start.x - size.width / 2, y: start.y - size.height / 2),
        withAttributes: attributes)
    }
  }
  private static func failure(_ message: String) -> NSError {
    NSError(domain: "Screenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
