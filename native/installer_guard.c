// Broomm-owned POSIX interop only. Dart owns installation and publication.
#include <stdbool.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "ppsspp_storage.inc"
#include "eden_probe.inc"
static int writer_fd = -1;
__attribute__((constructor)) static void guard_installer_writer(void) {
    if(eden_vulkan_probe())return;
    const char *path = getenv("BROOMM_INSTALLER_WRITER_LOCK");
    if (!path) return;
    writer_fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    struct stat info;
    struct flock lock = {.l_type=F_WRLCK, .l_whence=SEEK_SET, .l_start=0, .l_len=0};
    if (writer_fd < 0 || fstat(writer_fd,&info) != 0 || !S_ISREG(info.st_mode) || fcntl(writer_fd,F_SETLK,&lock) != 0) {
        fputs("Broomm installer writer lock could not be acquired.\n",stderr);
        _exit(78);
    }
    // Intentionally held through all native teardown, including parent death.
}

// An unattended RPCS3 CLI process can deliberately abort during its broken
// post-main destructor. Report an ordinary, non-success process status instead
// of raising SIGABRT and asking macOS to show a crash notification. Dart still
// requires the exact completion/teardown diagnostics and validates the output.
// No-game configuration and gameplay do not set this child-only opt-in.
__attribute__((noreturn)) static void installer_abort(void) {
    const char *mode = getenv("BROOMM_INSTALLER_ABORT_MODE");
    if (writer_fd >= 0 && mode && strcmp(mode,"rpcs3-cli-v1") == 0) {
        static const char marker[] = "\nBROOMM_RPCS3_CLI_ABORT_V1\n";
        (void)write(STDERR_FILENO,marker,sizeof(marker)-1);
        _exit(86);
    }
    abort();
}
__attribute__((used,section("__DATA,__interpose"))) static const struct {
    const void *replacement,*original;
} interpose_abort = {(const void *)installer_abort,(const void *)abort};

#include "dolphin_installer.inc"
