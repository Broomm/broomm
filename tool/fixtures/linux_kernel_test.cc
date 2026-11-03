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
  child=fork();assert(child>=0);
  if(!child){assert(private_writes(profile.c_str()));
    int output=open((profile+"/save").c_str(),O_CREAT|O_WRONLY,0600);assert(output>=0&&write(output,"local",5)==5);close(output);
    assert(open(outside.c_str(),O_WRONLY|O_TRUNC)<0&&errno==EACCES);
    assert(open((root+"/escape").c_str(),O_CREAT|O_WRONLY,0600)<0&&errno==EACCES);
    assert(rename(outside.c_str(),(profile+"/stolen").c_str())<0);
    assert(unlink(outside.c_str())<0);_exit(0);}
  exited(child);assert(file(outside)=="saved"&&file(profile+"/save")=="local");
  puts("PASS: native sandbox permits private saves and rejects outside creation/truncation/removal");
}
