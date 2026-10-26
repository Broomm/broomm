import Cocoa
import FlutterMacOS
import XCTest
import GameController
@testable import broomm

private class InputTestWindow: MainFlutterWindow {
  var events: [String] = []
  override func input(_ value: String) { events.append(value) }
}

class RunnerTests: XCTestCase {
  @MainActor
  func testGameControllerKeyboardShortcutEvents() throws {
    let window = InputTestWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    let controller = GCController.withExtendedGamepad()
    let pad = try XCTUnwrap(controller.extendedGamepad)
    window.observe(controller)
    let buttons: [(GCControllerButtonInput, String)] = [
      (pad.buttonY, "space"), (pad.buttonX, "search"),
      (try XCTUnwrap(pad.leftThumbstickButton), "caps"),
      (pad.leftShoulder, "caret-left"), (pad.rightShoulder, "caret-right"),
      (pad.buttonMenu, "home"), (pad.rightTrigger, "keyboard-enter"),
    ]
    for (button, action) in buttons {
      window.events.removeAll()
      button.setValue(1)
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
      button.setValue(0)
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
      XCTAssertEqual(window.events, [action])
    }
  }

  @MainActor
  func testHeldShiftWaitsForEveryControllerRelease() throws {
    let window = InputTestWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    let a = GCController.withExtendedGamepad(), b = GCController.withExtendedGamepad()
    window.observe(a); window.observe(b)
    let first = try XCTUnwrap(a.extendedGamepad).leftTrigger
    let second = try XCTUnwrap(b.extendedGamepad).leftTrigger
    for (button, value) in [(first, Float(1)), (second, Float(1)), (first, Float(0))] {
      button.setValue(value)
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    XCTAssertEqual(window.events, ["shift-down"])
    second.setValue(0)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    XCTAssertEqual(window.events, ["shift-down", "shift-up"])
  }
  func testArtworkKeyIsSeparateFromRomMSignIn() throws {
    let key = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let artwork = "sgdb-\(key)"
    defer {
      _ = try? BroommKeychain.perform(method: "delete", key: key, value: nil)
      _ = try? BroommKeychain.perform(method: "delete", key: artwork, value: nil)
    }
    _ = try BroommKeychain.perform(method: "write", key: key, value: "disposable-romm-token")
    _ = try BroommKeychain.perform(method: "write", key: artwork, value: "disposable-artwork-key")
    XCTAssertEqual(try BroommKeychain.perform(method: "read", key: artwork, value: nil), "disposable-artwork-key")
    _ = try BroommKeychain.perform(method: "delete", key: artwork, value: nil)
    XCTAssertNil(try BroommKeychain.perform(method: "read", key: artwork, value: nil))
    XCTAssertEqual(try BroommKeychain.perform(method: "read", key: key, value: nil), "disposable-romm-token")
    XCTAssertThrowsError(try BroommKeychain.perform(method: "read", key: "sgdb-../../bad", value: nil))
  }

  func testSecureSignInStorageKeepsProfilesSeparateAndSupportsRemoval() throws {
    let key = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let other = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    defer { _ = try? BroommKeychain.perform(method: "delete", key: key, value: nil) }
    XCTAssertNil(try BroommKeychain.perform(method: "read", key: key, value: nil))
    _ = try BroommKeychain.perform(method: "write", key: key, value: "disposable-test-token")
    XCTAssertEqual(try BroommKeychain.perform(method: "read", key: key, value: nil), "disposable-test-token")
    XCTAssertNil(try BroommKeychain.perform(method: "read", key: other, value: nil))
    _ = try BroommKeychain.perform(method: "write", key: key, value: "rotated-test-token")
    XCTAssertEqual(try BroommKeychain.perform(method: "read", key: key, value: nil), "rotated-test-token")
    _ = try BroommKeychain.perform(method: "delete", key: key, value: nil)
    XCTAssertNil(try BroommKeychain.perform(method: "read", key: key, value: nil))
    XCTAssertThrowsError(try BroommKeychain.perform(method: "write", key: "../bad-key", value: "fixture"))
  }

  @MainActor
  func testPairingAndReturnPreserveDecorationsAndUserFrame() throws {
    let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first)
    let original = window.frame
    defer { window.setFrame(original, display: true); window.present(overlay: false) }
    // Hosted runners can have a smaller screen than a developer's monitor.
    // Exercise a user frame which fits that screen: AppKit otherwise constrains
    // an oversized requested frame when ordering the window front.
    let visible = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
    let chosen = NSRect(x: visible.minX + 16, y: visible.minY + 16,
                        width: min(1100, visible.width - 32), height: min(760, visible.height - 32))
    window.setFrame(chosen, display: true)
    let accepted = window.frame
    XCTAssertEqual(accepted, chosen, "The fixture must fit the visible screen: \(visible)")
    for overlay in [true, true, false, true, false] {
      window.present(overlay: overlay)
      XCTAssertEqual(window.frame, accepted, "overlay=\(overlay), visible screen=\(visible)")
      XCTAssertTrue(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
      XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
      XCTAssertEqual(window.level, overlay ? .statusBar : .normal)
    }
  }
  @MainActor
  func testRepeatedHideAndForegroundWithFlutterRendering() throws {
    let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first)
    let frame = window.frame
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "FLTEnableImpeller") as? Bool, false)
    for _ in 0..<30 {
      window.orderOut(nil)
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      window.present(overlay: true)
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      window.present(overlay: false)
      XCTAssertEqual(window.frame, frame)
      XCTAssertTrue(window.isVisible)
    }
  }
}
