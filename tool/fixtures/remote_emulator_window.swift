import Cocoa
import Darwin

@main struct RemoteEmulatorWindowCheck {
  static func main() throws {
    let args = CommandLine.arguments
    guard args.count == 3 else { fatalError("Expected a target JSON file and touch/inspect.") }
    let target = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
    let app = try BroommSessionRecovery().emulatorWindowTarget(target)
    if args[2].hasPrefix("touch ") {
      guard let path = target["remoteSocket"] as? String, path.hasPrefix(NSTemporaryDirectory()),
            !path.contains("\0"), path.utf8.count < 104, args[2].utf8.count < 80 else { fatalError("Invalid private input socket.") }
      let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
      guard descriptor >= 0 else { fatalError("Could not open an input sender.") }
      defer { close(descriptor) }
      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
      withUnsafeMutableBytes(of: &address.sun_path) { destination in
        path.utf8CString.withUnsafeBytes { destination.copyBytes(from: $0) }
      }
      let report = Array(args[2].utf8)
      let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          sendto(descriptor, report, report.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard result == report.count else { fatalError("Private input delivery failed.") }
      return
    }
    guard args[2] == "inspect" else { fatalError("Unknown operation.") }
    let all = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
      .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }
    let windows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
      .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }
    let report: [String: Any] = ["hidden": app.isHidden, "windows": windows, "allWindows": all]
    print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
  }
}
