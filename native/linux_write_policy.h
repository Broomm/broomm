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
#include <stdlib.h>
#include <limits.h>
#include <sched.h>
#include <linux/capability.h>
#include <linux/mount.h>
#include <linux/securebits.h>
#include <sys/mount.h>

static bool namespace_map(const char *path,const char *value) {
    int fd=open(path,O_WRONLY|O_CLOEXEC);if(fd<0)return false;
    size_t n=strlen(value);ssize_t written=write(fd,value,n);int error=written>=0&&written!=(ssize_t)n?EIO:errno;
    close(fd);errno=error;return written==(ssize_t)n;
}

// Some ARM handheld kernels do not enable any LSM, including Landlock. Keep
// the same private-write boundary using a child-only user/mount namespace.
// This runs before native worker creation, preserving the original PID/UID
// and display/IPC connections. No helper executable, root or OS changes.
static bool namespace_private_writes(const char *root) {
    char canonical[PATH_MAX],cwd[PATH_MAX],mapping[96];
    if(!root){errno=EINVAL;return false;}
    if(!realpath(root,canonical)||!getcwd(cwd,sizeof(cwd)))return false;
    if(!strcmp(canonical,"/")){errno=EINVAL;return false;}
    uid_t uid=getuid();gid_t gid=getgid();
    if(unshare(CLONE_NEWUSER|CLONE_NEWNS))return false;
    if(!namespace_map("/proc/self/setgroups","deny\n"))return false;
    snprintf(mapping,sizeof(mapping),"%u %u 1\n",(unsigned)uid,(unsigned)uid);
    if(!namespace_map("/proc/self/uid_map",mapping))return false;
    snprintf(mapping,sizeof(mapping),"%u %u 1\n",(unsigned)gid,(unsigned)gid);
    if(!namespace_map("/proc/self/gid_map",mapping))return false;
    // Stop mount propagation before creating any new mounts. The existing
    // namespace tree was cloned by unshare; host mount flags are untouched.
    if(mount(NULL,"/",NULL,MS_REC|MS_PRIVATE,NULL)||
       mount(canonical,canonical,NULL,MS_BIND|MS_REC,NULL))return false;
    struct mount_attr attributes;
    memset(&attributes,0,sizeof(attributes));attributes.attr_set=MOUNT_ATTR_RDONLY;
    if(syscall(SYS_mount_setattr,AT_FDCWD,"/",AT_RECURSIVE,&attributes,sizeof(attributes)))return false;
    attributes.attr_set=0;attributes.attr_clr=MOUNT_ATTR_RDONLY;
    if(syscall(SYS_mount_setattr,AT_FDCWD,canonical,AT_RECURSIVE,&attributes,sizeof(attributes))||chdir(cwd))return false;
    // Device nodes still permit their normal I/O on read-only mounts. Creation,
    // regular file writes, truncation and renames outside the root stay denied.
    // Drop all namespace administration before running any provider code.
    unsigned secure=SECBIT_NOROOT|SECBIT_NOROOT_LOCKED|
        SECBIT_NO_SETUID_FIXUP|SECBIT_NO_SETUID_FIXUP_LOCKED;
    if(prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)||prctl(PR_SET_SECUREBITS,secure,0,0,0))return false;
    struct __user_cap_header_struct header={.version=_LINUX_CAPABILITY_VERSION_3,.pid=0};
    struct __user_cap_data_struct capabilities[2];memset(capabilities,0,sizeof(capabilities));
    if(syscall(SYS_capset,&header,capabilities))return false;
    return true;
}
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
    // TRUNCATE must be enforced, not silently ignored on older/absent LSMs.
    if(abi<3)return namespace_private_writes(root);
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
