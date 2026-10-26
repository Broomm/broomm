// Research-only macOS path interposition for RPCS3's hardcoded native cache path.
// Exact prefix, child-scoped; the seatbelt still denies writes at the original.
#define _DARWIN_C_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/statvfs.h>
#include <unistd.h>

static const char *redirect(const char *path,char buffer[PATH_MAX]) {
    const char *from=getenv("BROOMM_CACHE_FROM"),*to=getenv("BROOMM_CACHE_TO");
    if(!path||!from||!to)return path;
    size_t n=strlen(from);
    if(strncmp(path,from,n)||(path[n]&&path[n]!='/'))return path;
    int result=snprintf(buffer,PATH_MAX,"%s%s",to,path+n);
    if(result<0||result>=PATH_MAX)return path; // Original write remains denied.
    return buffer;
}
static int redirected_open(const char *path,int flags,...) {
    mode_t mode=0;
    if(flags&O_CREAT){va_list ap;va_start(ap,flags);mode=va_arg(ap,int);va_end(ap);}
    char b[PATH_MAX];return open(redirect(path,b),flags,mode);
}
static int redirected_mkdir(const char *p,mode_t m){char b[PATH_MAX];return mkdir(redirect(p,b),m);}
static int redirected_stat(const char *p,struct stat *s){char b[PATH_MAX];return stat(redirect(p,b),s);}
static int redirected_lstat(const char *p,struct stat *s){char b[PATH_MAX];return lstat(redirect(p,b),s);}
static int redirected_access(const char *p,int m){char b[PATH_MAX];return access(redirect(p,b),m);}
static int redirected_unlink(const char *p){char b[PATH_MAX];return unlink(redirect(p,b));}
static int redirected_rmdir(const char *p){char b[PATH_MAX];return rmdir(redirect(p,b));}
static int redirected_rename(const char *a,const char *b){char x[PATH_MAX],y[PATH_MAX];return rename(redirect(a,x),redirect(b,y));}
static DIR *redirected_opendir(const char *p){char b[PATH_MAX];return opendir(redirect(p,b));}
static int redirected_statfs(const char *p,struct statfs *s){char b[PATH_MAX];return statfs(redirect(p,b),s);}
static int redirected_statvfs(const char *p,struct statvfs *s){char b[PATH_MAX];return statvfs(redirect(p,b),s);}

#define INTERPOSE(replacement,original) \
    __attribute__((used,section("__DATA,__interpose"))) static const struct { \
        const void *new_function,*old_function; \
    } interpose_##original={(const void *)(replacement),(const void *)(original)};
INTERPOSE(redirected_open,open)
INTERPOSE(redirected_mkdir,mkdir)
INTERPOSE(redirected_stat,stat)
INTERPOSE(redirected_lstat,lstat)
INTERPOSE(redirected_access,access)
INTERPOSE(redirected_unlink,unlink)
INTERPOSE(redirected_rmdir,rmdir)
INTERPOSE(redirected_rename,rename)
INTERPOSE(redirected_opendir,opendir)
INTERPOSE(redirected_statfs,statfs)
INTERPOSE(redirected_statvfs,statvfs)
