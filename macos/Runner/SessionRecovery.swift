import Cocoa
import Darwin

/// OS adapter only: report the kernel lock owner and retain AppKit's unique
/// application identity. Dart owns recovery choices and all save workflows.
final class BroommSessionRecovery {
  private struct Owner: Equatable {
    let pid: pid_t
    let device: dev_t
    let inode: ino_t
  }
  private struct Application {
    let root: String
    let owner: Owner
    let app: NSRunningApplication
    let launched: Date?
    let executable: String
    let birth: Birth
  }
  private struct Birth: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    let uid: uid_t
  }
  private var applications: [String: Application] = [:]

  private func birth(_ pid: pid_t) throws -> Birth {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
          info.pbi_pid == UInt32(pid), info.pbi_uid == getuid(),
          info.pbi_start_tvsec > 0 else {
      throw failure("The operating system could not verify the emulator process identity. No process was signalled.")
    }
    return Birth(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec, uid: info.pbi_uid)
  }

  private func executable(_ pid: pid_t) throws -> String {
    // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN in the public Apple SDK;
    // Swift cannot import that expression macro directly.
    let capacity = 4 * Int(MAXPATHLEN)
    var buffer = [CChar](repeating: 0, count: capacity)
    let count = proc_pidpath(pid, &buffer, UInt32(capacity))
    guard count > 0, count < buffer.count else {
      throw failure("The operating system could not verify the emulator executable. No process was signalled.")
    }
    return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
  }

  private func owner(_ path: String) throws -> Owner? {
    let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    if fd < 0 {
      if errno == ENOENT { return nil }
      throw failure("The game lock could not be inspected. Its files were kept.")
    }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
      throw failure("The game lock is not a regular file. Its files were kept.")
    }
    var query = flock()
    query.l_type = Int16(F_WRLCK)
    query.l_whence = Int16(SEEK_SET)
    query.l_start = 0
    query.l_len = 0
    guard fcntl(fd, F_GETLK, &query) == 0 else {
      throw failure("The operating system could not confirm the game lock owner.")
    }
    if query.l_type == Int16(F_UNLCK) { return nil }
    guard query.l_pid > 0 else { throw failure("The game writer could not be identified.") }
    return Owner(pid: query.l_pid, device: info.st_dev, inode: info.st_ino)
  }

  func inspect(root: String) throws -> [String: Any]? {
    guard root.hasPrefix("/"), !root.contains("\0"), root.utf8.count < 4096 else {
      throw failure("Invalid Broomm storage location.")
    }
    let url = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL
    let path = url.path
    var directory: ObjCBool = false
    if !FileManager.default.fileExists(atPath: path, isDirectory: &directory) { return nil }
    guard directory.boolValue else { throw failure("Broomm storage is not a directory.") }
    if let coordinator = try owner(path + "/session.lock") {
      return ["status": "launcher", "pid": coordinator.pid,
              "message": "Another Broomm instance is using this storage. Close its game or quit that instance, then check again."]
    }
    guard let writer = try owner(path + "/writer.lock") else { return nil }
    guard let app = NSRunningApplication(processIdentifier: writer.pid), !app.isTerminated,
          let processBirth = try? birth(writer.pid),
          let executable = app.executableURL?.resolvingSymlinksInPath().path,
          executable.hasPrefix(path + "/emulators/") || executable.hasPrefix(path + "/profiles/"),
          try self.executable(writer.pid) == executable,
          try birth(writer.pid) == processBirth else {
      return ["status": "unknown", "pid": writer.pid,
              "message": "An emulator or helper still owns Broomm’s game data. Its application identity could not be verified, so Broomm cannot terminate it. Close that process normally, then check again."]
    }
    applications = applications.filter { !$0.value.app.isTerminated }
    let token: String
    if let existing = applications.first(where: { $0.value.root == path && $0.value.owner == writer && $0.value.birth == processBirth && $0.value.executable == executable }) {
      token = existing.key
    } else {
      if applications.count >= 16 { throw failure("Too many emulator recovery handles are open. Quit Broomm and retry.") }
      token = UUID().uuidString
      applications[token] = Application(root: path, owner: writer, app: app, launched: app.launchDate, executable: executable, birth: processBirth)
    }
    return ["status": "emulator", "token": token, "pid": writer.pid,
            "name": app.localizedName ?? "Emulator",
            "message": "This emulator survived the previous Broomm session. Close it before launching another game or changing saves. Local progress is kept."]
  }

  func control(token: String, action: String) throws {
    guard let captured = applications[token], !captured.app.isTerminated,
          (captured.launched == nil || captured.app.launchDate == captured.launched),
          try birth(captured.owner.pid) == captured.birth,
          captured.app.executableURL?.resolvingSymlinksInPath().path == captured.executable,
          try executable(captured.owner.pid) == captured.executable,
          try owner(captured.root + "/session.lock") == nil,
          try owner(captured.root + "/writer.lock") == captured.owner else {
      applications.removeValue(forKey: token)
      throw failure("The emulator or lock owner changed. Check the session again; no process was signalled.")
    }
    switch action {
    case "show":
      captured.app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    case "stop":
      guard captured.app.terminate() else { throw failure("The emulator did not accept a normal quit request. Your local data was kept.") }
    case "force":
      // Called only after the owner's explicit in-app force-quit confirmation.
      // NSRunningApplication retains the application identity across PID reuse.
      guard captured.app.forceTerminate() else { throw failure("The emulator could not be terminated. Your local data was kept.") }
    default: throw failure("Unknown session recovery action.")
    }
  }
  private func failure(_ message: String) -> NSError {
    NSError(domain: "app.broomm.session-recovery", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
  }
}
