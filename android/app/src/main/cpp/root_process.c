/* Owned Android kernel adapter. No injected code, process-memory writes or
 * save decisions. A short-lived tracer freezes one verified process, compares
 * bounded status bytes, and disposes of its idle cache through a pidfd. Kernel
 * tracer-death cleanup resumes every tracee if this operation is interrupted. */
#define _GNU_SOURCE
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/mman.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef __WALL
#define __WALL 0x40000000
#endif
#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434
#endif
#ifndef __NR_pidfd_send_signal
#define __NR_pidfd_send_signal 424
#endif

enum { ROOT_STOPPED = 0, ROOT_BUSY = 1, ROOT_GONE = 2,
       ROOT_UNAVAILABLE = 3, ROOT_CHANGED = 4, ROOT_TIMEOUT = 5,
       ROOT_ATTACH_REFUSED = 6, ROOT_WRITABLE = 7, ROOT_READY = 8 };
enum { ROOT_THREADS = 512, ROOT_MAPS = 1024 * 1024, ROOT_GUARDS = 3,
       ROOT_MAP_LINES = 4, ROOT_PREFIXES = 8 };
struct root_guard { uint64_t address; uint32_t bytes; };
struct root_stop_request {
    pid_t pid;
    uint64_t start_ticks;
    int guards, maps, prefixes;
    struct root_guard guard[ROOT_GUARDS];
    char map[ROOT_MAP_LINES][1024];
    char prefix[ROOT_PREFIXES][256];
};
struct root_dirent {
    uint64_t ino;
    int64_t off;
    unsigned short reclen;
    unsigned char type;
    char name[];
};

static int64_t root_millis(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) return -1;
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static void root_path(char *out, size_t n, pid_t pid, const char *leaf) {
    (void)snprintf(out, n, "/proc/%d/%s", pid, leaf);
}
static ssize_t root_read(const char *path, char *out, size_t cap) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    size_t used = 0;
    while (used < cap) {
        ssize_t n = read(fd, out + used, cap - used);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { used = cap; break; }
        if (!n) break;
        used += (size_t)n;
    }
    close(fd);
    if (used == cap) return -1;
    out[used] = 0;
    return (ssize_t)used;
}
static uint64_t root_ticks(pid_t pid) {
    char path[64], b[4096]; root_path(path, sizeof(path), pid, "stat");
    if (root_read(path, b, sizeof(b) - 1) < 0) return 0;
    char *p = strrchr(b, ')');
    if (!p || p[1] != ' ') return 0;
    p += 2;
    for (int i = 0; i < 19; ++i) {
        p = strchr(p, ' '); if (!p) return 0; ++p;
    }
    char *end; uint64_t ticks = strtoull(p, &end, 10);
    return end == p || (*end != ' ' && *end != '\n') ? 0 : ticks;
}
static int root_thread(pid_t tid, pid_t pid) {
    char path[64], b[4096]; root_path(path, sizeof(path), tid, "status");
    if (root_read(path, b, sizeof(b) - 1) < 0) return 0;
    char *p = strstr(b, "\nTgid:");
    return p && strtol(p + 6, NULL, 10) == pid;
}
static int root_available(pid_t tid) {
    char path[64], b[4096]; root_path(path, sizeof(path), tid, "status");
    if (root_read(path, b, sizeof(b) - 1) < 0) return 0;
    char *state = strstr(b, "\nState:"), *tracer = strstr(b, "\nTracerPid:");
    if (!state || !tracer || strtol(tracer + 11, NULL, 10)) return 0;
    state += 7;
    while (*state == ' ' || *state == '\t') ++state;
    /* Preserve a stop owned by the user/debugger; never take it over. */
    return *state != 'T' && *state != 't' && *state != 'Z' && *state != 'X';
}
static int root_names(const char *path, pid_t *out, int cap) {
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return -1;
    _Alignas(uint64_t) char b[8192]; int count = 0;
    for (;;) {
        long n = syscall(SYS_getdents64, fd, b, sizeof(b));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { count = -1; break; }
        if (!n) break;
        for (long off = 0; off < n;) {
            struct root_dirent *d = (struct root_dirent *)(void *)(b + off);
            if (d->reclen < 20 || off + d->reclen > n) { count = -1; goto done; }
            size_t max = d->reclen - 19;
            if (!memchr(d->name, 0, max)) { count = -1; goto done; }
            if (d->name[0] >= '0' && d->name[0] <= '9') {
                char *end; long value = strtol(d->name, &end, 10);
                if (*end || value < 0 || value > INT32_MAX || count == cap) {
                    count = -1; goto done;
                }
                out[count++] = (pid_t)value;
            }
            off += d->reclen;
        }
    }
done:
    close(fd); return count;
}
static int root_has_map(const char *all, const char *line) {
    size_t n = strlen(line);
    for (const char *p = all; *p;) {
        const char *end = strchr(p, '\n');
        if (!end) return 0;
        if ((size_t)(end - p) == n && !memcmp(p, line, n)) return 1;
        p = end + 1;
    }
    return 0;
}
static int root_writable(const struct root_stop_request *r) {
    char path[96], target[4096], info[2048]; pid_t fds[4096];
    root_path(path, sizeof(path), r->pid, "fd");
    int n = root_names(path, fds, 4096);
    if (n < 0) return 1;
    for (int i = 0; i < n; ++i) {
        snprintf(path, sizeof(path), "/proc/%d/fd/%d", r->pid, fds[i]);
        ssize_t bytes = readlink(path, target, sizeof(target) - 1);
        if (bytes < 0) return 1;
        target[bytes] = 0;
        int relevant = 0;
        for (int p = 0; p < r->prefixes; ++p)
            if (!strncmp(target, r->prefix[p], strlen(r->prefix[p]))) relevant = 1;
        if (!relevant) continue;
        snprintf(path, sizeof(path), "/proc/%d/fdinfo/%d", r->pid, fds[i]);
        if (root_read(path, info, sizeof(info) - 1) < 0) return 1;
        char *flags = strstr(info, "\nflags:");
        if (!flags) return 1;
        char *end; unsigned long value = strtoul(flags + 7, &end, 8);
        if (end == flags + 7 || (value & O_ACCMODE) != O_RDONLY) return 1;
    }
    return 0;
}

