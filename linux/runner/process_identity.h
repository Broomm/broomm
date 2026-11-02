#ifndef BROOMM_LINUX_PROCESS_IDENTITY_H
#define BROOMM_LINUX_PROCESS_IDENTITY_H
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/syscall.h>
#include <sys/vfs.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <cerrno>
#include <fstream>
#include <sstream>
#include <string>
#include <cstdio>

// Read-only kernel observations; never open/close a live POSIX lock inode.
namespace broomm_host {
struct Lock {int pid=0;unsigned major=0,minor=0;unsigned long long inode=0;
  bool operator==(const Lock& b) const{return pid==b.pid&&major==b.major&&minor==b.minor&&inode==b.inode;}};
struct Process {std::string root,executable,birth,cwd;Lock lock;int handle=-1;bool stopped=false;
  ~Process(){if(handle>=0)::close(handle);}};
inline std::string file(const std::string& path,size_t limit=65536) {
  std::ifstream in(path,std::ios::binary);if(!in)throw std::string("The operating system could not inspect the previous session.");
  std::string out;char buffer[4096];while(in.read(buffer,sizeof(buffer))||in.gcount()) {
    out.append(buffer,static_cast<size_t>(in.gcount()));if(out.size()>limit)throw std::string("The process observation exceeded its limit.");}
  if(in.bad())throw std::string("The process observation was incomplete.");return out;
}
inline std::string link(const std::string& path) {
  char buffer[4096];ssize_t n=readlink(path.c_str(),buffer,sizeof(buffer)-1);
  if(n<0||n>=static_cast<ssize_t>(sizeof(buffer)-1))throw std::string("The emulator executable could not be verified.");
  return std::string(buffer,static_cast<size_t>(n));
}
inline std::string process_birth(int pid) {
  std::string base="/proc/"+std::to_string(pid);struct stat info;
  if(stat(base.c_str(),&info)!=0||info.st_uid!=getuid())throw std::string("The process owner changed. No process was signalled.");
  std::string text=file(base+"/stat");auto end=text.rfind(')');if(end==std::string::npos)throw std::string("Invalid process identity.");
  std::istringstream values(text.substr(end+2));std::string part;
  for(int field=3;field<=22;++field)if(!(values>>part))throw std::string("Incomplete process identity.");
  return part;
}
inline bool descriptor_lock(const Lock& observed,const Lock& target) {
  // Btrfs subvolumes can report a different st_dev in stat() from the superblock
  // device printed by /proc/locks. Confirm the actual open file AND its lock;
  // inode alone would confuse unrelated filesystems. Never open the lock file.
  const std::string base="/proc/"+std::to_string(observed.pid);
  DIR* entries=opendir((base+"/fd").c_str());
  if(!entries)throw std::string("The writer's file ownership could not be inspected.");
  bool matched=false;struct dirent* entry;
  try {
    unsigned count=0;
    while((entry=readdir(entries))) {
      const std::string name=entry->d_name;
      if(name.empty()||name.find_first_not_of("0123456789")!=std::string::npos)continue;
      if(++count>4096)throw std::string("The writer has too many open files to verify safely.");
      struct stat info;
      if(stat((base+"/fd/"+name).c_str(),&info)!=0)continue;
      if(!S_ISREG(info.st_mode)||major(info.st_dev)!=target.major||minor(info.st_dev)!=target.minor||info.st_ino!=target.inode)continue;
      std::istringstream lines(file(base+"/fdinfo/"+name));std::string line;
      while(std::getline(lines,line)) {
        if(line.compare(0,5,"lock:")!=0)continue;
        std::istringstream row(line.substr(5));std::string number,kind,advisory,type,identity,start,end;int pid;
        if(!(row>>number>>kind>>advisory>>type>>pid>>identity>>start>>end))continue;
        unsigned ma,mi;unsigned long long inode;char extra;
        if(sscanf(identity.c_str(),"%x:%x:%llu%c",&ma,&mi,&inode,&extra)!=3)continue;
        if(pid==observed.pid&&ma==observed.major&&mi==observed.minor&&inode==observed.inode)matched=true;
      }
      if(matched)break;
    }
  }catch(...){closedir(entries);throw;}
  closedir(entries);return matched;
}
inline Lock lock_owner(const std::string& path) {
  struct stat s;if(lstat(path.c_str(),&s)!=0){if(errno==ENOENT)return {};throw std::string("The game lock could not be inspected.");}
  if(!S_ISREG(s.st_mode)||s.st_uid!=getuid())throw std::string("The game lock is linked or not a regular file. Its files were kept.");
  struct statfs filesystem;
  if(statfs(path.c_str(),&filesystem)!=0)throw std::string("The game lock filesystem could not be inspected.");
  const bool subvolume_devices=static_cast<unsigned long>(filesystem.f_type)==0x9123683eUL;
  Lock target;target.major=major(s.st_dev);target.minor=minor(s.st_dev);target.inode=s.st_ino;
  // Do not open/close the coordinator: POSIX would release this process's own
  // record lock when ANY descriptor for that inode closes. /proc/locks is a
  // kernel observation and does not alter Dart's live SessionLease.
  std::istringstream entries(file("/proc/locks",2*1024*1024));std::string line;
  while(std::getline(entries,line)) {
    std::istringstream row(line);std::string number,kind,advisory,type,identity,start,end;int pid;
    if(!(row>>number>>kind)||kind=="->")continue;
    if(!(row>>advisory>>type>>pid>>identity>>start>>end))continue;
    unsigned ma,mi;unsigned long long inode;char extra;
    if(sscanf(identity.c_str(),"%x:%x:%llu%c",&ma,&mi,&inode,&extra)!=3)continue;
    if(inode!=target.inode)continue;
    Lock observed;observed.pid=pid;observed.major=ma;observed.minor=mi;observed.inode=inode;
    if(subvolume_devices||ma!=target.major||mi!=target.minor) {
      if(pid<=0)throw std::string("The game has an unrecognized live lock owner. Close it normally.");
      if(!descriptor_lock(observed,target))continue;
    }
    if(type!="WRITE"||advisory!="ADVISORY"||kind!="POSIX"||pid<=0||start!="0"||end!="EOF")throw std::string("The game has an unrecognized live lock owner. Close it normally.");
    observed.pid=pid;return observed;
  }return {};
}
} // namespace broomm_host
#endif
