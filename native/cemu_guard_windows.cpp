// Original Broomm Windows writer/window interop. Dart owns session workflows.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <string>
#include "cemu_windows_identity.h"
extern "C" { __declspec(dllexport) BroommCemuWriterIdentity broomm_cemu_writer{}; }

static HANDLE writer=INVALID_HANDLE_VALUE;
static std::wstring status_path,command_path;
static char token[65];
static unsigned long long revision;
static unsigned long long sample;
static bool playing,quitting;
static unsigned long long birth;
static HANDLE launcher=nullptr;

static std::wstring environment(const wchar_t* name) {
  wchar_t value[4096];DWORD n=GetEnvironmentVariableW(name,value,4096);
  return n&&n<4096?std::wstring(value,n):L"";
}
struct Views {HWND main=nullptr,pad=nullptr;bool ambiguous=false;};
static bool pad_title(const std::wstring& title) {
  const auto names=environment(L"BROOMM_CEMU_PAD_TITLES");size_t at=0;
  do {const auto end=names.find(L'|',at);const auto name=names.substr(at,end==std::wstring::npos?end:end-at);
    if(!name.empty()&&(title==name||title.rfind(name+L" - FPS:",0)==0))return true;
    if(end==std::wstring::npos)break;at=end+1;
  }while(at<names.size());return title==L"GamePad View"||title.rfind(L"GamePad View - FPS:",0)==0;
}
static BOOL CALLBACK windows(HWND window,LPARAM context) {
  DWORD pid=0;GetWindowThreadProcessId(window,&pid);
  if(pid!=GetCurrentProcessId()||GetWindow(window,GW_OWNER)||!IsWindowVisible(window))return TRUE;
  wchar_t title[512];GetWindowTextW(window,title,512);auto* views=reinterpret_cast<Views*>(context);
  HWND* selected=pad_title(title)?&views->pad:!wcsncmp(title,L"Cemu",4)?&views->main:nullptr;
  if(selected){if(*selected){views->ambiguous=true;return FALSE;}*selected=window;}return TRUE;
}
static DWORD WINAPI worker(void*) {
  using Title=unsigned long long(__cdecl*)();
  auto symbol=GetProcAddress(GetModuleHandleW(nullptr),"gameMeta_getTitleId");Title title=nullptr;
  static_assert(sizeof(title)==sizeof(symbol),"Cemu title function ABI changed");memcpy(&title,&symbol,sizeof(title));
  if(!title)ExitProcess(78);
  for(;;) {
    FILE* file=nullptr;
    if(_wfopen_s(&file,command_path.c_str(),L"rb")==0&&file) {
      char received[65],extra;unsigned long long next=0;int active=0,quit=0;
      int count=fscanf_s(file,"%64s %llu %d %d %c",received,static_cast<unsigned>(sizeof(received)),&next,&active,&quit,&extra,1u);
      fclose(file);
      if(count==4&&!strcmp(received,token)&&next>revision&&(active==0||active==1)&&(quit==0||quit==1)) {
        revision=next;playing=active!=0;quitting=quit!=0;
      }
    }
    if(launcher&&WaitForSingleObject(launcher,0)==WAIT_OBJECT_0){playing=false;quitting=true;}
    Views views;EnumWindows(windows,reinterpret_cast<LPARAM>(&views));
    HWND main=views.ambiguous?nullptr:views.main,pad=views.ambiguous?nullptr:views.pad;
    if(pad&&environment(L"BROOMM_REMOTE_SCREEN")==L"1") {
      static HWND sized=nullptr;
      if(sized!=pad) {
        MONITORINFO monitor{};monitor.cbSize=sizeof(monitor);
        if(GetMonitorInfoW(MonitorFromWindow(pad,MONITOR_DEFAULTTONEAREST),&monitor)) {
          LONG width=monitor.rcWork.right-monitor.rcWork.left,height=monitor.rcWork.bottom-monitor.rcWork.top;
          if(width>1600)width=1600;if(width*9/16>height)width=height*16/9;
          LONG_PTR style=GetWindowLongPtrW(pad,GWL_STYLE);
          SetWindowLongPtrW(pad,GWL_STYLE,style&~static_cast<LONG_PTR>(WS_CAPTION|WS_THICKFRAME));
          SetWindowPos(pad,nullptr,monitor.rcWork.left,monitor.rcWork.top,width,width*9/16,SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED);sized=pad;
        }
      }
    }
    wchar_t window_title[1024]{};if(main)GetWindowTextW(main,window_title,1024);
    const bool ready=wcsstr(window_title,L" - FPS:")!=nullptr;
    static unsigned long long closed_revision=~0ULL;
    if(main&&quitting&&revision!=closed_revision){PostMessageW(main,WM_CLOSE,0,0);closed_revision=revision;}
    static bool raised=false;
    if(!playing)raised=false;
    if(main&&playing&&(!raised||(pad&&GetForegroundWindow()==pad))){SetForegroundWindow(main);raised=true;}
    char output[512];int n=snprintf(output,sizeof(output),
      "{\"version\":1,\"pid\":%lu,\"token\":\"%s\",\"ack\":%llu,\"sample\":%llu,\"paused\":0,\"title\":\"%016llx\",\"birth\":\"%llu\"}\n",
      GetCurrentProcessId(),token,revision,++sample,ready?title():0,birth);
    const auto pending=status_path+L".pending";
    HANDLE out=CreateFileW(pending.c_str(),GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if(out!=INVALID_HANDLE_VALUE) {
      BY_HANDLE_FILE_INFORMATION info{};DWORD written=0;
      bool ok=GetFileInformationByHandle(out,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY))&&
        n>0&&n<static_cast<int>(sizeof(output))&&WriteFile(out,output,static_cast<DWORD>(n),&written,nullptr)&&written==static_cast<DWORD>(n);
      CloseHandle(out);
      if(ok)MoveFileExW(pending.c_str(),status_path.c_str(),MOVEFILE_REPLACE_EXISTING);
    }
    Sleep(32);
  }
}

BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID) {
  if(reason!=DLL_PROCESS_ATTACH)return TRUE;
  DisableThreadLibraryCalls(module);
  const auto path=environment(L"BROOMM_CEMU_WRITER");
  status_path=environment(L"BROOMM_CEMU_STATUS");command_path=environment(L"BROOMM_CEMU_COMMAND");
  const auto nonce=environment(L"BROOMM_CEMU_TOKEN");
  if(path.empty()||status_path.empty()||command_path.empty()||nonce.size()!=64)ExitProcess(78);
  for(size_t i=0;i<64;++i){if(!((nonce[i]>=L'0'&&nonce[i]<=L'9')||(nonce[i]>=L'a'&&nonce[i]<=L'f')))ExitProcess(78);token[i]=static_cast<char>(nonce[i]);}
  writer=CreateFileW(path.c_str(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  BY_HANDLE_FILE_INFORMATION info{};OVERLAPPED range{};
  if(writer==INVALID_HANDLE_VALUE||!GetFileInformationByHandle(writer,&info)||
      info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY)||
      !LockFileEx(writer,LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,0,MAXDWORD,MAXDWORD,&range))ExitProcess(78);
  FILETIME created,exited,kernel,user;
  if(!GetProcessTimes(GetCurrentProcess(),&created,&exited,&kernel,&user))ExitProcess(78);
  birth=(static_cast<unsigned long long>(created.dwHighDateTime)<<32)|created.dwLowDateTime;
  broomm_cemu_writer.version=1;broomm_cemu_writer.pid=GetCurrentProcessId();
  broomm_cemu_writer.volume=info.dwVolumeSerialNumber;
  broomm_cemu_writer.inode=(static_cast<uint64_t>(info.nFileIndexHigh)<<32)|info.nFileIndexLow;
  broomm_cemu_writer.birth=birth;memcpy(broomm_cemu_writer.token,token,64);
  MemoryBarrier();broomm_cemu_writer.magic=broomm_cemu_writer_magic;
  if(environment(L"BROOMM_CEMU_SUPERVISED")==L"1") {
    const auto parent=environment(L"BROOMM_CEMU_LAUNCHER_PID"),expected=environment(L"BROOMM_CEMU_LAUNCHER_BIRTH");
    wchar_t* end=nullptr;unsigned long owner=wcstoul(parent.c_str(),&end,10);
    if(parent.empty()||!owner||!end||*end)ExitProcess(78);
    launcher=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,owner);
    FILETIME parent_birth;
    if(!launcher||!GetProcessTimes(launcher,&parent_birth,&exited,&kernel,&user)||
        std::to_wstring((static_cast<unsigned long long>(parent_birth.dwHighDateTime)<<32)|parent_birth.dwLowDateTime)!=expected)ExitProcess(78);
  }
  HANDLE thread=CreateThread(nullptr,0,worker,nullptr,0,nullptr);
  if(!thread)ExitProcess(78);CloseHandle(thread);
  // The kernel closes writer only at process exit, after all native writers.
  return TRUE;
}
