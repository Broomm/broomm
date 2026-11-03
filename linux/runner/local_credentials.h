#ifndef BROOMM_LOCAL_CREDENTIALS_H_
#define BROOMM_LOCAL_CREDENTIALS_H_

#include <gio/gio.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <stdexcept>
#include <string>

namespace broomm_credentials {
inline std::string local_credential(const std::string& root,
                                    const std::string& method,
                                    const std::string& key,
                                    const std::string& value, bool& present) {
  const auto fail = [] {
    throw std::runtime_error("Private credential storage unavailable");
  };
  struct stat info {};
  const uid_t owner = geteuid();
  if (lstat(root.c_str(), &info) != 0 || !S_ISDIR(info.st_mode) ||
      info.st_uid != owner || (info.st_mode & 0022)) fail();

  const std::string directory = root + "/private-credentials";
  if (mkdir(directory.c_str(), 0700) != 0 && errno != EEXIST) fail();
  if (lstat(directory.c_str(), &info) != 0 || !S_ISDIR(info.st_mode) ||
      info.st_uid != owner || (info.st_mode & 077)) fail();

  const std::string path = directory + "/" + key;
  if (lstat(path.c_str(), &info) == 0) {
    if (!S_ISREG(info.st_mode) || info.st_uid != owner ||
        (info.st_mode & 077) || info.st_nlink != 1) fail();
  } else if (errno == ENOENT) {
    if (method != "write") return {};
  } else {
    fail();
  }

  if (method == "delete") {
    if (unlink(path.c_str()) != 0 && errno != ENOENT) fail();
    return {};
  }
  if (method == "write") {
    // Publish from a mode-0600 sibling temporary file after flushing its data.
    if (!g_file_set_contents_full(path.c_str(), value.data(), value.size(),
          static_cast<GFileSetContentsFlags>(G_FILE_SET_CONTENTS_CONSISTENT |
                                            G_FILE_SET_CONTENTS_DURABLE),
          0600, nullptr)) fail();
    return {};
  }

  const int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) {
    if (errno == ENOENT) return {};
    fail();
  }
  char bytes[32769];
  ssize_t size = -1;
  if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) &&
      info.st_uid == owner && !(info.st_mode & 077) && info.st_nlink == 1 &&
      info.st_size <= 32768) {
    // Published entries are immutable. Read the opened inode even if a
    // different process replaces the directory entry.
    size = pread(fd, bytes, sizeof(bytes), 0);
  }
  close(fd);
  if (size <= 0 || size > 32768 || size != info.st_size ||
      std::string(bytes, size).find('\0') != std::string::npos ||
      !g_utf8_validate(bytes, size, nullptr)) fail();
  present = true;
  return std::string(bytes, size);
}
}  // namespace broomm_credentials
#endif
