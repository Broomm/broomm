#define _GNU_SOURCE 1
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <fstream>

static void write_file(const std::string& path,const std::string& text) {
  std::ofstream file(path);file<<text;file.flush();assert(file.good());
}
static std::string read_file(const std::string& path) {
  std::ifstream file(path);return {std::istreambuf_iterator<char>(file),{}};
}
static void ready(const std::string& path) {
  for(int i=0;i<500;++i){if(!read_file(path).empty())return;usleep(10000);}assert(false);
}
int main(int argc,char **argv) {
  assert(argc>=3);
  if(!strcmp(argv[1],"guest")) {
    std::string root=argv[2];
    assert(open((root+"/../preserved").c_str(),O_WRONLY|O_TRUNC)<0&&errno==EACCES);
    assert(socket(AF_INET,SOCK_STREAM,0)<0&&errno==EACCES);
    assert(socket(AF_INET6,SOCK_STREAM,0)<0&&errno==EACCES);
    int local=socket(AF_UNIX,SOCK_STREAM,0);assert(local>=0);close(local);
    // Native VM backing files are sparse; enforce the distinct installer
    // ceiling without allocating or writing 32 GiB of test data.
    int sparse=open((root+"/sparse").c_str(),O_CREAT|O_RDWR,0600);assert(sparse>=0);
    constexpr off_t limit=32LL*1024*1024*1024;
    assert(ftruncate(sparse,limit)==0);
    signal(SIGXFSZ,SIG_IGN);
    assert(ftruncate(sparse,limit+1)<0&&errno==EFBIG);
    close(sparse);assert(unlink((root+"/sparse").c_str())==0);
    pid_t child=fork();assert(child>=0);
    if(!child){assert(setsid()>=0);write_file(root+"/daemon",std::to_string(getpid()));for(;;)pause();}
    write_file(root+"/ready",std::to_string(getpid()));
    ready(root+"/release");return 0;
  }
  assert(argc==4);std::string helper=argv[1],executable=argv[2],base=argv[3];
  write_file(base+"/preserved","owner progress");
  for(int mode=0;mode<2;++mode) {
    std::string root=base+"/case"+std::to_string(mode),lock=base+"/writer"+std::to_string(mode);
    assert(mkdir(root.c_str(),0700)==0);
    pid_t child=fork();assert(child>=0);
    if(!child){setenv("BROOMM_WRITER_LOCK",lock.c_str(),1);setenv("BROOMM_INSTALLER_ROOT",root.c_str(),1);
      execl(helper.c_str(),helper.c_str(),root.c_str(),root.c_str(),executable.c_str(),"guest",root.c_str(),nullptr);_exit(99);}
    ready(root+"/ready");ready(root+"/daemon");
    pid_t daemon=std::stoi(read_file(root+"/daemon"));int handle=static_cast<int>(syscall(SYS_pidfd_open,daemon,0));assert(handle>=0);
    int fd=open(lock.c_str(),O_RDWR|O_CLOEXEC);assert(fd>=0);struct flock region={};region.l_type=F_WRLCK;region.l_whence=SEEK_SET;
    assert(fcntl(fd,F_SETLK,&region)<0&&(errno==EAGAIN||errno==EACCES));
    if(mode)assert(kill(child,SIGTERM)==0);else write_file(root+"/release","continue");
    int status=0;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status));assert(WEXITSTATUS(status)==(mode?143:0));
    assert(syscall(SYS_pidfd_send_signal,handle,0,nullptr,0)<0&&errno==ESRCH);close(handle);
    assert(fcntl(fd,F_SETLK,&region)==0);close(fd);
    assert(read_file(base+"/preserved")=="owner progress");
  }
  puts("PASS: private/offline native commands, stable writer lock, adopted daemon drain, normal completion and cancellation");
}
