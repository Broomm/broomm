#include <fcntl.h>
#include <errno.h>
// This lock lives in the emulator process, so an orphan remains the sole writer.
// Same fcntl whole-file lock as Dart FileLock.exclusive; never unlink this inode.
static int session_writer_fd=-1;
static void acquire_session_writer(void) {
    const char *path=getenv("BROOMM_WRITER_LOCK");
    if(!path){fprintf(stderr,"Broomm: missing session writer lock\n");_exit(73);}
    session_writer_fd=open(path,O_CREAT|O_RDWR|O_CLOEXEC,0600);
    struct flock lock={.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
    if(session_writer_fd<0||fcntl(session_writer_fd,F_SETLK,&lock)<0) {
        fprintf(stderr,"Broomm: another emulator owns the session writer lock (%d)\n",errno);
        _exit(73);
    }
}
