// Original Broomm Linux process adapter. Dart owns package/workflow decisions.
// Run a reviewed native tool with writes confined before its first instruction.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <sys/socket.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <unistd.h>
#include "linux_write_policy.h"

static volatile sig_atomic_t interrupted, child_group;
static void stop(int signal) {
    interrupted=signal;
    if(child_group>0)kill(-(pid_t)child_group,SIGKILL);
}
static void drain_adopted(void) {
    char path[128];snprintf(path,sizeof(path),"/proc/self/task/%d/children",getpid());
    FILE *children=fopen(path,"r");if(!children)return;int pid;
    while(fscanf(children,"%d",&pid)==1) {
        int handle=(int)syscall(SYS_pidfd_open,pid,0);if(handle<0)continue;
        snprintf(path,sizeof(path),"/proc/%d/stat",pid);FILE *state=fopen(path,"r");char line[4096];int parent=0;
        if(state){if(fgets(line,sizeof(line),state)){char *name=strrchr(line,')');if(name)sscanf(name+2,"%*c %d",&parent);}fclose(state);}
        // A retained kernel handle pins identity; an exited PID can never
        // redirect a signal to another process. Only our adopted children count.
        if(parent==getpid())syscall(SYS_pidfd_send_signal,handle,SIGKILL,NULL,0);
        close(handle);
    }
    fclose(children);
}
static bool offline_installer(void) {
    if(!getenv("BROOMM_INSTALLER_ROOT"))return true;
#if defined(__x86_64__)
    const unsigned architecture=AUDIT_ARCH_X86_64;
#elif defined(__aarch64__)
    const unsigned architecture=AUDIT_ARCH_AARCH64;
#else
    return false;
#endif
    struct sock_filter code[]={
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,arch)),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,architecture,1,0),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,SYS_socket,0,4),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,args[0])),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AF_INET,1,0),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,AF_INET6,0,1),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EACCES),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program={.len=sizeof(code)/sizeof(code[0]),.filter=code};
    return prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&program)==0;
}
int main(int argc,char **argv) {
    if(argc<4||argv[1][0]!='/'||argv[2][0]!='/'||argv[3][0]!='/') {
        fputs("Broomm native process needs absolute root, working directory and executable paths.\n",stderr);
        return 64;
    }
    char root[PATH_MAX],cwd[PATH_MAX],program[PATH_MAX];struct stat info;
    if(!realpath(argv[1],root)||!realpath(argv[2],cwd)||!realpath(argv[3],program)||
       strncmp(cwd,root,strlen(root))||(cwd[strlen(root)]&&cwd[strlen(root)]!='/')||
       stat(program,&info)||!S_ISREG(info.st_mode)||chdir(cwd))return 73;
    const char *lock_path=getenv("BROOMM_WRITER_LOCK");
    int lock=-1;
    if(lock_path) {
        lock=open(lock_path,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
        struct flock region={.l_type=F_WRLCK,.l_whence=SEEK_SET};
        // An open-file-description lock survives fork/exec and conflicts with
        // Dart's POSIX whole-file lock. Every surviving descendant retains it.
        if(lock<0||fcntl(lock,F_OFD_SETLK,&region))return 73;
    }
    if(prctl(PR_SET_CHILD_SUBREAPER,1,0,0,0))return 73;
    struct sigaction action={.sa_handler=stop};sigemptyset(&action.sa_mask);
    sigaction(SIGTERM,&action,NULL);sigaction(SIGINT,&action,NULL);
    pid_t child=fork();
    if(child<0)return 73;
    if(!child) {
        setpgid(0,0);
        if(prctl(PR_SET_PDEATHSIG,SIGKILL)||getppid()==1)_exit(73);
        if(!private_writes(root)){
            fprintf(stderr,"Broomm private archive writes unavailable: %s. The kernel must support Landlock ABI 3 or unprivileged user/mount namespaces.\n",strerror(errno));
            _exit(73);
        }
        if(!offline_installer())_exit(73);
        // Bound a single extracted file and handle count. Dart verifies the
        // exact complete inventory, cumulative bytes and links before publish.
        // RPCS3's reviewed VM startup creates a 32 GiB sparse backing file,
        // even for --installfw. Archive extraction retains its 8 GiB ceiling;
        // native installers also retain Dart's content/inventory limits.
        rlim_t limit=(getenv("BROOMM_INSTALLER_ROOT")?32ULL:8ULL)*1024*1024*1024;
        struct rlimit size={limit,limit};
        struct rlimit handles={1024,1024};
        struct rlimit cores={0,0};
        if(setrlimit(RLIMIT_FSIZE,&size)||setrlimit(RLIMIT_NOFILE,&handles)||setrlimit(RLIMIT_CORE,&cores))_exit(73);
        execv(program,argv+3);
        _exit(74);
    }
    child_group=child;setpgid(child,child);
    if(interrupted)kill(-child,SIGKILL);
    int status=0,answer=74;bool original_seen=false;
    for(;;) {
        if(original_seen||interrupted){kill(-child,SIGKILL);drain_adopted();}
        pid_t ended=waitpid(-1,&status,WNOHANG);
        if(!ended){usleep(20000);continue;}
        if(ended<0&&errno==EINTR)continue;
        if(ended<0&&errno==ECHILD)break;
        if(ended<0){answer=74;break;}
        if(ended==child){original_seen=true;answer=WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
            if(WIFSIGNALED(status))fprintf(stderr,"Broomm native tool ended with signal %d.\n",WTERMSIG(status));}
        // A tool must not daemonize past completion. Drain its process group.
        if(original_seen)kill(-child,SIGKILL);
    }
    if(lock>=0)close(lock);
    return interrupted?128+interrupted:answer;
}
