#ifndef BROOMM_WINDOWS_REMOTE_SCREEN_H_
#define BROOMM_WINDOWS_REMOTE_SCREEN_H_
#include <windows.h>
#include <psapi.h>
#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <memory>
#include <string>
#include <vector>
#include <cwctype>
#include "../../native/cemu_windows_host.h"

namespace broomm_remote {
using Value=flutter::EncodableValue;
using Map=flutter::EncodableMap;
inline const Value* field(const Map& map,const char* key) {
  const auto found=map.find(Value(key));return found==map.end()?nullptr:&found->second;
}
inline std::string text(const Map& map,const char* key,size_t limit=4096) {
  const auto* value=field(map,key);const auto* s=value?std::get_if<std::string>(value):nullptr;
  if(!s||s->empty()||s->size()>limit||s->find('\0')!=std::string::npos)throw std::string("Invalid emulator identity.");
  return *s;
}
inline int64_t number(const Map& map,const char* key) {
  const auto* value=field(map,key);
  if(value){if(auto* n=std::get_if<int64_t>(value))return *n;if(auto* n=std::get_if<int32_t>(value))return *n;}
  throw std::string("Invalid emulator process identity.");
}
struct WindowSearch {DWORD pid;HWND selected=nullptr;bool ambiguous=false;std::vector<std::wstring> titles;};
inline BOOL CALLBACK secondary(HWND window,LPARAM context) {
  auto* query=reinterpret_cast<WindowSearch*>(context);DWORD pid=0;GetWindowThreadProcessId(window,&pid);
  if(pid!=query->pid||!IsWindowVisible(window)||IsIconic(window))return TRUE;
  wchar_t title[1024];GetWindowTextW(window,title,1024);
  bool match=false;for(const auto& name:query->titles){const std::wstring value=title;if(value==name||value.rfind(name+L" - FPS:",0)==0)match=true;}
  if(!match)return TRUE;
  BOOL cloaked=FALSE;if(SUCCEEDED(DwmGetWindowAttribute(window,DWMWA_CLOAKED,&cloaked,sizeof(cloaked)))&&cloaked)return TRUE;
  if(query->selected){query->ambiguous=true;return FALSE;}query->selected=window;return TRUE;
}
struct Remote : PauseController {
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  Value call(const std::string& method,const Map& args) {
    if(method=="processIdentity") {
      FILETIME created,exited,kernel,user;
      if(!GetProcessTimes(GetCurrentProcess(),&created,&exited,&kernel,&user))throw std::string("Windows could not confirm this launcher identity.");
      return Value(Map{{Value("pid"),Value(static_cast<int64_t>(GetCurrentProcessId()))},{Value("birth"),Value(std::to_string((static_cast<unsigned long long>(created.dwHighDateTime)<<32)|created.dwLowDateTime))}});
    }
    if(method=="gameController"){if(args.empty())resume();return Value();}
    if(method=="controller"||method=="capture"||method=="cancelCapture")return Value();
    if(method!="captureTarget"&&method!="cemuState")throw std::string("Unsupported Windows remote operation.");
    if(text(args,"name",32)!="Cemu")throw std::string("This Windows preview hosts Cemu Remote screen. Other managed emulators are not available yet.");
    Process process;inspect(process,Identity{number(args,"pid"),text(args,"birth",20),text(args,"executable"),text(args,"guard"),text(args,"writer"),text(args,"guardToken",64)});
    if(method=="cemuState") {
      BOOL debugged=FALSE;
      if(!CheckRemoteDebuggerPresent(process.handle,&debugged)||
          (debugged&&!(paused_pid==process.pid&&paused_birth==process.birth)))
        throw std::string("Another debugger owns Cemu, or Windows could not verify its pause controller. Input remains blocked.");
      if(const auto* wanted=field(args,"paused")) {
        const auto* value=std::get_if<bool>(wanted);if(!value)throw std::string("Invalid Cemu pause request.");
        if(*value)pause(process);else if(paused_pid==process.pid&&paused_birth==process.birth)resume();
      }
      return Value(Map{{Value("paused"),Value(paused_pid==process.pid&&paused_birth==process.birth)}});
    }
    WindowSearch search{process.pid};
    const auto* value=field(args,"secondaryTitles");const auto* titles=value?std::get_if<flutter::EncodableList>(value):nullptr;
    if(!titles||titles->empty()||titles->size()>32)throw std::string("Invalid Cemu window titles.");
    for(const auto& item:*titles){const auto* title=std::get_if<std::string>(&item);if(!title||title->empty()||title->size()>256)throw std::string("Invalid Cemu window title.");search.titles.push_back(wide(*title));}
    EnumWindows(secondary,reinterpret_cast<LPARAM>(&search));
    if(!search.selected||search.ambiguous)throw std::string("Cemu must have one visible GamePad View window. Restore it and Retry screen.");
    const auto id=static_cast<int64_t>(reinterpret_cast<intptr_t>(search.selected));
    if(field(args,"window")&&number(args,"window")!=id)throw std::string("The captured emulator window was replaced. Retry screen.");
    if(WaitForSingleObject(process.handle,0)!=WAIT_TIMEOUT)throw std::string("The captured emulator process ended.");
    return Value(Map{{Value("window"),Value(id)}});
  }
};
inline std::unique_ptr<Remote> RegisterRemoteScreen(flutter::BinaryMessenger* messenger) {
  auto remote=std::make_unique<Remote>();auto* state=remote.get();
  remote->channel=std::make_unique<flutter::MethodChannel<Value>>(messenger,"app.broomm/remote",&flutter::StandardMethodCodec::GetInstance());
  remote->channel->SetMethodCallHandler([state](const auto& call,auto result) {
    try {
      const auto* args=std::get_if<Map>(call.arguments());
      result->Success(state->call(call.method_name(),args?*args:Map{}));
    }catch(const std::string& error){result->Error("remote",error);}
  });return remote;
}
} // namespace broomm_remote
#endif
