// Executes the real preloaded Cemu guard before a controlled application entry.
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <poll.h>
unsigned long long gameMeta_getTitleId(void) {return 0;}
static void path(char out[4096],const char* root,const char* name) {assert(snprintf(out,4096,"%s/%s",root,name)<4096);}
static void put(const char* name,const char* value) {FILE* f=fopen(name,"w");assert(f);assert(fputs(value,f)>=0&&fclose(f)==0);}
static pid_t spawn(const char* self,const char* guard,const char* root,int input,int ready) {
  pid_t child=fork();assert(child>=0);if(child)return child;
  char in[32],out[32],writer[4096],status[4096],command[4096];
  snprintf(in,sizeof(in),"%d",input);snprintf(out,sizeof(out),"%d",ready);
  path(writer,root,"writer.lock");path(status,root,"status.json");path(command,root,"command.txt");
  assert(setenv("LD_PRELOAD",guard,1)==0&&setenv("BROOMM_CEMU_ROOT",root,1)==0&&setenv("BROOMM_CEMU_WRITER",writer,1)==0&&setenv("BROOMM_CEMU_STATUS",status,1)==0&&setenv("BROOMM_CEMU_COMMAND",command,1)==0&&setenv("BROOMM_CEMU_TOKEN","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",1)==0);
  execl(self,self,"--child",in,out,NULL);_exit(127);
}
int main(int argc,char** argv) {
  if(argc==4&&!strcmp(argv[1],"--child")) {
    // Constructor must already own the private writer before main can run.
    struct flock observed={.l_type=F_WRLCK,.l_whence=SEEK_SET};
    int fd=open(getenv("BROOMM_CEMU_WRITER"),O_RDWR);assert(fd>=0);
    // F_GETLK ignores our own locks; a parent check below observes ownership.
    assert(fcntl(fd,F_GETLK,&observed)==0&&observed.l_type==F_UNLCK);
    // Do not close another descriptor for this POSIX lock inode: closing any
    // such descriptor would drop the guard's process-scoped lock.
    assert(write(atoi(argv[3]),"1",1)==1);char value;assert(read(atoi(argv[2]),&value,1)==1);_exit(0);
  }
  assert(argc==4);char writer[4096],status[4096],command[4096];path(writer,argv[3],"writer.lock");path(status,argv[3],"status.json");path(command,argv[3],"command.txt");
  put(writer,"");put(command,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 0 0\n");
  int input[2],ready[2];assert(pipe(input)==0&&pipe(ready)==0);
  pid_t child=spawn(argv[1],argv[2],argv[3],input[0],ready[1]);
  struct pollfd pending={ready[0],POLLIN,0};assert(poll(&pending,1,5000)==1);char value;assert(read(ready[0],&value,1)==1);
  int lock=open(writer,O_RDWR);assert(lock>=0);struct flock observed={.l_type=F_WRLCK,.l_whence=SEEK_SET};assert(fcntl(lock,F_GETLK,&observed)==0&&observed.l_pid==child&&observed.l_type==F_WRLCK);
  FILE* f=NULL;for(int i=0;i<100&&!f;++i){f=fopen(status,"r");if(!f)usleep(20000);}assert(f);char receipt[2048];assert(fgets(receipt,sizeof(receipt),f));fclose(f);assert(strstr(receipt,"\"sample\":")&&strstr(receipt,"\"birth\":\""));
  pid_t refused=spawn(argv[1],argv[2],argv[3],input[0],ready[1]);int code;assert(waitpid(refused,&code,0)==refused&&WIFEXITED(code)&&WEXITSTATUS(code)==78);
  assert(write(input[1],"1",1)==1);assert(waitpid(child,&code,0)==child&&WIFEXITED(code)&&WEXITSTATUS(code)==0);
  observed.l_type=F_WRLCK;assert(fcntl(lock,F_GETLK,&observed)==0&&observed.l_type==F_UNLCK);close(lock);
  close(input[0]);close(input[1]);close(ready[0]);close(ready[1]);
  puts("PASS: shipped Cemu constructor owns kernel writer before main, reports birth, rejects another writer, and releases only on native exit");return 0;
}
