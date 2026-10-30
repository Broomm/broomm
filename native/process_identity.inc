// Narrow Darwin process/lock inspection for Launch Services-owned children.
// Dart owns session supervision. No process is signalled by these functions.
#include <libproc.h>
#include <sys/proc_info.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>

static int broomm_birth(pid_t pid, const char *expected, uint64_t *out) {
    struct proc_bsdinfo first, last;
    int size = (int)sizeof(first);
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &first, size) != size) {
        return errno == ESRCH ? 0 : -1;
    }
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (first.pbi_uid != getuid() || proc_pidpath(pid, path, sizeof(path)) <= 0 ||
        strcmp(path, expected) != 0 ||
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &last, size) != size ||
        first.pbi_start_tvsec != last.pbi_start_tvsec ||
        first.pbi_start_tvusec != last.pbi_start_tvusec) return -1;
    out[0] = (uint64_t)pid;
    out[1] = first.pbi_start_tvsec;
    out[2] = first.pbi_start_tvusec;
    return 1;
}

int broomm_native_writer(const char *lock_path, const char *expected, uint64_t *out) {
    int fd = open(lock_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat info;
    struct flock query = {.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
    int result = -1;
    if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && fcntl(fd, F_GETLK, &query) == 0)
        result = query.l_type == F_UNLCK ? 0 : broomm_birth(query.l_pid, expected, out);
    close(fd);
    return result;
}

int broomm_native_alive(const char *expected, const uint64_t *identity) {
    uint64_t current[3];
    int result = broomm_birth((pid_t)identity[0], expected, current);
    if (result != 1) return result;
    return current[1] == identity[1] && current[2] == identity[2] ? 1 : 0;
}

int broomm_launch_owner(uint64_t *out) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if(proc_pidpath(getpid(),path,sizeof(path))<=0)return -1;
    return broomm_birth(getpid(),path,out);
}

int broomm_log_pipe(const char *path) {
    int fd = open(path, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    struct stat info;
    if (fd >= 0 && fstat(fd, &info) == 0 && S_ISFIFO(info.st_mode)) return fd;
    if (fd >= 0) close(fd);
    return -1;
}

void *broomm_application_capture(const char *expected, const uint64_t *identity) {
    if (broomm_native_alive(expected, identity) != 1) return NULL;
    id app=((id(*)(id,SEL,pid_t))objc_msgSend)((id)objc_getClass("NSRunningApplication"),sel_registerName("runningApplicationWithProcessIdentifier:"),(pid_t)identity[0]);
    if (!app || broomm_native_alive(expected,identity) != 1 ||
        ((bool(*)(id,SEL))objc_msgSend)(app,sel_registerName("isTerminated"))) return NULL;
    return (void *)CFRetain((CFTypeRef)app);
}

int broomm_application_stop(void *handle, const char *expected, const uint64_t *identity, int force) {
    id app=(id)handle;
    if (!app || broomm_native_alive(expected,identity) != 1 ||
        ((bool(*)(id,SEL))objc_msgSend)(app,sel_registerName("isTerminated")) ||
        ((pid_t(*)(id,SEL))objc_msgSend)(app,sel_registerName("processIdentifier")) != (pid_t)identity[0]) return 0;
    // The retained AppKit identity prevents a PID reused after the kernel
    // readback from redirecting this request to another application.
    return ((bool(*)(id,SEL))objc_msgSend)(app,sel_registerName(force?"forceTerminate":"terminate")) ? 1 : 0;
}

void broomm_application_release(void *handle) {
    if (handle) CFRelease((CFTypeRef)handle);
}
