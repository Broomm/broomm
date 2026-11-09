/* Linux/Android production-kernel tests. Every effect targets a disposable
 * cooperating child; no emulator, global ptrace policy or persistent file. */
#define BROOMM_PROCESS_TEST
#include "../../android/app/src/main/cpp/root_process.c"
#include <assert.h>
#include <pthread.h>

static volatile uint32_t test_pending;
static int freeze_notice = -1, freeze_release = -1;
static int concurrent_stop;
static int refuse_parent(void *value) {
    const struct root_stop_request *r=value;
    char path[96], status[4096];pid_t tids[16];root_path(path,sizeof(path),r->pid,"task");
    int n=root_names(path,tids,16);assert(n==4);
    for(int i=0;i<n;i++) {
        root_path(path,sizeof(path),tids[i],"status");assert(root_read(path,status,sizeof(status)-1)>0);
        char *state=strstr(status,"\nState:");assert(state);state+=7;while(*state==' '||*state=='\t')++state;
        assert(*state=='t');
    }
    return 0;
}
void root_test_before_attach(pid_t tid, pid_t pid) {
    if (!concurrent_stop || tid != pid) return;
    concurrent_stop = 0; assert(!kill(pid, SIGSTOP));
    int64_t end = root_millis() + 1000;
    while (root_available(pid) && root_millis() < end) {
        struct timespec pause = {0, 1000000}; nanosleep(&pause, NULL);
    }
    assert(!root_available(pid));
}
static void *test_worker(void *value) {
    (void)value;
    for (;;) pause();
    return NULL;
}
void root_test_frozen(void) {
    if (freeze_notice < 0) return;
    char b = 'F'; assert(write(freeze_notice, &b, 1) == 1);
    assert(read(freeze_release, &b, 1) == 1);
}
struct target { pid_t pid; int commands, reply; struct root_stop_request request; };
static struct target target_start(uint32_t pending) {
    int to[2], from[2]; assert(!pipe(to) && !pipe(from));
    pid_t pid = fork(); assert(pid >= 0);
    if (!pid) {
        close(to[1]); close(from[0]);
        assert(!prctl(PR_SET_PDEATHSIG, SIGKILL, 0L, 0L, 0L));
        int tracer = prctl(PR_SET_PTRACER, PR_SET_PTRACER_ANY, 0L, 0L, 0L);
#ifdef __ANDROID__
        /* Android kernels without Yama return EINVAL for its per-child opt-in.
         * Root still has to pass the actual ptrace checks below. */
        assert(!tracer || errno == EINVAL);
#else
        assert(!tracer);
#endif
        test_pending = pending;
        pthread_t workers[3];
        for (int i = 0; i < 3; ++i) assert(!pthread_create(&workers[i], NULL, test_worker, NULL));
        char file[] = "/data/local/tmp/broomm-kernel-XXXXXX";
#ifndef __ANDROID__
        strcpy(file, "/tmp/broomm-kernel-XXXXXX");
#endif
        int held = mkstemp(file); assert(held >= 0); assert(!unlink(file));
        char value = 'R'; assert(write(from[1], &value, 1) == 1);
        while (read(to[0], &value, 1) == 1) {
            if (value == '0') test_pending = 0;
            if (value == '1') test_pending = 1;
            if (value == 'C') { assert(!close(held)); held = -1; }
            assert(write(from[1], &value, 1) == 1);
        }
        if (held >= 0) close(held);
        _exit(0);
    }
    close(to[0]); close(from[1]);
    char ready; assert(read(from[0], &ready, 1) == 1 && ready == 'R');
    struct target t = {.pid = pid, .commands = to[1], .reply = from[0]};
    t.request.pid = pid; t.request.start_ticks = root_ticks(pid);
    t.request.guards = 1; t.request.guard[0].address = (uint64_t)(uintptr_t)&test_pending;
    t.request.guard[0].bytes = sizeof(test_pending); t.request.maps = 1; t.request.prefixes = 1;
    strcpy(t.request.prefix[0], "/broomm-disposable-test-no-files/");
    char path[64], maps[65536]; root_path(path, sizeof(path), pid, "maps");
    assert(root_read(path, maps, sizeof(maps) - 1) > 0);
    char *line = maps;
    while (*line) {
        char *end = strchr(line, '\n'); assert(end);
        unsigned long long first, last;
        assert(sscanf(line, "%llx-%llx", &first, &last) == 2);
        if (first <= t.request.guard[0].address && t.request.guard[0].address + 4 <= last) {
            assert((size_t)(end - line) < sizeof(t.request.map[0]));
            memcpy(t.request.map[0], line, (size_t)(end - line)); break;
        }
        line = end + 1;
    }
    assert(t.request.map[0][0]); return t;
}
static void target_reply(struct target *t, char command) {
    char got; assert(write(t->commands, &command, 1) == 1);
    struct pollfd p = {t->reply, POLLIN, 0}; assert(poll(&p, 1, 2000) == 1);
    assert(read(t->reply, &got, 1) == 1 && got == command);
}
static void target_finish(struct target *t) {
    close(t->commands); close(t->reply);
    int status; assert(waitpid(t->pid, &status, 0) == t->pid);
}
int main(void) {
    struct target busy = target_start(1);
    assert(root_stop_idle(&busy.request) == ROOT_BUSY);
    target_reply(&busy, '?'); /* Rejected writer resumes normally. */
    target_reply(&busy, '0');
    assert(root_stop_idle(&busy.request) == ROOT_STOPPED);
    target_finish(&busy);
    puts("PASS held writer refused/resumed; completed writer safely disposed");

    struct target changed = target_start(0);
    struct root_stop_request wrong = changed.request;
    wrong.start_ticks++;
    assert(root_stop_idle(&wrong) == ROOT_CHANGED);
    target_reply(&changed, '1'); /* Arrival after the caller's idle snapshot. */
    assert(root_stop_idle(&changed.request) == ROOT_BUSY);
    target_reply(&changed, '?');
    target_reply(&changed, '0');
    wrong = changed.request; strcpy(wrong.map[0], "foreign mapping");
    assert(root_stop_idle(&wrong) == ROOT_CHANGED);
    target_reply(&changed, '?');
    target_finish(&changed);
    puts("PASS lifetime/mapping conflict and new writer preserve the target");

    struct target parent = target_start(0);
    assert(root_stop_idle_guarded(&parent.request, refuse_parent, &parent.request) == ROOT_BUSY);
    target_reply(&parent, '?'); target_finish(&parent);
    puts("PASS fresh parent lifecycle refusal resumes every frozen thread");

    struct target file = target_start(0);
    struct root_stop_request writable = file.request;
#ifdef __ANDROID__
    strcpy(writable.prefix[0], "/data/local/tmp/broomm-kernel-");
#else
    strcpy(writable.prefix[0], "/tmp/broomm-kernel-");
#endif
    assert(root_stop_idle(&writable) == ROOT_WRITABLE);
    target_reply(&file, '?');
    assert(!kill(file.pid, SIGSTOP));
    int stopped; assert(waitpid(file.pid, &stopped, WUNTRACED) == file.pid && WIFSTOPPED(stopped));
    assert(root_stop_idle(&file.request) == ROOT_BUSY);
    assert(!kill(file.pid, SIGCONT)); target_reply(&file, 'C');
    assert(root_stop_idle(&writable) == ROOT_STOPPED); target_finish(&file);
    puts("PASS open writable save refused; foreign stop preserved; all threads released");

    struct target racing = target_start(0);
    concurrent_stop = 1;
    int conflict = root_stop_idle(&racing.request); concurrent_stop = 0;
    assert(conflict == ROOT_BUSY || conflict == ROOT_CHANGED);
    assert(!root_available(racing.pid));
    assert(!kill(racing.pid, SIGCONT)); target_reply(&racing, '?'); target_finish(&racing);
    puts("PASS concurrent foreign stop refused without killing or resuming its target");

    struct target interrupted = target_start(0);
    int notice[2], release[2]; assert(!pipe(notice) && !pipe(release));
    pid_t owner = fork(); assert(owner >= 0);
    if (!owner) {
        close(notice[0]); close(release[1]); freeze_notice = notice[1]; freeze_release = release[0];
        (void)root_stop_idle(&interrupted.request); _exit(1);
    }
    close(notice[1]); close(release[0]);
    char frozen; struct pollfd p = {notice[0], POLLIN, 0}; assert(poll(&p, 1, 3000) == 1);
    assert(read(notice[0], &frozen, 1) == 1 && frozen == 'F');
    assert(!kill(owner, SIGKILL)); int status; assert(waitpid(owner, &status, 0) == owner);
    target_reply(&interrupted, '?'); /* Kernel tracer-death detach must resume it. */
    close(notice[0]); close(release[1]); target_finish(&interrupted);
    puts("PASS interrupted root owner cannot strand a frozen target");
    return 0;
}
