import Cocoa
import FlutterMacOS
import GameController
import Security
import LocalAuthentication

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  var channel: FlutterMethodChannel!
  private var credentialChannel: FlutterMethodChannel!
  private let credentialQueue = DispatchQueue(label: "app.broomm.credentials")
  var permitClose = false
  private var heldDirections: [String: (String, TimeInterval)] = [:]
  private var shiftControllers = Set<String>()
  private var navigationTimer: Timer?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func awakeFromNib() {
    let controller = FlutterViewController()
    contentViewController = controller
    setContentSize(NSSize(width: 1180, height: 800))
    minSize = NSSize(width: 860, height: 620)
    center()
    delegate = self
    title = "Broomm"
    isOpaque = true
    backgroundColor = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.13, alpha: 1)
    RegisterGeneratedPlugins(registry: controller)
    credentialChannel = FlutterMethodChannel(name: "app.broomm/credentials", binaryMessenger: controller.engine.binaryMessenger)
    credentialChannel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      let method = call.method
      let key = args["key"] as? String ?? ""
      let value = args["value"] as? String
      self.credentialQueue.async {
        do {
          let result = try BroommKeychain.perform(method: method, key: key, value: value)
          DispatchQueue.main.async { reply(result) }
        } catch {
          DispatchQueue.main.async { reply(FlutterError(code: "secure_store", message: "Secure sign-in storage is unavailable or locked.", details: nil)) }
        }
      }
    }
    channel = FlutterMethodChannel(name: "app.broomm/prototype", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "show":
        let overlay = args["overlay"] as? Bool ?? false
        self.present(overlay: overlay)
        reply(nil)
      case "hide":
        self.orderOut(nil)
        if let number = args["pid"] as? NSNumber,
           let app = NSRunningApplication(processIdentifier: pid_t(number.int32Value)) {
          app.activate(options: [.activateIgnoringOtherApps])
        }
        reply(nil)
      case "close":
        self.permitClose = true
        reply(nil)
        NSApp.terminate(nil)
      default: reply(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] event in
      if let controller = event.object as? GCController { self?.observe(controller) }
    }
    NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] event in
      guard let controller = event.object as? GCController, let self = self else { return }
      let prefix = "\(ObjectIdentifier(controller))-"
      self.heldDirections = self.heldDirections.filter { !$0.key.hasPrefix(prefix) }
      self.shift(id: "\(ObjectIdentifier(controller))", pressed: false)
    }
    navigationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      let now = ProcessInfo.processInfo.systemUptime
      for (key, value) in self.heldDirections where now >= value.1 {
        self.input(value.0)
        self.heldDirections[key] = (value.0, now + 0.12)
      }
    }
    GCController.shouldMonitorBackgroundEvents = true
    for gamepad in GCController.controllers() { observe(gamepad) }
    super.awakeFromNib()
  }
  func present(overlay: Bool) {
    // Keep decorations and the user's frame across every screen. Recreating the
    // title bar and following the emulator's changing frame also resizes Metal
    // backing surfaces while the Flutter window is hidden.
    let nextLevel: NSWindow.Level = overlay ? .statusBar : .normal
    let behavior: NSWindow.CollectionBehavior = overlay ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
    if level != nextLevel { level = nextLevel }
    if collectionBehavior != behavior { collectionBehavior = behavior }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func observe(_ controller: GCController) {
    guard let pad = controller.extendedGamepad else { return }
    let id = "\(ObjectIdentifier(controller))"
    pad.buttonA.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("accept") } }
    pad.buttonB.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("back") } }
    pad.buttonX.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("search") } }
    pad.buttonY.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("space") } }
    pad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("caps") } }
    pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("caret-left") } }
    pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("caret-right") } }
    pad.leftTrigger.pressedChangedHandler = { [weak self] _, _, down in self?.shift(id: id, pressed: down) }
    pad.rightTrigger.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("keyboard-enter") } }
    pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("home") } }
    pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, down in if down { self?.input("options") } }
    for (name, button) in [("up", pad.dpad.up), ("down", pad.dpad.down), ("left", pad.dpad.left), ("right", pad.dpad.right)] {
      button.pressedChangedHandler = { [weak self] _, _, down in
        self?.direction(key: "\(id)-dpad-\(name)", value: down ? name : nil)
      }
    }
    pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
      let value: String? = abs(x) > abs(y) && abs(x) > 0.55 ? (x < 0 ? "left" : "right") : abs(y) > 0.55 ? (y < 0 ? "down" : "up") : nil
      self?.direction(key: "\(id)-stick", value: value)
    }
  }
  func shift(id: String, pressed: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let previous = !self.shiftControllers.isEmpty
      if pressed { self.shiftControllers.insert(id) } else { self.shiftControllers.remove(id) }
      let active = !self.shiftControllers.isEmpty
      if previous != active { self.input(active ? "shift-down" : "shift-up") }
    }
  }
  func direction(key: String, value: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard let value = value else { self.heldDirections.removeValue(forKey: key); return }
      if self.heldDirections[key]?.0 != value {
        self.input(value)
        self.heldDirections[key] = (value, ProcessInfo.processInfo.systemUptime + 0.4)
      }
    }
  }
  func input(_ value: String) {
    DispatchQueue.main.async { [weak self] in self?.channel.invokeMethod("controller", arguments: value) }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if permitClose { return true }
    channel.invokeMethod("closeRequested", arguments: nil)
    return false
  }
}

// Narrow OS storage adapter. Token refresh, account identity and lifecycle stay
// in Dart. The legacy login Keychain needs no sharing/provisioning entitlement.
enum BroommKeychain {
  static func perform(method: String, key: String, value: String?) throws -> String? {
    guard key.range(of: "^(sgdb-)?[a-f0-9]{32}$", options: .regularExpression) != nil,
          ["read", "write", "delete"].contains(method) else { throw failure(errSecParam) }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.broomm.romm.v1",
      kSecAttrAccount as String: key,
      kSecAttrSynchronizable as String: false,
    ]
    var query = base
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = authentication
    switch method {
    case "read":
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess, let data = item as? Data,
            data.count <= 32768, let result = String(data: data, encoding: .utf8) else { throw failure(status) }
      return result
    case "write":
      guard let data = value?.data(using: .utf8), data.count <= 32768 else { throw failure(errSecParam) }
      let attributes = [kSecValueData as String: data]
      var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = key.hasPrefix("sgdb-") ? "Broomm SteamGridDB key" : "Broomm RomM sign-in"
        status = SecItemAdd(item as CFDictionary, nil)
      }
      guard status == errSecSuccess else { throw failure(status) }
      return nil
    default:
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
      return nil
    }
  }
  private static func failure(_ status: OSStatus) -> NSError {
    NSError(domain: "app.broomm.credentials", code: Int(status), userInfo: nil)
  }
}
