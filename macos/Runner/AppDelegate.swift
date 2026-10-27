import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    Self.applyApplicationIcon(to: NSApplication.shared)
  }

  @discardableResult
  static func applyApplicationIcon(to application: NSApplication, bundle: Bundle = .main) -> Bool {
    // Finder and the running Dock tile have separate icon resolution. Read our
    // own resource directly, including when several local builds share an ID.
    guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: url), icon.isValid else {
      NSLog("Broomm could not load its bundled application icon.")
      return false
    }
    application.applicationIconImage = icon
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let window = mainFlutterWindow as? MainFlutterWindow else { return .terminateNow }
    if window.permitClose { return .terminateNow }
    window.requestClose()
    return .terminateCancel
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
