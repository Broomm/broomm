// OS interop only. Dart owns Cemu configuration, input, saves and supervision.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libproc.h>
#else
#include <link.h>
#include "linux_write_policy.h"
#endif

extern void broomm_cemu_window_tick(bool playing, bool quit, uint64_t request);
extern void broomm_cemu_window_initialize(void);
extern bool broomm_cemu_window_ready(void);
extern bool broomm_cemu_application_ready(void);
extern bool broomm_cemu_window_geometry(double out[5]);
static int writer_fd = -1;
static const char *status_path, *command_path, *nonce;
static unsigned long long revision, birth_seconds, birth_microseconds;
static unsigned long long sample;
static char birth_ticks[32];
static bool active, quitting;
static pid_t launcher;
static volatile sig_atomic_t normal_quit;
static void request_quit(int signal) { (void)signal;normal_quit=1; }

static bool identity(void) {
#ifdef __APPLE__
  struct proc_bsdinfo info;
  if (proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return false;
  birth_seconds = info.pbi_start_tvsec; birth_microseconds = info.pbi_start_tvusec;
#else
  FILE *file = fopen("/proc/self/stat", "r"); char line[4096];
  if (!file) return false;
  char *read = fgets(line, sizeof(line), file); fclose(file);
  char *tail = read ? strrchr(line, ')') : NULL;
  if (!tail) return false;
  char *save = NULL, *token = strtok_r(tail + 2, " ", &save);
  for (int field = 3; token; ++field, token = strtok_r(NULL, " ", &save)) {
    if (field == 22) {
      if (strlen(token) >= sizeof(birth_ticks) || strspn(token, "0123456789") != strlen(token)) return false;
      strcpy(birth_ticks, token); return true;
    }
  }
  return false;
#endif
  return true;
}

static bool publish(uint64_t title, int paused) {
  char pending[4096];
  if (snprintf(pending, sizeof(pending), "%s.XXXXXX", status_path) >= (int)sizeof(pending)) return false;
  int fd = mkstemp(pending);
  if (fd < 0) return false;
  FILE *file = fdopen(fd, "w");
  if (!file) { close(fd); unlink(pending); return false; }
  int result = fprintf(file,
    "{\"version\":1,\"pid\":%d,\"token\":\"%s\",\"ack\":%llu,\"sample\":%llu,\"applicationReady\":%s,\"paused\":%d,"
    "\"title\":\"%016llx\",\"seconds\":%llu,\"microseconds\":%llu,\"birth\":\"%s\",\"remoteCapture\":[",
    getpid(), nonce, revision, ++sample, broomm_cemu_application_ready()?"true":"false", paused, (unsigned long long)title, birth_seconds, birth_microseconds, birth_ticks);
  double geometry[5];bool failed=result<0;
  if(broomm_cemu_window_geometry(geometry))for(int i=0;i<5;++i)if(fprintf(file,"%s%.4f",i?",":"",geometry[i])<0)failed=true;
  if(fputs("]}\n",file)==EOF)failed=true;
  if (fclose(file) || failed || rename(pending, status_path)) { unlink(pending); return false; }
  return true;
}

#ifndef __APPLE__
static int bind_symbols(struct dl_phdr_info *image, size_t size, void *context) {
  (void)size;
  if (image->dlpi_name[0]) return 0;
  uintptr_t *addresses=context;
  const char *names[]={"BROOMM_CEMU_RUNNING","BROOMM_CEMU_TITLE"};
  for(int n=0;n<2;++n) {
    const char *value=getenv(names[n]); char *end=NULL;
    if(!value||!*value||strlen(value)>16)return 1;
    unsigned long long offset=strtoull(value,&end,16);
    if(!end||*end||offset>UINTPTR_MAX-image->dlpi_addr)return 1;
    for(int i=0;i<image->dlpi_phnum;++i) {
      const ElfW(Phdr) *segment=&image->dlpi_phdr[i];
      if(segment->p_type==PT_LOAD&&(segment->p_flags&PF_W)&&offset>=segment->p_vaddr&&
          offset-segment->p_vaddr<=segment->p_memsz&&segment->p_memsz-(offset-segment->p_vaddr)>=8)
        addresses[n]=image->dlpi_addr+(uintptr_t)offset;
    }
  }
  return 1;
}
#endif

static void command(void) {
  FILE *file = fopen(command_path, "r");
  if (!file) return;
  char token[65], extra; unsigned long long next; int play, quit;
  int count = fscanf(file, "%64s %llu %d %d %c", token, &next, &play, &quit, &extra);
  fclose(file);
  if (count != 4 || strcmp(token, nonce) || next <= revision ||
      (play != 0 && play != 1) || (quit != 0 && quit != 1)) return;
  revision = next; active = play != 0; quitting = quit != 0;
}

static void *worker(void *unused) {
  (void)unused;
  uint64_t (*title_id)(void) = dlsym(RTLD_DEFAULT, "gameMeta_getTitleId");
  const uint64_t *native_title = dlsym(RTLD_DEFAULT, "_ZN10CafeSystem18sForegroundTitleIdE");
  const bool *native_running = dlsym(RTLD_DEFAULT, "_ZN10CafeSystem14sSystemRunningE");
#ifndef __APPLE__
  if(!native_title||!native_running) {
    uintptr_t addresses[2]={0};dl_iterate_phdr(bind_symbols,addresses);
    native_running=(const bool *)addresses[0];native_title=(const uint64_t *)addresses[1];
  }
#endif
  if (!title_id && (!native_title || !native_running)) _exit(78);
  for (;;) {
    command();
    const char *supervised=getenv("BROOMM_CEMU_SUPERVISED");
    if(normal_quit || (supervised && !strcmp(supervised,"1") && getppid()!=launcher)) {quitting=true;active=false;}
    uint64_t title = native_title && native_running ?
      (__atomic_load_n(native_running,__ATOMIC_ACQUIRE) ? __atomic_load_n(native_title,__ATOMIC_ACQUIRE) : 0) : title_id();
    broomm_cemu_window_tick(active, quitting, revision);
    if(!broomm_cemu_window_ready()) title=0;
    // The host confirms suspension through the kernel, never a status flag.
    // Diagnostic publication must not abort a game or compromise its saves.
    if(!publish(title, 0)) {
      static unsigned failures;
      if((failures++ % 160)==0)fputs("Broomm Cemu status publication failed; local progress remains owned.\n",stderr);
    }
    usleep(32000);
  }
  return NULL;
}

__attribute__((constructor)) static void initialize(void) {
  const char *path = getenv("BROOMM_CEMU_WRITER");
  if (!path) return;
  status_path = getenv("BROOMM_CEMU_STATUS"); command_path = getenv("BROOMM_CEMU_COMMAND"); nonce = getenv("BROOMM_CEMU_TOKEN");
  if (!status_path || !command_path || !nonce || strlen(nonce) != 64 || strspn(nonce,"0123456789abcdef") != 64 || !identity()) _exit(78);
  writer_fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
  struct stat info; struct flock lock = {.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
  if (writer_fd < 0 || fstat(writer_fd,&info) || !S_ISREG(info.st_mode) || fcntl(writer_fd,F_SETLK,&lock)) _exit(78);
#ifndef __APPLE__
  if (!private_writes(getenv("BROOMM_CEMU_ROOT"))) _exit(78);
#endif
  broomm_cemu_window_initialize();
  launcher=getppid();
#ifndef __APPLE__
  struct sigaction close_action={.sa_handler=request_quit};sigemptyset(&close_action.sa_mask);
  if(sigaction(SIGTERM,&close_action,NULL)||sigaction(SIGINT,&close_action,NULL))_exit(78);
#else
  (void)request_quit;
#endif
  pthread_t thread;
  if (pthread_create(&thread,NULL,worker,NULL)) _exit(78);
  pthread_detach(thread);
  // Keep writer_fd open through native teardown, including launcher death.
}
