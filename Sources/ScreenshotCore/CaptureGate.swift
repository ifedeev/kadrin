import Foundation

public struct CaptureGate {
  private var token: UUID?
  public init() {}
  public mutating func begin() -> UUID? {
    guard token == nil else { return nil }
    let value = UUID()
    token = value
    return value
  }
  public func accepts(_ value: UUID) -> Bool { token == value }
  public mutating func cancel() { token = nil }
}
