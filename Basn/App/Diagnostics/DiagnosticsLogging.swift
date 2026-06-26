import BasnCore
import OSLog

enum DiagnosticsLogging {
  private static var isBootstrapped = false
  private static let logger = Logger(subsystem: BasnLog.subsystem, category: "Diagnostics")

  static func bootstrapIfNeeded() {
    guard !isBootstrapped else { return }
    logger.notice("Diagnostics logging initialized")
    isBootstrapped = true
  }
}
