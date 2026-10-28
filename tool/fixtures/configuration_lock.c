// Read-only native integration-test observation. Never shipped with Broomm.
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    int fd=open(argv[1],O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    struct stat info;
    struct flock lock={.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
    if(fd<0||fstat(fd,&info)!=0||!S_ISREG(info.st_mode)||fcntl(fd,F_GETLK,&lock)!=0)return 2;
    close(fd);
    if(lock.l_type==F_UNLCK)return 1;
    return lock.l_type==F_WRLCK&&lock.l_pid==(pid_t)strtol(argv[2],NULL,10)?0:2;
}
