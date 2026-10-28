// Broomm-owned POSIX interop only. Dart owns installation and publication.
#include <stdbool.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dlfcn.h>
#include "ppsspp_storage.inc"
#include "eden_probe.inc"
static int writer_fd = -1;
static int configuration_fd = -1;
__attribute__((constructor)) static void guard_installer_writer(void) {
    if(eden_vulkan_probe())return;
    const char *path = getenv("BROOMM_INSTALLER_WRITER_LOCK");
    if (!path) return;
    const char *coordinator = getenv("BROOMM_CONFIGURATION_SESSION_LOCK");
    if (coordinator) {
        configuration_fd = open(coordinator,O_RDWR|O_NOFOLLOW|O_CLOEXEC);
        struct stat owner;
        struct flock handoff = {.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
        if (configuration_fd<0 || fstat(configuration_fd,&owner)!=0 || !S_ISREG(owner.st_mode))
            _exit(78);
        // Refuse a competing operation before native settings/save writers
        // initialize. Neither Broomm nor the detached child waits for it.
        if(fcntl(configuration_fd,F_SETLK,&handoff)!=0)_exit(78);
    }
    writer_fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    struct stat info;
    struct flock lock = {.l_type=F_WRLCK, .l_whence=SEEK_SET, .l_start=0, .l_len=0};
    if (writer_fd < 0 || fstat(writer_fd,&info) != 0 || !S_ISREG(info.st_mode) || fcntl(writer_fd,F_SETLK,&lock) != 0) {
        fputs("Broomm installer writer lock could not be acquired.\n",stderr);
        _exit(78);
    }
    if (coordinator) {
        // Launch Services creates the app outside the launcher's sandbox.
        // Apply the Dart-supplied child policy before native settings writers.
        const char *root = getenv("BROOMM_CONFIGURATION_ROOT");
        const char *policy = getenv("BROOMM_CONFIGURATION_SANDBOX");
        void *library = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_NOW | RTLD_LOCAL);
        int (*initialize)(const char *, unsigned long long, char **) = library ? dlsym(library,"sandbox_init") : NULL;
        char *error = NULL;
        if (!root || !policy || root[0]!='/' ||
            chdir(root)!=0 || !initialize || initialize(policy,0,&error)!=0) {
            fputs("Broomm private configuration sandbox could not be applied.\n",stderr);
            _exit(78);
        }
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
