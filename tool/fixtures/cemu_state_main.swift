import Cocoa
import Foundation

@main struct CemuStateCheck {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else { throw NSError(domain: "cemu-test", code: 1) }
    let path = CommandLine.arguments[1]
    guard let target = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any] else {
      throw NSError(domain: "cemu-test", code: 2)
    }
    let recovery = BroommSessionRecovery()
    guard try recovery.cemuState(target)["paused"] as? Bool == false else { throw NSError(domain: "cemu-test", code: 3) }
    var wrong = target
    wrong["seconds"] = (target["seconds"] as! Int) + 1
    do { _ = try recovery.cemuState(wrong); throw NSError(domain: "cemu-test-false-admission", code: 4) }
    catch let error as NSError where error.domain == "app.broomm.session-recovery" { }
    var pause = target
    pause["paused"] = true
    var resume = target
    resume["paused"] = false
    defer { _ = try? recovery.cemuState(resume) }
    guard try recovery.cemuState(pause)["paused"] as? Bool == true else { throw NSError(domain: "cemu-test", code: 5) }
    guard try recovery.cemuState(target)["paused"] as? Bool == true else { throw NSError(domain: "cemu-test", code: 6) }
    pause["paused"] = false
    guard try recovery.cemuState(pause)["paused"] as? Bool == false else { throw NSError(domain: "cemu-test", code: 7) }
    print("Confirmed real Cemu kernel pause/resume and rejected changed birth identity.")
  }
}
