// Build-pinned ELF symbols and the emulator's own public SDL DynAPI table.
static void record_at(int line,const char *format,...) {
 pthread_mutex_lock(&log_lock);
 struct stat st;
 if(log_path&&stat(log_path,&st)==0&&st.st_size>=1024*1024) {
  if(log_file){fclose(log_file);log_file=NULL;}
  for(int i=9;i>=1;--i){char from[4096],to[4096];snprintf(to,sizeof(to),"%s.%d",log_path,i);
   if(i==9)unlink(to);if(i==1)snprintf(from,sizeof(from),"%s",log_path);else snprintf(from,sizeof(from),"%s.%d",log_path,i-1);rename(from,to);}
 }
 if(!log_file&&log_path)log_file=fopen(log_path,"a");
 if(log_file){struct timespec now;struct tm utc;char stamp[32];clock_gettime(CLOCK_REALTIME,&now);gmtime_r(&now.tv_sec,&utc);strftime(stamp,sizeof(stamp),"%Y-%m-%dT%H:%M:%S",&utc);
  fprintf(log_file,"%s.%03ldZ info linux_bridge.c:%d pid=%d ",stamp,now.tv_nsec/1000000,line,getpid());va_list args;va_start(args,format);vfprintf(log_file,format,args);va_end(args);fputc('\n',log_file);fflush(log_file);
 }else fputs("Broomm native log unavailable; retrying.\n",stderr);
 pthread_mutex_unlock(&log_lock);
}
static void *symbol(const char *name) {
 void *found=dlsym(sdl,name);if(found)return found;
 void **entry=api_slot(name);if(entry)return __atomic_load_n(entry,__ATOMIC_ACQUIRE);
 for(size_t i=0;i<symbol_count;++i)if(!strcmp(symbol_entries[i].name,name))return (void *)symbol_entries[i].address;
 char real[200];snprintf(real,sizeof(real),"%s_REAL",name);
 for(size_t i=0;i<symbol_count;++i)if(!strcmp(symbol_entries[i].name,real))return (void *)symbol_entries[i].address;
 return NULL;
}
#include "linux_dispatch.h"