/* Runs only in the disposable tracer. Even a timeout/crash/parent death drops
 * ptrace ownership in the kernel; no emulator remains stopped by our tracer. */
static int root_trace_stop(const struct root_stop_request *r, int pidfd, int reply, int confirm) {
    if (root_ticks(r->pid) != r->start_ticks) return ROOT_CHANGED;
    char path[64]; root_path(path, sizeof(path), r->pid, "task");
    pid_t attached[ROOT_THREADS]; unsigned char stopped[ROOT_THREADS] = {0};
    int count = 0, stable = 0; int64_t end = root_millis() + 2500;
    while (root_millis() < end) {
        pid_t current[ROOT_THREADS]; int n = root_names(path, current, ROOT_THREADS);
        if (n < 1) return ROOT_CHANGED;
        int all = 1;
        for (int i = 0; i < n; ++i) {
            int index = 0;
            while (index < count && attached[index] != current[i]) ++index;
            if (index == count) {
                if (count == ROOT_THREADS || !root_thread(current[i], r->pid)) return ROOT_CHANGED;
                if (!root_available(current[i])) return ROOT_BUSY;
#ifdef BROOMM_PROCESS_TEST
                extern void root_test_before_attach(pid_t tid, pid_t pid);
                root_test_before_attach(current[i], r->pid);
#endif
                /* SEIZE does not stop the thread or deliver SIGSTOP. */
                if (ptrace(PTRACE_SEIZE, current[i], NULL, NULL)) return ROOT_ATTACH_REFUSED;
                attached[count] = current[i]; stopped[count++] = 0;
                if (!root_thread(current[i], r->pid) ||
                    ptrace(PTRACE_INTERRUPT, current[i], NULL, NULL)) return ROOT_CHANGED;
                stable = 0;
            }
            if (!stopped[index]) {
                int status = 0;
                pid_t got = waitpid(current[i], &status, __WALL | WNOHANG);
                if (got == current[i] && WIFSTOPPED(status) &&
                    (unsigned)status >> 16 == PTRACE_EVENT_STOP && WSTOPSIG(status) == SIGTRAP) stopped[index] = 1;
                else if (got > 0 && WIFSTOPPED(status)) return ROOT_BUSY;
                else if (got < 0 || (got > 0 && !WIFSTOPPED(status))) return ROOT_CHANGED;
            }
            if (!stopped[index]) all = 0;
        }
        if (all && ++stable >= 2) {
            if (root_ticks(r->pid) != r->start_ticks) return ROOT_CHANGED;
            char *maps = mmap(NULL, ROOT_MAPS + 1, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (maps == MAP_FAILED) return ROOT_UNAVAILABLE;
            root_path(path, sizeof(path), r->pid, "maps");
            if (root_read(path, maps, ROOT_MAPS) < 0) return ROOT_CHANGED;
            for (int m = 0; m < r->maps; ++m)
                if (!root_has_map(maps, r->map[m])) return ROOT_CHANGED;
            munmap(maps, ROOT_MAPS + 1);
            root_path(path, sizeof(path), r->pid, "mem");
            int mem = open(path, O_RDONLY | O_CLOEXEC);
            if (mem < 0) return ROOT_UNAVAILABLE;
            int result = ROOT_STOPPED;
            for (int g = 0; g < r->guards; ++g) {
                unsigned char b[128];
                ssize_t bytes = pread(mem, b, r->guard[g].bytes, (off_t)r->guard[g].address);
                if (bytes != (ssize_t)r->guard[g].bytes) { result = ROOT_CHANGED; break; }
                for (ssize_t i = 0; i < bytes; ++i) if (b[i]) result = ROOT_BUSY;
            }
            close(mem);
            if (result != ROOT_STOPPED) return result;
            if (root_writable(r)) return ROOT_WRITABLE;
#ifdef BROOMM_PROCESS_TEST
            extern void root_test_frozen(void);
            root_test_frozen();
#endif
            int ready = ROOT_READY;
            if (write(reply, &ready, sizeof(ready)) != sizeof(ready)) return ROOT_CHANGED;
            struct pollfd approval = {confirm, POLLIN, 0}; unsigned char allowed = 0;
            int64_t remaining = end - root_millis();
            if (remaining <= 0 || poll(&approval, 1, (int)remaining) != 1 ||
                read(confirm, &allowed, 1) != 1 || allowed != 1) return ROOT_BUSY;
            if (root_millis() >= end) return ROOT_TIMEOUT;
            /* All target threads are held; no new writer can start between
             * the byte/descriptor checks and this generation-bound signal. */
            if (syscall(__NR_pidfd_send_signal, pidfd, SIGKILL, NULL, 0)) return ROOT_CHANGED;
            while (root_millis() < end) {
                int status;
                while (waitpid(-1, &status, __WALL | WNOHANG) > 0) { }
                struct pollfd p = {pidfd, POLLIN, 0};
                if (poll(&p, 1, 0) == 1 && (p.revents & POLLIN)) return ROOT_STOPPED;
                struct timespec pause = {0, 1000000}; nanosleep(&pause, NULL);
            }
            return ROOT_TIMEOUT;
        }
        struct timespec pause = {0, 1000000}; nanosleep(&pause, NULL);
    }
    return ROOT_TIMEOUT;
}

static int root_stop_idle_guarded(const struct root_stop_request *r, int (*allow)(void *), void *context) {
    if (r->pid <= 1 || r->pid == getpid() || !r->start_ticks ||
        r->guards < 1 || r->guards > ROOT_GUARDS || r->maps < 1 || r->maps > ROOT_MAP_LINES ||
        r->prefixes < 1 || r->prefixes > ROOT_PREFIXES) return ROOT_UNAVAILABLE;
    int total = 0;
    for (int g = 0; g < r->guards; ++g) {
        if (!r->guard[g].address || r->guard[g].address > INT64_MAX - 128 ||
            !r->guard[g].bytes || r->guard[g].bytes > 128) return ROOT_UNAVAILABLE;
        total += (int)r->guard[g].bytes;
    }
    if (total > 128) return ROOT_UNAVAILABLE;
    int pidfd = (int)syscall(__NR_pidfd_open, r->pid, 0);
    if (pidfd < 0) return errno == ESRCH ? ROOT_GONE : ROOT_UNAVAILABLE;
    if (root_ticks(r->pid) != r->start_ticks) { close(pidfd); return ROOT_CHANGED; }
    int pipes[2], confirm[2];
    if (pipe2(pipes, O_CLOEXEC)) { close(pidfd); return ROOT_UNAVAILABLE; }
    if (pipe2(confirm, O_CLOEXEC)) { close(pipes[0]); close(pipes[1]); close(pidfd); return ROOT_UNAVAILABLE; }
    pid_t parent = getpid(), child = fork();
    if (child == 0) {
        close(pipes[0]); close(confirm[1]);
        if (prctl(PR_SET_PDEATHSIG, SIGKILL, 0L, 0L, 0L) || getppid() != parent) _exit(2);
        int result = root_trace_stop(r, pidfd, pipes[1], confirm[0]);
        (void)write(pipes[1], &result, sizeof(result));
        _exit(0);
    }
    close(pipes[1]); close(pidfd);
    if (child < 0) { close(pipes[0]); close(confirm[0]); close(confirm[1]); return ROOT_UNAVAILABLE; }
    struct pollfd p = {pipes[0], POLLIN, 0};
    int result = ROOT_TIMEOUT;
    if (poll(&p, 1, 3500) == 1 && (p.revents & POLLIN)) {
        if (read(pipes[0], &result, sizeof(result)) != sizeof(result)) result = ROOT_CHANGED;
        if (result == ROOT_READY) {
            /* Parent-only callback: the target cannot change while fresh OS/
             * client lifecycle evidence is checked. The child never calls JNI. */
            unsigned char approved = !allow || allow(context) ? 1 : 0;
            if (write(confirm[1], &approved, 1) != 1) result = ROOT_CHANGED;
            else if (poll(&p, 1, 3500) != 1 || read(pipes[0], &result, sizeof(result)) != sizeof(result)) result = ROOT_TIMEOUT;
        }
    }
    /* Keep our read end until after the approval write: a timed-out child
     * cannot deliver SIGPIPE into the root service. */
    close(confirm[0]); close(confirm[1]); close(pipes[0]);
    if (result < ROOT_STOPPED || result > ROOT_WRITABLE) result = ROOT_CHANGED;
    /* This is our unreaped child, never a caller-supplied PID. */
    (void)kill(child, SIGKILL);
    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) { }
    return result;
}

