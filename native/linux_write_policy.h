#ifndef BROOMM_LINUX_WRITE_POLICY_H
#define BROOMM_LINUX_WRITE_POLICY_H
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <linux/landlock.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>
static bool sandbox_path(int ruleset,const char *path,uint64_t access,bool optional) {
    int fd=open(path,O_PATH|O_CLOEXEC|O_NOFOLLOW);
    if(fd<0)return optional&&errno==ENOENT;
    struct landlock_path_beneath_attr rule={.allowed_access=access,.parent_fd=fd};
    bool ok=syscall(SYS_landlock_add_rule,ruleset,LANDLOCK_RULE_PATH_BENEATH,&rule,0)==0;
    close(fd);return ok;
}
static bool private_writes(const char *root) {
    // Kernel-only interop: domain ownership and paths are resolved by Dart.
    // Read/execute remain available; filesystem mutation is private to this run.
    int abi=(int)syscall(SYS_landlock_create_ruleset,NULL,0,LANDLOCK_CREATE_RULESET_VERSION);
    if(abi<3)return false; // TRUNCATE must be enforced, not silently ignored.
    uint64_t rights=LANDLOCK_ACCESS_FS_WRITE_FILE|LANDLOCK_ACCESS_FS_REMOVE_DIR|LANDLOCK_ACCESS_FS_REMOVE_FILE|
        LANDLOCK_ACCESS_FS_MAKE_CHAR|LANDLOCK_ACCESS_FS_MAKE_DIR|LANDLOCK_ACCESS_FS_MAKE_REG|
        LANDLOCK_ACCESS_FS_MAKE_SOCK|LANDLOCK_ACCESS_FS_MAKE_FIFO|LANDLOCK_ACCESS_FS_MAKE_BLOCK|
        LANDLOCK_ACCESS_FS_MAKE_SYM|LANDLOCK_ACCESS_FS_REFER|LANDLOCK_ACCESS_FS_TRUNCATE;
    struct landlock_ruleset_attr rules;
    memset(&rules,0,sizeof(rules));rules.handled_access_fs=rights;
    int fd=(int)syscall(SYS_landlock_create_ruleset,&rules,sizeof(rules.handled_access_fs),0);if(fd<0)return false;
    bool ok=root&&sandbox_path(fd,root,rights,false);
    // Existing character devices are not profile settings. Never grant directory
    // creation/removal outside the private root. memfd/tmp caches stay private.
    for(size_t i=0;i<5&&ok;++i)ok=sandbox_path(fd,(const char *[]){"/dev/dri","/dev/snd","/dev/input","/dev/null","/dev/tty"}[i],LANDLOCK_ACCESS_FS_WRITE_FILE,true);
    DIR *devices=opendir("/dev");struct dirent *entry;
    if(devices) {
        while(ok&&(entry=readdir(devices))) {
            if(!strncmp(entry->d_name,"hidraw",6)) {
                char path[512];snprintf(path,sizeof(path),"/dev/%s",entry->d_name);
                ok=sandbox_path(fd,path,LANDLOCK_ACCESS_FS_WRITE_FILE,true);
            }
        }
        closedir(devices);
    }
    if(ok)ok=prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)==0&&syscall(SYS_landlock_restrict_self,fd,0)==0;
    close(fd);return ok;
}

#endif
