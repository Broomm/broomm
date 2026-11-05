#define _GNU_SOURCE 1
#include "../../linux/runner/process_identity.h"
#include "../../native/linux_write_policy.h"
#include "../../native/linux_window_handoff.h"
#include <sys/wait.h>
#include <signal.h>
#include <cassert>
#include <cstring>
#include <cstdlib>

using namespace broomm_host;
static void exited(pid_t child, int code=0) {
  int status=0;assert(waitpid(child,&status,0)==child);
  assert(WIFEXITED(status)&&WEXITSTATUS(status)==code);
}
static int locked(const std::string& path) {
  int fd=open(path.c_str(),O_CREAT|O_RDWR|O_CLOEXEC,0600);assert(fd>=0);
  struct flock lock={};lock.l_type=F_WRLCK;lock.l_whence=SEEK_SET;
  assert(fcntl(fd,F_SETLK,&lock)==0);return fd;
}
int main(int argc,char** argv) {
  assert(argc==2);std::string root=argv[1],path=root+"/coordinator";
  const auto launcher = root + "/mapped-launcher";
  assert(!broomm_hide_game_window(true, false, launcher.c_str()));
  int mapped = open(launcher.c_str(), O_CREAT | O_WRONLY, 0600);
  assert(mapped >= 0);
  close(mapped);
  assert(broomm_hide_game_window(true, false, launcher.c_str()));
  assert(!broomm_hide_game_window(false, false, launcher.c_str()));
  assert(!broomm_hide_game_window(true, true, launcher.c_str()));
  assert(unlink(launcher.c_str()) == 0);
  assert(!broomm_hide_game_window(true, false, launcher.c_str()));
  assert(broomm_hide_game_window(true, false, nullptr));
  puts("PASS: Gamescope hides a gated emulator only after launcher handoff");
  int fd=locked(path);const auto owner=lock_owner(path);assert(owner.pid==getpid());
  struct stat actual;assert(fstat(fd,&actual)==0);Lock target;
  target.major=major(actual.st_dev);target.minor=minor(actual.st_dev);target.inode=actual.st_ino;
  assert(descriptor_lock(owner,target));
  target.inode++;assert(!descriptor_lock(owner,target));
  // Inspection must not release the caller's own POSIX lock.
  for(int i=0;i<3;++i)assert(lock_owner(path)==owner);
  pid_t child=fork();assert(child>=0);
  if(!child){int other=open(path.c_str(),O_RDWR);struct flock lock={};lock.l_type=F_WRLCK;lock.l_whence=SEEK_SET;
    assert(fcntl(other,F_SETLK,&lock)<0&&(errno==EACCES||errno==EAGAIN));_exit(0);}
  exited(child);close(fd);assert(lock_owner(path).pid==0);
  puts("PASS: kernel lock inspection preserves caller ownership");
  assert(symlink(path.c_str(),(root+"/linked").c_str())==0);
  bool rejected=false;try{lock_owner(root+"/linked");}catch(const std::string&){rejected=true;}assert(rejected);
  assert(lock_owner(root+"/absent").pid==0);
  puts("PASS: linked lock is uncertainty; missing/unheld lock is empty");
  int ready[2],release[2];assert(pipe(ready)==0&&pipe(release)==0);
  child=fork();assert(child>=0);
  if(!child){close(ready[0]);close(release[1]);int held=locked(path);assert(write(ready[1],"1",1)==1);
    char value;assert(read(release[0],&value,1)==1);close(held);_exit(0);}
  close(ready[1]);close(release[0]);char value;assert(read(ready[0],&value,1)==1);
  auto identity=process_birth(child);assert(!identity.empty());assert(lock_owner(path).pid==child);
  int handle=static_cast<int>(syscall(SYS_pidfd_open,child,0));assert(handle>=0);
  assert(write(release[1],"1",1)==1);exited(child);
  // A retained kernel handle cannot target an unrelated later process.
  pid_t unrelated=fork();assert(unrelated>=0);
  if(!unrelated){usleep(150000);_exit(0);}
  assert(syscall(SYS_pidfd_send_signal,handle,SIGTERM,nullptr,0)<0&&errno==ESRCH);
  exited(unrelated);close(handle);close(ready[0]);close(release[1]);
  puts("PASS: exited writer's retained pidfd cannot signal another process");
  std::string profile=root+"/profile",outside=root+"/preserved";
  assert(mkdir(profile.c_str(),0700)==0);
  fd=open(outside.c_str(),O_CREAT|O_WRONLY,0600);assert(fd>=0&&write(fd,"saved",5)==5);close(fd);
  assert(symlink(outside.c_str(),(profile+"/linked-save").c_str())==0);
  // Exercise the namespace backend even on Landlock-capable CI kernels.
  // Some hosts forbid unprivileged namespaces; establish that independently
  // before asserting the optional fallback, without masking later failures.
  child=fork();assert(child>=0);
  if(!child){if(unshare(CLONE_NEWUSER|CLONE_NEWNS)==0)_exit(0);
    assert(errno==EPERM||errno==ENOSYS||errno==EINVAL);_exit(77);}
  int probe=0;assert(waitpid(child,&probe,0)==child&&WIFEXITED(probe));
  bool namespaces=WEXITSTATUS(probe)==0;assert(namespaces||WEXITSTATUS(probe)==77);
  for(int backend=0;backend<2;++backend){
   if(backend==1&&!namespaces){puts("OBSERVED: host forbids the optional user/mount namespace backend");continue;}
   child=fork();assert(child>=0);
   if(!child){pid_t original_pid=getpid();uid_t original_uid=getuid();gid_t original_gid=getgid();
    assert(backend?namespace_private_writes(profile.c_str()):private_writes(profile.c_str()));
    assert(getpid()==original_pid&&getuid()==original_uid&&getgid()==original_gid);
    int output=open((profile+"/save").c_str(),O_CREAT|O_WRONLY,0600);assert(output>=0&&write(output,"local",5)==5);close(output);
    assert(open(outside.c_str(),O_WRONLY|O_TRUNC)<0&&(errno==EACCES||errno==EROFS));
    assert(open((root+"/escape").c_str(),O_CREAT|O_WRONLY,0600)<0&&(errno==EACCES||errno==EROFS));
    assert(open((profile+"/linked-save").c_str(),O_WRONLY|O_TRUNC)<0&&(errno==EACCES||errno==EROFS));
    assert(rename(outside.c_str(),(profile+"/stolen").c_str())<0);
    assert(unlink(outside.c_str())<0);
    int device=open("/dev/null",O_WRONLY);assert(device>=0);close(device);
    if(backend){
      assert(mount(nullptr,"/",nullptr,MS_BIND|MS_REMOUNT,nullptr)<0&&errno==EPERM);
      struct __user_cap_header_struct h={};h.version=_LINUX_CAPABILITY_VERSION_3;
      struct __user_cap_data_struct caps[2]={};assert(syscall(SYS_capget,&h,caps)==0);
      for(const auto& c:caps)assert(!c.permitted&&!c.effective&&!c.inheritable);
    }
    _exit(0);}
   exited(child);assert(file(outside)=="saved"&&file(profile+"/save")=="local");
   fd=open(outside.c_str(),O_WRONLY);assert(fd>=0);close(fd); // Parent mount table is unaffected.
  }
  assert(!namespace_private_writes("/")&&errno==EINVAL);
  assert(!namespace_private_writes(nullptr)&&errno==EINVAL);
  puts("PASS: native sandbox permits private saves and rejects outside creation/truncation/removal");
}