#ifdef BROOMM_PROCESS_TEST
static int root_stop_idle(const struct root_stop_request *r) { return root_stop_idle_guarded(r, NULL, NULL); }
#endif

#ifndef BROOMM_PROCESS_TEST
#include <jni.h>
struct root_jni_guard { JNIEnv *env; jobject guard; jmethodID method; };
static int root_allow_java(void *value) {
    struct root_jni_guard *g = value;
    jboolean allowed = (*g->env)->CallBooleanMethod(g->env, g->guard, g->method);
    return !(*g->env)->ExceptionCheck(g->env) && allowed;
}
JNIEXPORT jint JNICALL Java_app_broomm_broomm_RootProcessKernel_stopIdle(
    JNIEnv *env, jobject object, jint pid, jlong ticks, jlongArray addresses,
    jintArray lengths, jobjectArray maps, jobjectArray prefixes, jobject guard) {
    (void)object;
    struct root_stop_request r = {0}; r.pid = pid; r.start_ticks = (uint64_t)ticks;
    r.guards = (*env)->GetArrayLength(env, addresses);
    r.maps = (*env)->GetArrayLength(env, maps); r.prefixes = (*env)->GetArrayLength(env, prefixes);
    if (r.guards < 1 || r.guards > ROOT_GUARDS ||
        (*env)->GetArrayLength(env, lengths) != r.guards || r.maps < 1 || r.maps > ROOT_MAP_LINES ||
        r.prefixes < 1 || r.prefixes > ROOT_PREFIXES) return ROOT_UNAVAILABLE;
    jlong a[ROOT_GUARDS]; jint n[ROOT_GUARDS];
    (*env)->GetLongArrayRegion(env, addresses, 0, r.guards, a);
    (*env)->GetIntArrayRegion(env, lengths, 0, r.guards, n);
    if ((*env)->ExceptionCheck(env)) return ROOT_UNAVAILABLE;
    for (int g = 0; g < r.guards; ++g) { r.guard[g].address = (uint64_t)a[g]; r.guard[g].bytes = (uint32_t)n[g]; }
    for (int group = 0; group < 2; ++group) {
        jobjectArray array = group ? prefixes : maps;
        int count = group ? r.prefixes : r.maps;
        for (int i = 0; i < count; ++i) {
            jstring s = (jstring)(*env)->GetObjectArrayElement(env, array, i);
            if (!s) return ROOT_UNAVAILABLE;
            const char *text = (*env)->GetStringUTFChars(env, s, NULL);
            if (!text) return ROOT_UNAVAILABLE;
            char *target = group ? r.prefix[i] : r.map[i];
            size_t cap = group ? sizeof(r.prefix[i]) : sizeof(r.map[i]);
            size_t bytes = strlen(text);
            if (!bytes || bytes >= cap || strchr(text, '\n')) {
                (*env)->ReleaseStringUTFChars(env, s, text); return ROOT_UNAVAILABLE;
            }
            memcpy(target, text, bytes + 1);
            (*env)->ReleaseStringUTFChars(env, s, text); (*env)->DeleteLocalRef(env, s);
        }
    }
    if (!guard) return ROOT_UNAVAILABLE;
    jclass type = (*env)->GetObjectClass(env, guard);
    jmethodID method = (*env)->GetMethodID(env, type, "allow", "()Z");
    if (!method || (*env)->ExceptionCheck(env)) return ROOT_UNAVAILABLE;
    struct root_jni_guard callback = {env, guard, method};
    return root_stop_idle_guarded(&r, root_allow_java, &callback);
}
#endif
