import Cocoa
import FlutterMacOS
import GameController
import ScreenCaptureKit
import CoreImage
import Darwin

/// OS capture and local input transport. Connection and session policy stay in Dart.
final class BroommRemoteScreen {
  private let channel: FlutterMethodChannel
  private let recovery = BroommSessionRecovery()
  private var controllerTimer: Timer?
  private var capture: AnyObject?
  private var revision = 0
  private var inputSocket: Int32 = -1
  private var inputEnabled = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app.broomm/remote", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { reply(nil); return }
      switch call.method {
      case "controller":
        self.controllerTimer?.invalidate()
        self.controllerTimer = nil
        self.inputEnabled = call.arguments as? Bool == true
        for controller in GCController.controllers() { self.observe(controller) }
        if self.inputEnabled {
          self.controllerTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in self?.sampleController() }
        }
        reply(nil)
      case "input":
        self.sendInput(call.arguments as? [String: Any] ?? [:])
        reply(nil)
      case "cancelCapture":
        self.revision += 1
        let previous = self.capture
        self.capture = nil
        Task { @MainActor in
          if #available(macOS 12.3, *), let stream = previous as? BroommWindowStream { await stream.stop() }
          reply(nil)
        }
      case "nextFrame":
        if #available(macOS 12.3, *), let capture = self.capture as? BroommWindowStream,
           let args = call.arguments as? [String: Any], args["id"] as? Int == capture.captureID { capture.nextFrame() }
        reply(nil)
      case "capture":
        self.revision += 1
        let revision = self.revision
        let arguments = call.arguments as? [String: Any]
        let previous = self.capture
        self.capture = nil
        Task { @MainActor in
          do {
            if #available(macOS 12.3, *) {
              if let previous = previous as? BroommWindowStream { await previous.stop() }
              guard revision == self.revision else { reply(nil); return }
              if let args = arguments {
                let app = try self.recovery.emulatorWindowTarget(args)
                guard revision == self.revision else { reply(nil); return }
                let stream = BroommWindowStream(channel: self.channel, captureID: args["id"] as? Int ?? 0)
                self.capture = stream
                try await stream.start(pid: app.processIdentifier, name: args["name"] as? String ?? "", geometry: args["remoteCapture"] as? [NSNumber], valid: {
                  revision == self.revision && !app.isTerminated
                })
                if revision != self.revision { await stream.stop() }
              }
              reply(nil)
            } else {
              reply(FlutterError(code: "capture", message: "Remote screen hosting requires macOS 12.3 or later.", details: nil))
            }
          } catch {
            reply(FlutterError(code: "capture", message: error.localizedDescription, details: nil))
          }
        }
      default: reply(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] event in
      if let controller = event.object as? GCController { self?.observe(controller) }
    }
  }

  private func observe(_ controller: GCController) {
    controller.extendedGamepad?.valueChangedHandler = inputEnabled ? { [weak self] _, _ in
      DispatchQueue.main.async { self?.sampleController() }
    } : nil
  }

  private func sendInput(_ args: [String: Any]) {
    guard let path = args["path"] as? String, path.hasPrefix(NSTemporaryDirectory()),
          !path.contains("\0"), path.utf8.count < 104,
          let report = args["report"] as? String, report.utf8.count < 180 else { return }
    if inputSocket < 0 { inputSocket = socket(AF_UNIX, SOCK_DGRAM, 0) }
    guard inputSocket >= 0 else { return }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { bytes in
      bytes.initializeMemory(as: UInt8.self, repeating: 0)
      path.utf8CString.withUnsafeBytes { source in bytes.copyBytes(from: source) }
    }
    let data = Array(report.utf8)
    _ = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        sendto(inputSocket, data, data.count, MSG_DONTWAIT, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }

  private func sampleController() {
    guard inputEnabled, NSApp.isActive, let controller = GCController.controllers().first, let pad = controller.extendedGamepad else {
      channel.invokeMethod("pad", arguments: ["buttons": 0, "axes": [0,0,0,0,0,0], "connected": false]); return
    }
    let buttons: [GCControllerButtonInput?] = [pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
      pad.buttonOptions, pad.buttonHome, pad.buttonMenu, pad.leftThumbstickButton, pad.rightThumbstickButton,
      pad.leftShoulder, pad.rightShoulder, pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right]
    var mask = 0
    for (index, button) in buttons.enumerated() where button?.isPressed == true { mask |= 1 << index }
    let values = [pad.leftThumbstick.xAxis.value, -pad.leftThumbstick.yAxis.value,
      pad.rightThumbstick.xAxis.value, -pad.rightThumbstick.yAxis.value,
      pad.leftTrigger.value, pad.rightTrigger.value]
    channel.invokeMethod("pad", arguments: ["device": "\(ObjectIdentifier(controller))", "buttons": mask, "axes": values.map { Int(max(-1, min(1, $0)) * 32767) }, "connected": true])
  }

  deinit {
    controllerTimer?.invalidate()
    if inputSocket >= 0 { Darwin.close(inputSocket) }
  }
}

