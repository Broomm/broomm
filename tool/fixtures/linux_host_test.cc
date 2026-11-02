#include "../../linux/runner/broomm_host.h"
#include <sys/wait.h>
#include <cassert>
#include <poll.h>

static int signal_fd=-1;
static void termination(int) { char value='1';(void)write(signal_fd,&value,1); }
static int locked(const std::string& path) {
  int fd=open(path.c_str(),O_CREAT|O_RDWR,0600);assert(fd>=0);
  struct flock lock={};lock.l_type=F_WRLCK;lock.l_whence=SEEK_SET;
  assert(fcntl(fd,F_SETLK,&lock)==0);return fd;
}
static std::string property(FlValue* value,const char* key) {
  auto* item=fl_value_lookup_string(value,key);assert(item);return fl_value_get_string(item);
}
int main(int argc,char** argv) {
  if(argc==4&&!strcmp(argv[1],"--stop")) {
    broomm_host::Host host{};g_autoptr(FlValue) value=broomm_host::inspect(&host,argv[2]);
    if(!value||property(value,"status")!="emulator") {
      fprintf(stderr,"Recovery fixture could not retain writer: %s\n",value?property(value,"message").c_str():"no live writer");
      const int writer=atoi(argv[3]);fprintf(stderr,"Fixture process birth=%s\n",broomm_host::process_birth(writer).c_str());
      struct stat info;assert(lstat((std::string(argv[2])+"/writer.lock").c_str(),&info)==0);
      fprintf(stderr,"Fixture writer dev=%x:%x inode=%llu\n",major(info.st_dev),minor(info.st_dev),static_cast<unsigned long long>(info.st_ino));
      std::istringstream rows(broomm_host::file("/proc/locks"));std::string row;
      while(std::getline(rows,row))if(row.find(" "+std::string(argv[3])+" ")!=std::string::npos)fprintf(stderr,"Fixture lock: %s\n",row.c_str());
      for(int i=0;i<128;++i)try {
        auto text=broomm_host::file("/proc/"+std::string(argv[3])+"/fdinfo/"+std::to_string(i));
        auto at=text.find("lock:");if(at!=std::string::npos)fprintf(stderr,"Fixture fd=%d %s\n",i,text.substr(at).c_str());
      }catch(const std::string&){}
      return 1;
    }
    broomm_host::control(&host,property(value,"token").c_str(),"stop");return 0;
  }
  if(argc==5&&!strcmp(argv[1],"--writer")) {
    signal_fd=atoi(argv[4]);signal(SIGTERM,termination);
    int fd=locked(std::string(argv[2])+"/writer.lock");
    assert(write(atoi(argv[3]),"1",1)==1);for(;;)pause();close(fd);return 0;
  }
  assert(argc==4);std::string root=argv[1],executable=argv[2],cwd=argv[3];
  broomm_host::Host host{};
  assert(broomm_host::inspect(&host,root.c_str())==nullptr);
  int coordinator=locked(root+"/session.lock");
  {g_autoptr(FlValue) result=broomm_host::inspect(&host,root.c_str());
    assert(property(result,"status")=="launcher");}
  // The production GTK adapter must preserve Dart's coordinator lock.
  assert(broomm_host::lock_owner(root+"/session.lock").pid==getpid());close(coordinator);
  int ready[2],signals[2];assert(pipe(ready)==0&&pipe(signals)==0);
  pid_t child=fork();assert(child>=0);
  if(!child){assert(chdir(cwd.c_str())==0);std::string r=std::to_string(ready[1]),s=std::to_string(signals[1]);
    execl(executable.c_str(),executable.c_str(),"--writer",root.c_str(),r.c_str(),s.c_str(),nullptr);_exit(127);}
  close(ready[1]);close(signals[1]);char value;assert(read(ready[0],&value,1)==1);
  std::string token;
  {g_autoptr(FlValue) result=broomm_host::inspect(&host,root.c_str());
    assert(property(result,"status")=="emulator");token=property(result,"token");}
  {g_autoptr(FlValue) result=broomm_host::inspect(&host,root.c_str());assert(property(result,"token")==token);}
  broomm_host::control(&host,token.c_str(),"show");
  assert(!broomm_host::file(cwd+"/bridge-recovery-show.txt").empty());
  const std::string canary=root+"/preserved",checkpoint=cwd+"/bridge-recovery-stop.txt";
  {std::ofstream file(canary);file<<"keep";}
  assert(symlink(canary.c_str(),checkpoint.c_str())==0);
  bool invalid=false;try{broomm_host::control(&host,token.c_str(),"stop");}catch(const std::string&){invalid=true;}
  struct pollfd observed={signals[0],POLLIN,0};assert(invalid&&poll(&observed,1,100)==0);
  assert(broomm_host::file(canary)=="keep");assert(unlink(checkpoint.c_str())==0);
  broomm_host::control(&host,token.c_str(),"stop");
  assert(read(signals[0],&value,1)==1);
  broomm_host::control(&host,token.c_str(),"stop");
  assert(poll(&observed,1,100)==0);
  broomm_host::Host restarted{};
  {g_autoptr(FlValue) result=broomm_host::inspect(&restarted,root.c_str());
    assert(property(result,"status")=="emulator");
    broomm_host::control(&restarted,property(result,"token").c_str(),"stop");}
  assert(poll(&observed,1,100)==0);
  puts("PASS: production host retains one verified writer token, requests Show and sends graceful termination once");
  puts("PASS: linked checkpoint preserves unrelated data; launcher restart cannot repeat native termination");
  broomm_host::control(&host,token.c_str(),"force");int status;assert(waitpid(child,&status,0)==child&&WIFSIGNALED(status)&&WTERMSIG(status)==SIGKILL);
  bool refused=false;try{broomm_host::control(&host,token.c_str(),"stop");}catch(const std::string&){refused=true;}
  assert(refused);assert(broomm_host::inspect(&host,root.c_str())==nullptr);
  puts("PASS: exited process invalidates retained recovery control without signalling a new process");
  close(ready[0]);close(signals[0]);
}
