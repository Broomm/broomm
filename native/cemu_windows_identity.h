#ifndef BROOMM_CEMU_WINDOWS_IDENTITY_H_
#define BROOMM_CEMU_WINDOWS_IDENTITY_H_
#include <cstdint>
// Fixed layout, published once by the admitted DLL before Cemu's entry point.
// The host reads this record from that exact mapped module, not a stale file.
struct BroommCemuWriterIdentity {
  uint32_t magic,version,pid,volume;
  uint64_t birth,inode;
  char token[64];
};
static_assert(sizeof(BroommCemuWriterIdentity)==96,"Cemu writer ABI changed");
constexpr uint32_t broomm_cemu_writer_magic=0x42524d43;
#endif