@available(macOS 12.3, *)
private final class BroommWindowStream: NSObject, SCStreamOutput, SCStreamDelegate {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "app.broomm.remote.capture", autoreleaseFrequency: .workItem)
  private let context = CIContext(options: [.cacheIntermediates: false])
  private var stream: SCStream?
  private var permitted = true
  private var stopped = false
  let captureID: Int
  private var statsStart = ProcessInfo.processInfo.systemUptime
  private var frames = 0, idle = 0, blank = 0, suspended = 0
  private var encodeMillis = 0.0

  init(channel: FlutterMethodChannel, captureID: Int) { self.channel = channel; self.captureID = captureID }

  @MainActor
  func start(pid: pid_t, name: String, geometry: [NSNumber]?, valid: () -> Bool) async throws {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      throw failure("Allow Broomm in System Settings → Privacy & Security → Screen & System Audio Recording, then reconnect.")
    }
    var selected: SCWindow?
    for _ in 0..<60 {
      guard valid() else { return }
      let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
      let windows = content.windows.filter { window in
        guard window.owningApplication?.processID == pid else { return false }
        let title = window.title ?? ""
        return name == "melonDS" ? title.contains("[w2]") && geometry?.first?.uint32Value == window.windowID : title.hasSuffix("Secondary Window")
      }
      if windows.count == 1 { selected = windows[0]; break }
      if windows.count > 1 { throw failure("The secondary emulator window is ambiguous.") }
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    guard let window = selected, valid() else {
      throw failure("The emulator has no secondary window. Connect before launching melonDS or Azahar, then launch the game again.")
    }
    let configuration = SCStreamConfiguration()
    if name == "melonDS" {
      guard let geometry = geometry, geometry.count == 5 else { throw failure("The emulator screen geometry is unavailable.") }
      let values = geometry.dropFirst().map { $0.doubleValue }
      guard values.allSatisfy({ $0.isFinite }), values[0] >= 0, values[1] >= 0,
            values[2] > 0, values[3] > 0,
            values[0] + values[2] <= window.frame.width + 1,
            values[1] + values[3] <= window.frame.height + 1 else { throw failure("The emulator screen geometry changed. Retry screen capture.") }
      configuration.sourceRect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    configuration.width = 640
    configuration.height = 480
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    configuration.queueDepth = 3
    configuration.showsCursor = false
    if #available(macOS 14.0, *) { configuration.ignoreShadowsSingleWindow = true }
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: self)
    self.stream = stream
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
  }

  func nextFrame() { queue.async { self.permitted = true } }
  @MainActor
  func stop() async {
    queue.sync { stopped = true }
    try? await stream?.stopCapture()
    stream = nil
  }
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    queue.async {
      guard !self.stopped else { return }
      DispatchQueue.main.async { self.channel.invokeMethod("captureError", arguments: ["id": self.captureID, "message": error.localizedDescription]) }
    }
  }
  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, !stopped, sampleBuffer.isValid else { return }
    defer { reportStats() }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
       let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != .complete {
      if status == .idle { idle += 1 }
      if status == .blank { blank += 1 }
      if status == .suspended { suspended += 1 }
      return
    }
    guard permitted, let buffer = sampleBuffer.imageBuffer else { return }
    let start = ProcessInfo.processInfo.systemUptime
    let image = CIImage(cvPixelBuffer: buffer)
    guard let cg = context.createCGImage(image, from: image.extent),
          let jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.75]),
          jpeg.count <= 1024 * 1024 else { return }
    frames += 1
    encodeMillis += (ProcessInfo.processInfo.systemUptime - start) * 1000
    permitted = false
    DispatchQueue.main.async {
      self.channel.invokeMethod("frame", arguments: ["id": self.captureID, "bytes": FlutterStandardTypedData(bytes: jpeg)])
    }
  }
  private func reportStats() {
    let now = ProcessInfo.processInfo.systemUptime, elapsed = now - statsStart
    guard elapsed >= 5 else { return }
    let report: [String: Any] = ["id": captureID, "fps": String(format: "%.1f", Double(frames)/elapsed),
      "encodeMs": String(format: "%.2f", frames == 0 ? 0 : encodeMillis/Double(frames)),
      "idle": idle, "blank": blank, "suspended": suspended]
    statsStart = now; frames = 0; idle = 0; blank = 0; suspended = 0; encodeMillis = 0
    DispatchQueue.main.async { self.channel.invokeMethod("captureStats", arguments: report) }
  }

  private func failure(_ message: String) -> NSError {
    NSError(domain: "app.broomm.remote", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
