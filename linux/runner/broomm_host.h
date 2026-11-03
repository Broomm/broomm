#ifndef BROOMM_LINUX_HOST_H
#define BROOMM_LINUX_HOST_H
#include "process_identity.h"
#include "file_icon.h"
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <glib-unix.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <cerrno>
#include <fstream>
#include <sstream>
#include <string>
#include <map>
#include <memory>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// OS interop only. Dart retains session, recovery-choice and save policy.
namespace broomm_host {
struct Host {GtkWindow* window;FlMethodChannel* channel;bool permit=false,closing=false,dialog=false;
  unsigned close_generation=0;
  guint close_timeout=0,term_source=0,int_source=0;
  std::map<std::string,std::unique_ptr<Process>> processes;};
inline const char* argument(FlValue* args,const char* name) {
  if(!args||fl_value_get_type(args)!=FL_VALUE_TYPE_MAP)return nullptr;
  FlValue* value=fl_value_lookup_string(args,name);return value&&fl_value_get_type(value)==FL_VALUE_TYPE_STRING?fl_value_get_string(value):nullptr;
}
inline FlValue* status(const char* kind,int pid,const char* message) {
  FlValue* map=fl_value_new_map();fl_value_set_string_take(map,"status",fl_value_new_string(kind));
  fl_value_set_string_take(map,"pid",fl_value_new_int(pid));fl_value_set_string_take(map,"message",fl_value_new_string(message));return map;
}
inline FlValue* inspect(Host* host,const char* root) {
  if(!root||root[0]!='/'||strlen(root)>4000)throw std::string("Invalid Broomm storage location.");
  char resolved[4096];if(!realpath(root,resolved)){if(errno==ENOENT)return nullptr;throw std::string("Broomm storage could not be inspected.");}
  std::string path=resolved;auto coordinator=lock_owner(path+"/session.lock");
  if(coordinator.pid)return status("launcher",coordinator.pid,"Another Broomm operation or configuration window owns this storage. Finish it or close that window, then check again.");
  auto writer=lock_owner(path+"/writer.lock");if(!writer.pid)return nullptr;
  try {
    auto process=std::make_unique<Process>();process->root=path;process->lock=writer;
    process->birth=process_birth(writer.pid);process->executable=link("/proc/"+std::to_string(writer.pid)+"/exe");
    process->cwd=link("/proc/"+std::to_string(writer.pid)+"/cwd");
    const std::string executables=path+"/emulators/retroarch/",profiles=path+"/profiles/";
    const std::string suffix="/RetroArch/retroarch",profile_suffix="/emulators/retroarch";
    auto hex=[](const std::string& value,size_t size){return value.size()==size&&value.find_first_not_of("0123456789abcdef")==std::string::npos;};
    if(process->executable.compare(0,executables.size(),executables)!=0||
       process->executable.size()!=executables.size()+64+suffix.size()||
       process->executable.compare(executables.size()+64,suffix.size(),suffix)!=0||
       !hex(process->executable.substr(executables.size(),64),64)||
       process->cwd.compare(0,profiles.size(),profiles)!=0||
       process->cwd.size()!=profiles.size()+32+profile_suffix.size()||
       process->cwd.compare(profiles.size()+32,profile_suffix.size(),profile_suffix)!=0||
       !hex(process->cwd.substr(profiles.size(),32),32))throw std::string("The writer is outside Broomm's managed emulator paths.");
    process->handle=static_cast<int>(syscall(SYS_pidfd_open,writer.pid,0));
    if(process->handle<0||process_birth(writer.pid)!=process->birth||
       link("/proc/"+std::to_string(writer.pid)+"/exe")!=process->executable||!(lock_owner(path+"/writer.lock")==writer))
      throw std::string("The process identity changed.");
    for(auto it=host->processes.begin();it!=host->processes.end();) {
      try {if(process_birth(it->second->lock.pid)!=it->second->birth){it=host->processes.erase(it);continue;}}catch(const std::string&){it=host->processes.erase(it);continue;}
      if(it->second->root==path&&it->second->lock==writer&&it->second->birth==process->birth) {
        auto* result=status("emulator",writer.pid,"The emulator survived the previous session. Close it before another game or save operation; local progress was kept.");
        fl_value_set_string_take(result,"token",fl_value_new_string(it->first.c_str()));fl_value_set_string_take(result,"name",fl_value_new_string("RetroArch"));return result;
      }++it;
    }
    if(host->processes.size()>=16)throw std::string("Too many recovery handles are open.");
    g_autofree gchar* uuid=g_uuid_string_random();host->processes.emplace(uuid,std::move(process));
    auto* result=status("emulator",writer.pid,"The emulator survived the previous session. Close it before another game or save operation; local progress was kept.");
    fl_value_set_string_take(result,"token",fl_value_new_string(uuid));fl_value_set_string_take(result,"name",fl_value_new_string("RetroArch"));return result;
  }catch(const std::string& reason) {
    const std::string message="A writer still owns the game data. "+reason+" Close it normally; Broomm has preserved the files.";
    return status("unknown",writer.pid,message.c_str());
  }
}
struct ControlLock {
  int fd=-1;
  explicit ControlLock(const std::string& cwd) {
    fd=open((cwd+"/bridge-recovery-control.lock").c_str(),O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);
    struct stat info;struct flock lock={};lock.l_type=F_WRLCK;lock.l_whence=SEEK_SET;
    if(fd<0||fstat(fd,&info)!=0||!S_ISREG(info.st_mode)||info.st_uid!=getuid()||fcntl(fd,F_SETLK,&lock)!=0) {
      if(fd>=0)::close(fd);fd=-1;throw std::string("Another recovery action is active, or its lock is invalid. Check again.");
    }
  }
  ~ControlLock(){if(fd>=0)::close(fd);}
};
inline bool stop_checkpoint(Process& process) {
  const std::string prefix="Broomm Linux graceful stop 1\n",path=process.cwd+"/bridge-recovery-stop.txt";
  const std::string expected=prefix+std::to_string(process.lock.pid)+" "+process.birth+"\n";
  struct stat info;
  if(lstat(path.c_str(),&info)==0) {
    if(!S_ISREG(info.st_mode)||info.st_uid!=getuid())throw std::string("The recovery checkpoint is linked or invalid. Its files were kept.");
    const auto saved=file(path,512);if(saved==expected)return true;
    std::istringstream identity(saved.substr(saved.compare(0,prefix.size(),prefix)==0?prefix.size():saved.size()));
    std::string pid,birth,extra;
    if(!(identity>>pid>>birth)||identity>>extra||pid.find_first_not_of("0123456789")!=std::string::npos||birth.find_first_not_of("0123456789")!=std::string::npos)
      throw std::string("The recovery checkpoint has unknown ownership. Its files were kept.");
  }else if(errno!=ENOENT)throw std::string("The recovery checkpoint could not be inspected.");
  std::string pattern=process.cwd+"/.recovery-stop-XXXXXX";std::vector<char> name(pattern.begin(),pattern.end());name.push_back(0);
  int fd=g_mkstemp_full(name.data(),O_RDWR|O_CLOEXEC,0600);
  if(fd<0)throw std::string("The graceful close request could not be checkpointed.");
  bool ok=write(fd,expected.data(),expected.size())==static_cast<ssize_t>(expected.size())&&fsync(fd)==0;
  ::close(fd);
  if(ok)ok=rename(name.data(),path.c_str())==0;
  if(!ok){unlink(name.data());throw std::string("The graceful close checkpoint could not be published.");}
  int directory=open(process.cwd.c_str(),O_RDONLY|O_DIRECTORY|O_CLOEXEC);
  ok=directory>=0&&fsync(directory)==0;if(directory>=0)::close(directory);
  if(!ok||file(path,512)!=expected)throw std::string("Graceful close delivery is uncertain. Close the emulator's window normally; local data was kept.");
  return false;
}
inline void control(Host* host,const char* token,const char* action) {
  auto found=token?host->processes.find(token):host->processes.end();
  if(found==host->processes.end()||!action)throw std::string("Check the game session again before controlling it.");
  Process& p=*found->second;
  if(process_birth(p.lock.pid)!=p.birth||link("/proc/"+std::to_string(p.lock.pid)+"/exe")!=p.executable||
     link("/proc/"+std::to_string(p.lock.pid)+"/cwd")!=p.cwd||
     lock_owner(p.root+"/session.lock").pid||!(lock_owner(p.root+"/writer.lock")==p.lock)) {
    host->processes.erase(found);throw std::string("The process or lock owner changed. No process was signalled.");}
  if(!strcmp(action,"show")) {
    std::string path=p.cwd+"/bridge-recovery-show.txt";int fd=open(path.c_str(),O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC|O_NOFOLLOW,0600);
    if(fd<0)throw std::string("The emulator window could not be requested.");
    gint64 value=g_get_monotonic_time();std::string text=std::to_string(value);
    bool ok=write(fd,text.data(),text.size())==static_cast<ssize_t>(text.size());::close(fd);
    if(!ok)throw std::string("The emulator window request was incomplete.");return;
  }
  int signal;std::unique_ptr<ControlLock> request;
  if(!strcmp(action,"stop")){
    if(p.stopped)return;request=std::make_unique<ControlLock>(p.cwd);
    if(stop_checkpoint(p)){p.stopped=true;return;}signal=SIGTERM;
  }else if(!strcmp(action,"force"))signal=SIGKILL;
  else throw std::string("Unknown recovery action.");
  if(syscall(SYS_pidfd_send_signal,p.handle,signal,nullptr,0)!=0)throw std::string("The emulator could not be signalled; its data was kept.");
  if(signal==SIGTERM)p.stopped=true; // A second upstream termination signal is a hard exit.
}
inline gboolean fallback(gpointer data) {
  Host* host=static_cast<Host*>(data);
  GSource* source=g_main_current_source();if(source&&g_source_get_id(source)==host->close_timeout)host->close_timeout=0;
  if(host->permit||host->dialog)return G_SOURCE_REMOVE;
  if(host->close_timeout){g_source_remove(host->close_timeout);host->close_timeout=0;}
  host->closing=false;++host->close_generation;
  host->dialog=true;GtkWidget* dialog=gtk_message_dialog_new(host->window,GTK_DIALOG_MODAL,GTK_MESSAGE_QUESTION,GTK_BUTTONS_NONE,
      "Broomm is not responding to the close request.");
  gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog),"Quit now keeps unfinished local data for recovery. An active emulator may remain open.");
  gtk_dialog_add_buttons(GTK_DIALOG(dialog),"Keep waiting",GTK_RESPONSE_CANCEL,"Quit Broomm now",GTK_RESPONSE_ACCEPT,nullptr);
  g_signal_connect(dialog,"response",G_CALLBACK(+[](GtkDialog* dialog,gint response,gpointer data){Host* host=static_cast<Host*>(data);
    host->dialog=false;gtk_widget_destroy(GTK_WIDGET(dialog));if(response==GTK_RESPONSE_ACCEPT){host->permit=true;gtk_window_close(host->window);}}),host);
  gtk_widget_show(dialog);return G_SOURCE_REMOVE;
}
struct CloseReply {Host* host;unsigned generation;};
inline void request_close(Host* host) {
  if(host->permit||host->closing||host->dialog)return;
  host->closing=true;const unsigned generation=++host->close_generation;
  auto* pending=new CloseReply{host,generation};
  fl_method_channel_invoke_method(host->channel,"closeRequested",nullptr,nullptr,+[](GObject* object,GAsyncResult* result,gpointer data){
    std::unique_ptr<CloseReply> pending(static_cast<CloseReply*>(data));Host* host=pending->host;
    g_autoptr(GError) error=nullptr;
    g_autoptr(FlMethodResponse) response=fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object),result,&error);
    if(host->permit||!host->closing||host->close_generation!=pending->generation)return;
    host->closing=false;
    if(host->close_timeout){g_source_remove(host->close_timeout);host->close_timeout=0;}
    bool acknowledged=false;
    if(response&&FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
      FlValue* value=fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response));
      acknowledged=value&&fl_value_get_type(value)==FL_VALUE_TYPE_BOOL&&fl_value_get_bool(value);
    }
    if(!acknowledged)fallback(host);
  },pending);
  host->close_timeout=g_timeout_add_seconds(5,fallback,host);
}
inline void register_host(FlView* view,GtkWindow* window) {
  auto* host=new Host();host->window=window;
  g_autoptr(FlStandardMethodCodec) codec=fl_standard_method_codec_new();
  host->channel=fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),"app.broomm/prototype",FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(host->channel,+[](FlMethodChannel*,FlMethodCall* call,gpointer data){
    auto* host=static_cast<Host*>(data);const char* method=fl_method_call_get_name(call);FlValue* args=fl_method_call_get_args(call);
    try {
      if(!strcmp(method,"show")){
        GtkWidget* window=GTK_WIDGET(host->window);
        gtk_widget_show(window);
        gtk_window_deiconify(host->window);
        gtk_window_present(host->window);
        const char* desktop=g_getenv("XDG_CURRENT_DESKTOP");
        if(desktop&&!strcmp(desktop,"gamescope")){
          // Finish sending the map request before allowing the bridge to
          // withdraw the only other game surface.
          gdk_display_sync(gtk_widget_get_display(window));
          if(!gtk_widget_get_mapped(window))
            throw std::string("Gamescope did not map the Broomm window.");
        }
      }
      else if(!strcmp(method,"hide"))gtk_widget_hide(GTK_WIDGET(host->window));
      else if(!strcmp(method,"close")){host->permit=true;gtk_window_close(host->window);}
      else if(!strcmp(method,"gameWriter")){g_autoptr(FlValue) value=inspect(host,argument(args,"root"));fl_method_call_respond_success(call,value,nullptr);return;}
      else if(!strcmp(method,"setExecutableIcon")){broomm_file_icon::apply(call);return;}
      else if(!strcmp(method,"controlGameWriter"))control(host,argument(args,"token"),argument(args,"action"));
      else {fl_method_call_respond_not_implemented(call,nullptr);return;}
      fl_method_call_respond_success(call,nullptr,nullptr);
    }catch(const std::string& message){fl_method_call_respond_error(call,"linux_host",message.c_str(),nullptr,nullptr);}
  },host,nullptr);
  g_signal_connect(window,"delete-event",G_CALLBACK(+[](GtkWidget*,GdkEvent*,gpointer data)->gboolean{
    auto* host=static_cast<Host*>(data);if(host->permit)return FALSE;request_close(host);return TRUE;
  }),host);
  host->term_source=g_unix_signal_add(SIGTERM,+[](gpointer data)->gboolean{request_close(static_cast<Host*>(data));return G_SOURCE_CONTINUE;},host);
  host->int_source=g_unix_signal_add(SIGINT,+[](gpointer data)->gboolean{request_close(static_cast<Host*>(data));return G_SOURCE_CONTINUE;},host);
  g_signal_connect(window,"destroy",G_CALLBACK(+[](GtkWidget*,gpointer data){auto* host=static_cast<Host*>(data);
    host->permit=true;host->window=nullptr;
    if(host->close_timeout)g_source_remove(host->close_timeout);
    if(host->term_source)g_source_remove(host->term_source);
    if(host->int_source)g_source_remove(host->int_source);
    host->processes.clear();
  }),host);
}
} // namespace broomm_host
#endif
