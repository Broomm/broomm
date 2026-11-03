#include "../../linux/runner/local_credentials.h"

#include <cassert>
#include <cstdlib>
#include <iostream>

using broomm_credentials::local_credential;

int main(int argc, char** argv) {
  assert(argc == 3);
  const std::string root = argv[1];
  const std::string phase = argv[2];
  const std::string key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  const std::string other = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  const std::string directory = root + "/private-credentials";
  const std::string entry = directory + "/" + key;
  bool present = false;
  if (phase == "write") {
    umask(0);
    assert(local_credential(root, "read", key, "", present).empty() && !present);
    local_credential(root, "write", key, "fixture first", present);
    local_credential(root, "write", key, "fixture refreshed", present);
    local_credential(root, "write", other, "other profile", present);
    struct stat info {};
    assert(stat(directory.c_str(), &info) == 0 && (info.st_mode & 0777) == 0700);
    assert(stat(entry.c_str(), &info) == 0 && (info.st_mode & 0777) == 0600);
    return 0;
  }
  assert(phase == "restore");
  assert(local_credential(root, "read", key, "", present) == "fixture refreshed" && present);
  local_credential(root, "delete", key, "", present);
  present = false;
  assert(local_credential(root, "read", key, "", present).empty() && !present);
  assert(local_credential(root, "read", other, "", present) == "other profile" && present);

  const std::string target = directory + "/" + other;
  assert(symlink(target.c_str(), entry.c_str()) == 0);
  for (const std::string method : {"read", "write", "delete"}) {
    bool refused = false;
    try {
      local_credential(root, method, key, "fixture", present);
    } catch (const std::runtime_error&) {
      refused = true;
    }
    assert(refused);
  }
  assert(local_credential(root, "read", other, "", present) == "other profile");
  std::cout << "Private credential modes, restart, profile separation and symlink refusal passed\n";
}
