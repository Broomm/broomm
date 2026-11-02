// Original Broomm Linux SDL input bridge. No emulator or SDL implementation copied.
#define _GNU_SOURCE
#define BROOMM_SESSION_BRIDGE 1
#include <dlfcn.h>
#include <link.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <math.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include "ownership.inc"
#include "linux_write_policy.h"
#include "pause_transition.h"
// POSIX shared memory is process infrastructure, not a global emulator setting.
// Redirect this emulator's named mappings into its private launch directory;
// granting write access to the system-wide /dev/shm would weaken confinement.
static const char *private_shm_root;
static bool shm_path(const char *name,char path[4096]) {
 if(!name)return false;if(name[0]=='/')++name;
 if(!*name||strlen(name)>240)return false;
 for(const char *p=name;*p;++p)if(!((*p>='a'&&*p<='z')||(*p>='A'&&*p<='Z')||(*p>='0'&&*p<='9')||*p=='_'||*p=='-'||*p=='.'))return false;
 return snprintf(path,4096,"%s/cache/shm-%s",private_shm_root,name)<4096;
}
int shm_open(const char *name,int flags,mode_t mode) {
 if(!private_shm_root){int (*next)(const char *,int,mode_t)=dlsym(RTLD_NEXT,"shm_open");return next(name,flags,mode);}
 char path[4096];if(!shm_path(name,path)){errno=EINVAL;return -1;}
 return open(path,flags|O_CLOEXEC|O_NOFOLLOW,mode);
}
int shm_unlink(const char *name) {
 if(!private_shm_root){int (*next)(const char *)=dlsym(RTLD_NEXT,"shm_unlink");return next(name);}
 char path[4096];if(!shm_path(name,path)){errno=EINVAL;return -1;}return unlink(path);
}
static uintptr_t image_slide;
static int find_image(struct dl_phdr_info *i,size_t n,void *data) {
 (void)n;(void)data;if(!i->dlpi_name[0])image_slide=i->dlpi_addr;return 0;
}
static void linux_dispatch(void *,void (*)(void *));
static void linux_ui_tick(void);
#define dispatch_get_main_queue() NULL
#define dispatch_async_f(queue,context,callback) linux_dispatch(context,callback)
static void install_motion_hooks(void);
static int fixture_index(void *,bool);
static bool hook(const char *,void *,void **);
static _Atomic int psp_test_key,test_native_pause_action;
#define pthread_main_np() (syscall(SYS_gettid)==getpid())
static void *symbol(const char *);
static void record_at(int,const char *,...);
#define record(...) record_at(__LINE__,__VA_ARGS__)

#include "linux_input.inc"
#include "linux_control.inc"
#include "linux_ui.inc"
#include "linux_session.inc"
static void stop_sampling(void) {
 if(!atomic_load(&linux_active))return;
 atomic_store(&session_finishing,true);
 for(int i=0;i<5000&&(!atomic_load(&session_worker_stopped)||!atomic_load(&control_finished));++i)usleep(1000);
 if(!atomic_load(&session_worker_stopped)||!atomic_load(&control_finished))_exit(74);
}
static void (*native_quit)(void),(*native_quit_subsystem)(uint32_t);
static void linux_quit(void){stop_sampling();if(native_quit)native_quit();}
static void linux_quit_subsystem(uint32_t flags){if(flags&0x200)stop_sampling();if(native_quit_subsystem)native_quit_subsystem(flags);}
static void *worker(void *unused) {
 (void)unused;
 const char *library=getenv("BROOMM_SDL_LIBRARY");
 if(library) {
  for(int n=0;n<1200&&!sdl&&!atomic_load(&session_finishing);++n){sdl=dlopen(library,RTLD_NOW|RTLD_NOLOAD);if(!sdl)usleep(50000);}
  if(!sdl){record("SESSION_FATAL reviewed SDL library did not load");atomic_store(&session_worker_stopped,true);return NULL;}
 }
 initialize_dispatch();
 if(!api_table||!abi_valid){record("SESSION_FATAL SDL public dispatch table unverified");atomic_store(&session_worker_stopped,true);return NULL;}
 install_hooks();
 hook("SDL_Quit",linux_quit,(void **)&native_quit);
 hook("SDL_QuitSubSystem",linux_quit_subsystem,(void **)&native_quit_subsystem);
 uint32_t (*was_init)(uint32_t)=resolve_was_init();
 if(!was_init){atomic_store(&session_worker_stopped,true);return NULL;}
 for(int n=0;n<1200&&!atomic_load(&session_finishing);++n){if(was_init(0)&0x200)break;usleep(50000);}
 if(!atomic_load(&session_finishing))session_worker();
 atomic_store(&session_worker_stopped,true);return NULL;
}
__attribute__((constructor))static void linux_start(void) {
 const char *expected=getenv("BROOMM_SESSION_EXECUTABLE");
 const char *root=getenv("BROOMM_CONFIGURATION_ROOT");
 bool configuration=root!=NULL;
 if(!expected||(!configuration&&!getenv("BROOMM_SESSION")))return;
 char actual[4096];ssize_t n=readlink("/proc/self/exe",actual,sizeof(actual)-1);if(n<=0)return;actual[n]=0;
 if(strcmp(actual,expected))return;
 if(configuration) {
  const char *path=getenv("BROOMM_CONFIGURATION_SESSION_LOCK");
  int fd=path?open(path,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600):-1;
  struct flock region={.l_type=F_WRLCK,.l_whence=SEEK_SET};
  if(fd<0||fcntl(fd,F_SETLK,&region))_exit(73);
 }
 acquire_session_writer();
 if(!root)root=getenv("BROOMM_LINUX_PROFILE");
 if(!private_writes(root)){fputs("Broomm: private Linux emulator writes unavailable.\n",stderr);_exit(73);}
 private_shm_root=root;
 log_path=getenv("BROOMM_PROBE_LOG");record("Linux private writes active configuration=%d",configuration);
 if(configuration)return;
 dl_iterate_phdr(find_image,NULL);
 const char *path=getenv("BROOMM_SYMBOL_FILE");FILE *symbols=path?fopen(path,"r"):NULL;
 if(symbols){unsigned long long address;char name[160];while(symbol_count<4000&&fscanf(symbols,"%llx %159s",&address,name)==2){struct SymbolEntry *e=&symbol_entries[symbol_count++];snprintf(e->name,sizeof(e->name),"%s",name);e->address=address+image_slide;}fclose(symbols);}
 const char *table=getenv("BROOMM_SDL_TABLE");if(table)api_table=(void **)(strtoull(table,NULL,16)+image_slide);
 const char *status=getenv("BROOMM_EMU_STATUS");if(status)rpcs_status=(void *)(strtoull(status,NULL,16)+image_slide);
 rpcs_ftotal=symbol("g_progr_ftotal");rpcs_fdone=symbol("g_progr_fdone");rpcs_ptotal=symbol("g_progr_ptotal");rpcs_pdone=symbol("g_progr_pdone");rpcs_ftotal_bits=symbol("g_progr_ftotal_bits");rpcs_fknown_bits=symbol("g_progr_fknown_bits");
 core_system_fn=symbol("_ZN4Core6System11GetInstanceEv");core_state_fn=symbol("_ZN4Core8GetStateERNS_6SystemE");core_set_state_fn=symbol("_ZN4Core8SetStateERNS_6SystemENS_5StateEbb");
 atomic_store(&linux_active,true);start_control();pthread_t thread;
 if(pthread_create(&thread,NULL,worker,NULL))_exit(73);pthread_detach(thread);
}
__attribute__((destructor))static void linux_finish(void){stop_sampling();}
