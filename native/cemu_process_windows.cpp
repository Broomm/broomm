// Admit the writer DLL before Cemu's application entry point. No domain
// workflow lives here: arguments/environment are supplied literally by Dart.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#include <string>
#include <vector>
#include <cwctype>
#include <cstdio>
#include <cstdint>

static std::wstring quote(const std::wstring& value) {
  std::wstring result=L"\"";size_t slashes=0;
  for(wchar_t c:value) {
    if(c==L'\\'){++slashes;continue;}
    result.append(c==L'"'?slashes*2+1:slashes,L'\\');slashes=0;result+=c;
  }
  result.append(slashes*2,L'\\');return result+L"\"";
}
static std::wstring normalized(std::wstring path) {
  for(auto& c:path){if(c==L'/')c=L'\\';c=static_cast<wchar_t>(towlower(c));}
  return path;
}
static HMODULE module(HANDLE process,const std::wstring& path) {
  HMODULE modules[2048];DWORD needed=0;
  if(!EnumProcessModulesEx(process,modules,sizeof(modules),&needed,LIST_MODULES_ALL)||needed>sizeof(modules))return nullptr;
  for(DWORD i=0;i<needed/sizeof(HMODULE);++i) {
    wchar_t name[4096];DWORD n=GetModuleFileNameExW(process,modules[i],name,4096);
    if(n&&n<4096&&normalized(std::wstring(name,n))==normalized(path))return modules[i];
  }
  return nullptr;
}
static void close_debug_file(const DEBUG_EVENT& event) {
  if(event.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT&&event.u.CreateProcessInfo.hFile)CloseHandle(event.u.CreateProcessInfo.hFile);
  if(event.dwDebugEventCode==LOAD_DLL_DEBUG_EVENT&&event.u.LoadDll.hFile)CloseHandle(event.u.LoadDll.hFile);
}
static bool read(HANDLE process,const void* address,void* value,SIZE_T bytes) {
  SIZE_T copied=0;return ReadProcessMemory(process,address,value,bytes,&copied)&&copied==bytes;
}
static bool patch(HANDLE process,void* address,BYTE value) {
  DWORD original=0,ignored=0;SIZE_T written=0;
  if(!VirtualProtectEx(process,address,1,PAGE_EXECUTE_READWRITE,&original))return false;
  const bool ok=WriteProcessMemory(process,address,&value,1,&written)&&written==1&&FlushInstructionCache(process,address,1);
  const bool restored=VirtualProtectEx(process,address,1,original,&ignored)!=FALSE;return ok&&restored;
}
static bool detached_before_entry(PROCESS_INFORMATION& child) {
  if(ResumeThread(child.hThread)==MAXDWORD)return false;
  const ULONGLONG end=GetTickCount64()+10000;void* entry=nullptr;BYTE original=0;
  while(GetTickCount64()<end) {
    DEBUG_EVENT event{};
    if(!WaitForDebugEvent(&event,250)) {if(GetLastError()==ERROR_SEM_TIMEOUT)continue;return false;}
    close_debug_file(event);DWORD disposition=DBG_CONTINUE;
    if(event.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT) {
      if(entry||event.dwProcessId!=child.dwProcessId)return false;
      const auto base=reinterpret_cast<uintptr_t>(event.u.CreateProcessInfo.lpBaseOfImage);
      IMAGE_DOS_HEADER dos{};IMAGE_NT_HEADERS64 pe{};
      if(!read(child.hProcess,reinterpret_cast<void*>(base),&dos,sizeof(dos))||dos.e_magic!=IMAGE_DOS_SIGNATURE||dos.e_lfanew<0||dos.e_lfanew>1024*1024||
         !read(child.hProcess,reinterpret_cast<void*>(base+static_cast<uintptr_t>(dos.e_lfanew)),&pe,sizeof(pe))||
         pe.Signature!=IMAGE_NT_SIGNATURE||pe.FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||pe.OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||
         !pe.OptionalHeader.AddressOfEntryPoint||pe.OptionalHeader.AddressOfEntryPoint>=pe.OptionalHeader.SizeOfImage)return false;
      entry=reinterpret_cast<void*>(base+pe.OptionalHeader.AddressOfEntryPoint);
      if(!read(child.hProcess,entry,&original,1)||original==0xcc||!patch(child.hProcess,entry,0xcc))return false;
    } else if(event.dwDebugEventCode==EXCEPTION_DEBUG_EVENT) {
      const auto& exception=event.u.Exception;
      const bool breakpoint=exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT&&exception.dwFirstChance;
      if(breakpoint&&entry&&exception.ExceptionRecord.ExceptionAddress==entry) {
        // The initial loader breakpoint still holds loader initialization and
        // cannot admit a remote loader thread. Stop at the PE entry instead:
        // loader work has finished, and no application/CRT entry has executed.
        CONTEXT context{};context.ContextFlags=CONTEXT_CONTROL;
        if(event.dwProcessId!=child.dwProcessId||event.dwThreadId!=child.dwThreadId||
           !patch(child.hProcess,entry,original)||!GetThreadContext(child.hThread,&context)||
           context.Rip!=reinterpret_cast<uintptr_t>(entry)+1)return false;
        context.Rip=reinterpret_cast<uintptr_t>(entry);
        if(!SetThreadContext(child.hThread,&context)||SuspendThread(child.hThread)==MAXDWORD)return false;
        return ContinueDebugEvent(event.dwProcessId,event.dwThreadId,DBG_CONTINUE)&&DebugActiveProcessStop(child.dwProcessId);
      }
      if(!breakpoint)disposition=DBG_EXCEPTION_NOT_HANDLED;
    } else if(event.dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT) {
      ContinueDebugEvent(event.dwProcessId,event.dwThreadId,DBG_CONTINUE);return false;
    }
    if(!ContinueDebugEvent(event.dwProcessId,event.dwThreadId,disposition))return false;
  }
  SetLastError(ERROR_TIMEOUT);return false;
}
static void reject(PROCESS_INFORMATION& child,const char* phase,DWORD error) {
  // A failed pre-entry admission must not leave a child behind. Drain pending
  // debugger events as well: Windows can defer exit until they are continued.
  TerminateProcess(child.hProcess,78);DebugActiveProcessStop(child.dwProcessId);
  while(WaitForSingleObject(child.hProcess,50)!=WAIT_OBJECT_0) {
    DEBUG_EVENT event{};
    if(WaitForDebugEvent(&event,50)){close_debug_file(event);ContinueDebugEvent(event.dwProcessId,event.dwThreadId,DBG_CONTINUE);}
  }
  CloseHandle(child.hThread);CloseHandle(child.hProcess);
  fprintf(stderr,"Broomm could not establish Cemu's native writer during %s (Windows error %lu). Existing progress was kept.\n",phase,error);
}
static bool inject(PROCESS_INFORMATION& child,const std::wstring& dll) {
  FARPROC function=GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"LoadLibraryW");HMODULE local=nullptr;
  if(!function||!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(function),&local))return false;
  wchar_t owner[4096];DWORD n=GetModuleFileNameW(local,owner,4096);
  HMODULE remote=n&&n<4096?module(child.hProcess,std::wstring(owner,n)):nullptr;
  if(!remote)return false;
  auto entry=reinterpret_cast<LPTHREAD_START_ROUTINE>(reinterpret_cast<uintptr_t>(remote)+reinterpret_cast<uintptr_t>(function)-reinterpret_cast<uintptr_t>(local));
  SIZE_T bytes=(dll.size()+1)*sizeof(wchar_t),written=0;
  void* memory=VirtualAllocEx(child.hProcess,nullptr,bytes,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
  if(!memory)return false;
  bool ok=WriteProcessMemory(child.hProcess,memory,dll.c_str(),bytes,&written)&&written==bytes;
  HANDLE thread=ok?CreateRemoteThread(child.hProcess,nullptr,0,entry,memory,0,nullptr):nullptr;
  ok=thread&&WaitForSingleObject(thread,10000)==WAIT_OBJECT_0&&WaitForSingleObject(child.hProcess,0)==WAIT_TIMEOUT&&module(child.hProcess,dll);
  if(thread)CloseHandle(thread);
  // Do not free an argument still being read by a timed-out loader thread.
  if(ok)VirtualFreeEx(child.hProcess,memory,0,MEM_RELEASE);
  return ok;
}
int wmain(int argc,wchar_t** argv) {
  if(argc<3||wcslen(argv[1])>4095||wcslen(argv[2])>4095)return 64;
  std::wstring command;
  for(int i=2;i<argc;++i){if(!command.empty())command+=L' ';command+=quote(argv[i]);}
  if(command.size()>32766)return 64;
  STARTUPINFOW startup{};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESTDHANDLES;
  startup.hStdInput=GetStdHandle(STD_INPUT_HANDLE);startup.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);startup.hStdError=GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION child{};
  if(!CreateProcessW(argv[2],command.data(),nullptr,nullptr,TRUE,CREATE_SUSPENDED|DEBUG_ONLY_THIS_PROCESS,nullptr,nullptr,&startup,&child))return 73;
  if(!detached_before_entry(child)){const DWORD error=GetLastError();reject(child,"application entry",error);return 78;}
  if(!inject(child,argv[1])){const DWORD error=GetLastError();reject(child,"writer injection",error);return 78;}
  if(ResumeThread(child.hThread)==MAXDWORD){const DWORD error=GetLastError();reject(child,"application resume",error);return 78;}
  CloseHandle(child.hThread);
  if(WaitForSingleObject(child.hProcess,INFINITE)!=WAIT_OBJECT_0){CloseHandle(child.hProcess);return 74;}
  DWORD code=74;GetExitCodeProcess(child.hProcess,&code);CloseHandle(child.hProcess);
  return static_cast<int>(code);
}
