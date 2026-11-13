import AppKit
import Darwin

private struct Snapshot: Codable, Equatable {
  let revision: UInt64
  let hidden: Bool
  let seconds: UInt64
  let microseconds: UInt64
  let nativeFullscreen: Bool
  let coversDisplay: Bool
  let active: Bool
}

@MainActor
private final class FixtureWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@MainActor
private final class FullscreenCheck: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let arguments = CommandLine.arguments
  private var window: NSWindow!
  private var timer: Timer?
  private var writer: Int32 = -1
  private var lastSnapshot: Snapshot?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let isTarget = arguments[1] != "launcher"
    let screen = NSScreen.main!
    let frame = arguments[1] == "borderless"
      ? screen.frame
      : NSRect(x: 80, y: 80, width: 700, height: 480)
    let style: NSWindow.StyleMask = arguments[1] == "borderless"
      ? .borderless : [.titled, .closable, .resizable]
    window = FixtureWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = arguments[1] == "ryubing"
      ? "Ryujinx - Fixture game (64-bit) (Paused)"
      : isTarget ? "Fixture game" : "Fixture launcher"
    if isTarget {
      window.collectionBehavior = [.fullScreenPrimary]
      window.delegate = self
    }
    if arguments[1] == "borderless" { window.setFrame(frame, display: true) }
    window.makeKeyAndOrderFront(nil)
    activate()
    if isTarget {
      writer = open(root.appendingPathComponent("writer.lock").path, O_CREAT | O_RDWR, 0o600)
      var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
      guard writer >= 0, fcntl(writer, F_SETLK, &lock) == 0 else { exit(2) }
      broomm_macos_window_observe()
      let launcher = pid_t(arguments[3])!
      timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.sample(root, launcher: launcher) }
      }
      if arguments[1] == "fullscreen" || arguments[1] == "recreated" || arguments[1] == "ryubing" {
        window.toggleFullScreen(nil)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 50) { NSApp.terminate(nil) }
    } else {
      Task {
        do {
          try await run(root, mode: arguments[3])
          exit(0)
        } catch {
          FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
          exit(1)
        }
      }
    }
  }

  private func activate() {
    if #available(macOS 14.0, *) { NSApp.activate() }
    else { NSApp.activate(ignoringOtherApps: true) }
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    guard arguments[1] == "recreated", notification.object as? NSWindow === window else { return }
    DispatchQueue.main.async {
      let previous = self.window!
      let replacement = FixtureWindow(contentRect: previous.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      replacement.isReleasedWhenClosed = false
      replacement.collectionBehavior = [.fullScreenPrimary]
      replacement.delegate = self
      self.window = replacement
      replacement.makeKeyAndOrderFront(nil)
      previous.close()
    }
  }

  private func sample(_ root: URL, launcher: pid_t) {
    let enter = root.appendingPathComponent("enter-fullscreen")
    if FileManager.default.fileExists(atPath: enter.path) {
      try? FileManager.default.removeItem(at: enter)
      window.toggleFullScreen(nil)
    }
    if arguments[1] == "ryubing" {
      var paused: Int32 = -1
      let game = broomm_macos_ryubing_window(&paused)
      if paused == 1 { broomm_macos_window_tick(game, launcher, false) }
    } else {
      broomm_macos_window_tick(Unmanaged.passUnretained(window).toOpaque(), launcher, false)
    }
    let ack = broomm_macos_window_status()
    let state = Snapshot(
      revision: ack.revision, hidden: NSApp.isHidden, seconds: ack.seconds,
      microseconds: ack.microseconds, nativeFullscreen: window.styleMask.contains(.fullScreen),
      coversDisplay: window.screen?.frame == window.frame, active: NSApp.isActive)
    if state != lastSnapshot {
      try? JSONEncoder().encode(state).write(to: root.appendingPathComponent("status.json"), options: .atomic)
      lastSnapshot = state
    }
  }

  private func wait(_ description: String, _ ready: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 7
    while ProcessInfo.processInfo.systemUptime < deadline {
      if ready() { return }
      try await Task.sleep(nanoseconds: 25_000_000)
    }
    throw NSError(domain: "FullscreenCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
  }

  private func presentLauncher() {
    activate()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func run(_ fixture: URL, mode: String) async throws {
    let target = fixture.appendingPathComponent("Emulator.app")
    let recovery = BroommSessionRecovery()
    let root = fixture.appendingPathComponent(mode, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let command = root.appendingPathComponent("command.txt")
    let snapshot = root.appendingPathComponent("status.json")
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.arguments = [mode, root.path, String(getpid())]
    config.environment = ["BROOMM_MAC_WINDOW_COMMAND": command.path]
    let app = try await NSWorkspace.shared.openApplication(at: target, configuration: config)
    defer { if !app.isTerminated { app.terminate() } }
    func read() -> Snapshot? {
      guard let data = try? Data(contentsOf: snapshot) else { return nil }
      return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
    func send(_ revision: Int, menu: Bool) throws {
      try "\(app.processIdentifier) \(revision) \(menu ? 1 : 0)\n"
        .write(to: command, atomically: true, encoding: .utf8)
    }
    try await wait("\(mode) fixture never opened") {
      guard let state = read() else { return false }
      switch mode {
      case "windowed": return state.active && !state.nativeFullscreen && !state.coversDisplay
      case "borderless": return state.active && !state.nativeFullscreen && state.coversDisplay
      default: return state.active && state.nativeFullscreen
      }
    }
    let state = read()!
    let identity: [String: Any] = [
      "pid": NSNumber(value: app.processIdentifier), "seconds": NSNumber(value: state.seconds),
      "microseconds": NSNumber(value: state.microseconds),
      "executable": target.appendingPathComponent("Contents/MacOS/check").path,
      "writer": root.appendingPathComponent("writer.lock").path,
    ]
    var invalidIdentity = identity
    invalidIdentity["seconds"] = NSNumber(value: state.seconds - 1)
    if (try? recovery.emulatorWindowTarget(invalidIdentity)) != nil {
      throw NSError(domain: "FullscreenCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Accepted a stale process birth"])
    }
    var menu = 1
    if mode == "windowed" {
      try send(1, menu: true)
      try await wait("windowed menu must keep the emulator visible") {
        read()?.revision == 1 && !app.isHidden
      }
      try Data().write(to: root.appendingPathComponent("enter-fullscreen"), options: .atomic)
      try await wait("windowed fixture did not enter fullscreen during play") {
        read()?.nativeFullscreen == true
      }
      menu = 2
    }
    for _ in 0..<(mode == "fullscreen" ? 2 : 1) {
      try send(menu, menu: true)
      try await wait("\(mode) did not hide for the menu") {
        read()?.revision == UInt64(menu) && read()?.nativeFullscreen == false && app.isHidden
      }
      presentLauncher()
      try await wait("launcher did not become key on its Space") {
        NSApp.isActive && window.isKeyWindow && window.isOnActiveSpace
      }
      let verifiedApp = try recovery.emulatorWindowTarget(identity)
      if #available(macOS 14.0, *) { NSApp.yieldActivation(to: verifiedApp) }
      try send(menu + 1, menu: false)
      try await wait("\(mode) did not resume in the same fullscreen mode") {
        guard let state = read() else { return false }
        let restored = mode == "borderless"
          ? !state.nativeFullscreen && state.coversDisplay
          : state.nativeFullscreen
        return state.revision == UInt64(menu + 1) && !state.hidden && state.active && restored
      }
      window.orderOut(nil)
      menu += 2
    }
    // Finish on the launcher's Space so the next fixture starts on the
    // desktop and does not inherit a disappearing fullscreen Space.
    try send(menu, menu: true)
    try await wait("fixture did not leave fullscreen before cleanup") {
      read()?.revision == UInt64(menu) && app.isHidden
    }
    presentLauncher()
    app.terminate()
    try await wait("\(mode) fixture did not quit") { app.isTerminated }
    print("PASS \(mode): menu foreground, original fullscreen restored, stale birth rejected")
  }
}

@main
private enum Run {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = FullscreenCheck()
    app.delegate = delegate
    app.run()
  }
}
