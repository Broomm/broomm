import Cocoa
import Darwin

// Native integration check, using disposable AppKit writers under its own root.
// Compile together with macos/Runner/SessionRecovery.swift; never owner storage.
@main
struct SessionRecoveryCheck {
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try condition() == false { throw NSError(domain: "BroommRecoveryTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  }
  static func until(_ observation: () throws -> Bool) throws {
    let deadline = Date(timeIntervalSinceNow: 10)
    while Date() < deadline {
      if try observation() { return }
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    throw NSError(domain: "BroommRecoveryTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Native recovery observation timed out"])
  }
  static func launch(_ app: URL, lock: String, mode: String) throws -> NSRunningApplication {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.createsNewApplicationInstance = true
    config.arguments = [lock, mode]
    var result: NSRunningApplication?, failure: Error?
    NSWorkspace.shared.openApplication(at: app, configuration: config) { value, error in result = value; failure = error }
    try until { result != nil || failure != nil }
    if let failure = failure { throw failure }
    return result!
  }
  static func main() {
    do { try run() } catch {
      FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
      exit(1)
    }
  }
  static func run() throws {
    guard CommandLine.arguments.count == 2 else { fatalError("Provide the private fixture root") }
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
    let lock = root + "/writer.lock"
    let appURL = URL(fileURLWithPath: root + "/emulators/Writer.app")
    let recovery = BroommSessionRecovery()
    try check(try recovery.inspect(root: root) == nil, "An absent writer must be empty")
    let stubborn = try launch(appURL, lock: lock, mode: "ignore")
    defer { if !stubborn.isTerminated { stubborn.forceTerminate() } }
    var observation: [String: Any]?
    try until { observation = try recovery.inspect(root: root); return observation?["status"] as? String == "emulator" }
    let token = observation!["token"] as! String
    try check((observation!["pid"] as! NSNumber).int32Value == stubborn.processIdentifier, "Recover the kernel lock owner")
    try recovery.control(token: token, action: "stop")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    try check(!stubborn.isTerminated, "Fixture must refuse normal Quit")
    try recovery.control(token: token, action: "force")
    try until { try stubborn.isTerminated && recovery.inspect(root: root) == nil }
    let normal = try launch(appURL, lock: lock, mode: "normal")
    defer { if !normal.isTerminated { normal.forceTerminate() } }
    try until { observation = try recovery.inspect(root: root); return observation?["status"] as? String == "emulator" }
    let next = observation!["token"] as! String
    try check(next != token, "A different writer must receive a new identity")
    var staleRejected = false
    do { try recovery.control(token: token, action: "force") } catch { staleRejected = true }
    try check(staleRejected && !normal.isTerminated, "A stale token cannot signal the replacement")
    try recovery.control(token: next, action: "stop")
    try until { try normal.isTerminated && recovery.inspect(root: root) == nil }
    // Broomm uses Process.start, not LaunchServices. Such applications may
    // legitimately have no AppKit launchDate (observed with pinned Ryubing).
    let direct = Process()
    direct.executableURL = appURL.appendingPathComponent("Contents/MacOS/Writer")
    direct.arguments = [lock, "ignore"]
    try direct.run()
    defer { if direct.isRunning { direct.terminate() } }
    try until { observation = try recovery.inspect(root: root); return observation?["status"] as? String == "emulator" }
    try check((observation!["pid"] as! NSNumber).int32Value == direct.processIdentifier, "Direct launch must identify its actual writer")
    try recovery.control(token: observation!["token"] as! String, action: "force")
    try until { try !direct.isRunning && recovery.inspect(root: root) == nil }
    let original = try Data(contentsOf: URL(fileURLWithPath: lock))
    try FileManager.default.removeItem(atPath: lock)
    let sentinel = root + "/preserved-save"
    try "retained-progress".write(toFile: sentinel, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(atPath: lock, withDestinationPath: sentinel)
    var linkRejected = false
    do { _ = try recovery.inspect(root: root) } catch { linkRejected = true }
    try check(linkRejected, "Linked lock must be unknown, not empty")
    try check(try String(contentsOfFile: sentinel, encoding: .utf8) == "retained-progress", "Recovery must preserve save data")
    try FileManager.default.removeItem(atPath: lock)
    try original.write(to: URL(fileURLWithPath: lock))
    print("PASS: LaunchServices and directly launched AppKit writers, normal quit, refused quit then force, stale identity rejection, released lock, linked-lock refusal and retained progress")
  }
}
