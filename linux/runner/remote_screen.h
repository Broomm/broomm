#ifndef BROOMM_REMOTE_SCREEN_H_
#define BROOMM_REMOTE_SCREEN_H_
#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xatom.h>
#endif
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <signal.h>
#include <cstring>
#include <string>
#include <vector>
#include "process_identity.h"

namespace broomm_remote {
inline FlValue* field(FlValue* map,const char* key) {
  return map&&fl_value_get_type(map)==FL_VALUE_TYPE_MAP?fl_value_lookup_string(map,key):nullptr;
}
inline std::string text(FlValue* map,const char* key,size_t maximum=4096) {
  auto* v=field(map,key);
  if(!v||fl_value_get_type(v)!=FL_VALUE_TYPE_STRING)throw std::string("Invalid remote window target.");
  std::string s=fl_value_get_string(v);
  if(s.empty()||s.size()>maximum)throw std::string("Invalid remote window target.");
  return s;
}
inline int64_t number(FlValue* map,const char* key) {
  auto* v=field(map,key);
  if(!v||fl_value_get_type(v)!=FL_VALUE_TYPE_INT)throw std::string("Invalid remote window identity.");
  return fl_value_get_int(v);
}
struct Identity {int pid;std::string birth,executable,writer; broomm_host::Lock lock;};
inline Identity identity(FlValue* args) {
  const auto pid=number(args,"pid");
  if(pid<=0||pid>2147483647)throw std::string("Invalid remote emulator process.");
  Identity result{static_cast<int>(pid),text(args,"birth",20),text(args,"executable"),text(args,"writer"),{}};
  if(result.birth.find_first_not_of("0123456789")!=std::string::npos||
      result.executable.front()!='/'||result.writer.front()!='/'||
      result.writer.size()<12||result.writer.substr(result.writer.size()-12)!="/writer.lock")
    throw std::string("Invalid remote emulator identity.");
  char expected[4096];if(!realpath(result.executable.c_str(),expected))throw std::string("The emulator executable is unavailable.");
  result.executable=expected;
  result.lock=broomm_host::lock_owner(result.writer);
  if(result.lock.pid!=result.pid||broomm_host::process_birth(result.pid)!=result.birth||
      broomm_host::link("/proc/"+std::to_string(result.pid)+"/exe")!=result.executable)
    throw std::string("The remote emulator process or writer changed. Restart screen capture.");
  return result;
}
inline void recheck(const Identity& p) {
  if(broomm_host::process_birth(p.pid)!=p.birth||
      broomm_host::link("/proc/"+std::to_string(p.pid)+"/exe")!=p.executable||
      !(broomm_host::lock_owner(p.writer)==p.lock))
    throw std::string("The remote emulator session changed. Restart screen capture.");
}
inline bool stopped(const Identity& p) {
  const auto value=broomm_host::file("/proc/"+std::to_string(p.pid)+"/stat",4096);
  const auto end=value.rfind(')');
  if(end==std::string::npos||end+2>=value.size())throw std::string("The Cemu process state is unavailable.");
  return value[end+2]=='T'||value[end+2]=='t';
}
inline FlValue* cemu_state(FlValue* args) {
  if(text(args,"name",32)!="Cemu")throw std::string("Invalid Cemu process target.");
  const auto p=identity(args);
  const int handle=static_cast<int>(syscall(SYS_pidfd_open,p.pid,0));
  if(handle<0)throw std::string("Cemu control requires kernel process handles (pidfd). Close its window normally.");
  try {
    recheck(p);
    if(auto* desired=field(args,"paused")) {
      if(fl_value_get_type(desired)!=FL_VALUE_TYPE_BOOL)throw std::string("Invalid Cemu pause request.");
      bool pause=fl_value_get_bool(desired);
      if(syscall(SYS_pidfd_send_signal,handle,pause?SIGSTOP:SIGCONT,nullptr,0))throw std::string("The kernel could not change Cemu's pause state.");
      bool confirmed=false;
      for(int i=0;i<200;++i){if(stopped(p)==pause){confirmed=true;break;}usleep(5000);}
      if(!confirmed)throw std::string("Cemu did not confirm its pause state. Input remains blocked.");
    }
    recheck(p);bool paused=stopped(p);::close(handle);
    FlValue* result=fl_value_new_map();fl_value_set_string_take(result,"paused",fl_value_new_bool(paused));return result;
  }catch(...){::close(handle);throw;}
}
#ifdef GDK_WINDOWING_X11
struct XErrors {
  GdkDisplay* display;bool active=true;
  explicit XErrors(GdkDisplay* d):display(d){gdk_x11_display_error_trap_push(display);}
  ~XErrors(){if(active)gdk_x11_display_error_trap_pop_ignored(display);}
  void finish(){active=false;if(gdk_x11_display_error_trap_pop(display))throw std::string("The emulator window changed during capture. Retry screen.");}
};
inline std::vector<unsigned long> property(Display* display,Window window,const char* name,Atom type,long limit) {
  Atom actual;int format;unsigned long count,left;unsigned char* bytes=nullptr;
  int error=XGetWindowProperty(display,window,XInternAtom(display,name,False),0,limit,False,type,&actual,&format,&count,&left,&bytes);
  std::vector<unsigned long> result;
  if(!error&&actual==type&&format==32&&left==0&&count<=static_cast<unsigned long>(limit)&&bytes)
    result.assign(reinterpret_cast<unsigned long*>(bytes),reinterpret_cast<unsigned long*>(bytes)+count);
  if(bytes)XFree(bytes);return result;
}
inline std::string title(Display* display,Window window) {
  Atom actual;int format;unsigned long count,left;unsigned char* bytes=nullptr;
  Atom utf8=XInternAtom(display,"UTF8_STRING",False);
  int error=XGetWindowProperty(display,window,XInternAtom(display,"_NET_WM_NAME",False),0,1024,False,utf8,&actual,&format,&count,&left,&bytes);
  std::string value;
  if(!error&&actual==utf8&&format==8&&!left&&bytes&&count<=4096&&g_utf8_validate(reinterpret_cast<char*>(bytes),count,nullptr))
    value.assign(reinterpret_cast<char*>(bytes),count);
  if(bytes)XFree(bytes);return value;
}
inline bool secondary(const std::string& name,const std::string& title,FlValue* args) {
  if(name=="melonDS")return title.find("[w2]")!=std::string::npos;
  if(name=="Azahar")return title.size()>=16&&title.compare(title.size()-16,16,"Secondary Window")==0;
  if(name=="Cemu") {
    auto* titles=field(args,"secondaryTitles");
    if(!titles||fl_value_get_type(titles)!=FL_VALUE_TYPE_LIST||fl_value_get_length(titles)>32)throw std::string("Invalid Cemu window titles.");
    for(size_t i=0;i<fl_value_get_length(titles);++i) {
      auto* value=fl_value_get_list_value(titles,i);
      if(fl_value_get_type(value)!=FL_VALUE_TYPE_STRING)throw std::string("Invalid Cemu window title.");
      const char* value_text=fl_value_get_string(value);
      if(std::strlen(value_text)>256)throw std::string("Invalid Cemu window title.");
      if(title==value_text||title.compare(0,std::strlen(value_text)+7,std::string(value_text)+" - FPS:")==0)return true;
    }
  }
  return false;
}
inline FlValue* capture_target(FlValue* args) {
  const auto p=identity(args);const auto name=text(args,"name",32);
  GdkDisplay* gdk=gdk_display_get_default();
  if(!gdk||!GDK_IS_X11_DISPLAY(gdk))throw std::string("Best-effort Linux hosting requires Broomm on X11/XWayland. Start it with GDK_BACKEND=x11; native Wayland capture is not available.");
  Display* display=gdk_x11_display_get_xdisplay(gdk);XErrors errors(gdk);
  auto windows=property(display,DefaultRootWindow(display),"_NET_CLIENT_LIST",XA_WINDOW,4096);
  if(windows.empty())throw std::string("The desktop did not expose an X11 window list. Check the window manager, then Retry screen.");
  Window selected=0;
  for(Window window:windows) {
    auto owner=property(display,window,"_NET_WM_PID",XA_CARDINAL,1);
    if(owner.size()!=1||owner[0]!=static_cast<unsigned long>(p.pid)||!secondary(name,title(display,window),args))continue;
    XWindowAttributes attributes{};
    if(!XGetWindowAttributes(display,window,&attributes)||attributes.map_state!=IsViewable)continue;
    if(selected)throw std::string("The emulator has more than one matching secondary window. Close the extra view, then retry.");
    selected=window;
  }
  errors.finish();recheck(p);
  if(!selected)throw std::string("The emulator's separate second screen is not visible. Connect before launching it, then Retry screen.");
  if(auto* expected=field(args,"window")) {
    if(fl_value_get_type(expected)!=FL_VALUE_TYPE_INT||static_cast<Window>(fl_value_get_int(expected))!=selected)
      throw std::string("The captured emulator window was replaced. Retry screen.");
  }
  FlValue* result=fl_value_new_map();
  fl_value_set_string_take(result,"window",fl_value_new_int(static_cast<int64_t>(selected)));
  return result;
}
#endif
struct Remote {
  FlMethodChannel* channel=nullptr;int input=-1;
  ~Remote(){if(input>=0)::close(input);g_clear_object(&channel);}
  void send(FlValue* args) {
    const auto path=text(args,"path",107),report=text(args,"report",180);
    const std::string prefix=std::string(g_get_tmp_dir())+"/brm-remote-";
    if(path.compare(0,prefix.size(),prefix)||path.find("/../")!=std::string::npos)
      throw std::string("Invalid private controller endpoint.");
    struct sockaddr_un address{};address.sun_family=AF_UNIX;
    if(path.size()>=sizeof(address.sun_path))throw std::string("The private controller endpoint is too long.");
    std::memcpy(address.sun_path,path.c_str(),path.size()+1);
    if(input<0)input=socket(AF_UNIX,SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0);
    if(input<0)throw std::string("The private controller transport is unavailable.");
    const auto sent=sendto(input,report.data(),report.size(),MSG_DONTWAIT,reinterpret_cast<sockaddr*>(&address),sizeof(address));
    if(sent<0&&errno!=ENOENT&&errno!=ECONNREFUSED&&errno!=EAGAIN&&errno!=EWOULDBLOCK)
      throw std::string("The emulator could not receive remote controller input.");
  }
};
inline void register_remote(FlView* view) {
  auto* remote=new Remote();g_autoptr(FlStandardMethodCodec) codec=fl_standard_method_codec_new();
  remote->channel=fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),"app.broomm/remote",FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(remote->channel,+[](FlMethodChannel*,FlMethodCall* call,gpointer data){
    auto* remote=static_cast<Remote*>(data);const char* method=fl_method_call_get_name(call);FlValue* args=fl_method_call_get_args(call);
    try {
      if(!std::strcmp(method,"input"))remote->send(args);
      else if(!std::strcmp(method,"cemuState")){g_autoptr(FlValue) result=cemu_state(args);fl_method_call_respond_success(call,result,nullptr);return;}
#ifdef GDK_WINDOWING_X11
      else if(!std::strcmp(method,"captureTarget")){g_autoptr(FlValue) result=capture_target(args);fl_method_call_respond_success(call,result,nullptr);return;}
#endif
      else if(std::strcmp(method,"gameController")&&std::strcmp(method,"controller")&&std::strcmp(method,"capture")&&std::strcmp(method,"cancelCapture")) {
        fl_method_call_respond_not_implemented(call,nullptr);return;
      }
      fl_method_call_respond_success(call,nullptr,nullptr);
    }catch(const std::string& error){fl_method_call_respond_error(call,"remote",error.c_str(),nullptr,nullptr);}
  },remote,nullptr);
  g_object_set_data_full(G_OBJECT(view),"broomm-remote-screen",remote,+[](gpointer data){delete static_cast<Remote*>(data);});
}
} // namespace broomm_remote
#endif
