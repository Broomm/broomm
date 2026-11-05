// Narrow native CLI teardown/Dolphin interop. Dart owns staging, validation,
// cancellation, persistence and publication. The native-run parent holds locks
// and kernel write confinement before this reviewed application executes.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static bool enabled;
static _Atomic bool linux_active;
static void import_wad(void);
#define linux_ui_tick import_wad
#define record(...) do {fprintf(stderr,"Broomm installer: ");fprintf(stderr,__VA_ARGS__);fputc('\n',stderr);} while(0)
#include "linux_qt_timer.inc"
static uintptr_t slide;
static int image(struct dl_phdr_info *info,size_t size,void *context){(void)size;(void)context;if(!info->dlpi_name[0])slide=info->dlpi_addr;return 0;}
__attribute__((constructor))static void initialize(void) {
 const char *expected=getenv("BROOMM_SESSION_EXECUTABLE"),*root=getenv("BROOMM_INSTALLER_ROOT");
 if(!expected||!root)return;char executable[4096];ssize_t n=readlink("/proc/self/exe",executable,sizeof(executable)-1);if(n<=0)return;executable[n]=0;
 if(strcmp(executable,expected))return;enabled=true;atomic_store(&linux_active,true);dl_iterate_phdr(image,NULL);
}
__attribute__((noreturn))void abort(void) {
 const char *mode=getenv("BROOMM_INSTALLER_ABORT_MODE");
 if(enabled&&mode&&!strcmp(mode,"rpcs3-cli-v1")){static const char text[]="\nBROOMM_RPCS3_CLI_ABORT_V1\n";ssize_t written=write(2,text,sizeof(text)-1);_exit(written==(ssize_t)sizeof(text)-1?86:87);}
 void (*next)(void)=dlsym(RTLD_NEXT,"abort");next();_exit(134);
}
static void import_wad(void) {
 static bool working;if(!enabled||working||syscall(SYS_gettid)!=getpid()||!getenv("BROOMM_DOLPHIN_WAD"))return;
 void **app=dlsym(RTLD_DEFAULT,"_ZN16QCoreApplication4selfE");
 struct Array{void *allocation;void **data;long size;};struct Array (*widgets)(void)=dlsym(RTLD_DEFAULT,"_ZN12QApplication15topLevelWidgetsEv");
 const char *(*name)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK11QMetaObject9classNameEv");
 if(!app||!*app||!widgets||!name)return;struct Array top=widgets();bool ready=false;
 if(top.size>=0&&top.size<256)for(long i=0;i<top.size;++i){void *object=top.data[i];const void *(*meta)(void *)=(void *)((void **)*(void ***)object)[0];if(!strcmp(name(meta(object)),"MainWindow"))ready=true;}
 if(top.allocation&&__atomic_fetch_sub((int *)top.allocation,1,__ATOMIC_ACQ_REL)==1){void (*release)(void *,long long,long long)=dlsym(RTLD_DEFAULT,"_ZN10QArrayData10deallocateEPS_xx");if(release)release(top.allocation,sizeof(void *),_Alignof(void *));else free(top.allocation);}
 if(!ready)return;working=true;
 const char *map=getenv("BROOMM_SYMBOL_FILE");FILE *file=map?fopen(map,"r"):NULL;uintptr_t address=0;
 if(file){unsigned long long value;char symbol[160];int count=0;while(++count<4000&&fscanf(file,"%llx %159s",&value,symbol)==2)if(!strcmp(symbol,"_ZN8WiiUtils10InstallWADERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE"))address=slide+value;fclose(file);}
 if(!address)_exit(80);
 const char *path=getenv("BROOMM_DOLPHIN_WAD");
 // Reviewed Linux GCC C++11 std::string const-reference layout. The importer
 // reads this long representation synchronously and never takes its ownership.
 struct {const char *data;size_t size;union{size_t capacity;char local[16];} storage;} text={.data=path,.size=strlen(path),.storage={.capacity=strlen(path)}};
 bool result=((bool(*)(const void *))address)(&text);
 if(result){static const char ok[]="BROOMM_DOLPHIN_WAD_V1_OK\n";if(write(1,ok,sizeof(ok)-1)!=(ssize_t)sizeof(ok)-1)_exit(82);}_exit(result?0:81);
}
