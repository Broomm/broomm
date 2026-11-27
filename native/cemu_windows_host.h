// Windows OS interop shared by the Flutter boundary and native regressions.
#ifndef BROOMM_CEMU_WINDOWS_HOST_H
#define BROOMM_CEMU_WINDOWS_HOST_H
#include <windows.h>
#include <psapi.h>
#include <string>
#include <cstring>
#include <cstdint>
#include <cwctype>
#include "cemu_windows_identity.h"
namespace broomm_remote {
inline std::wstring wide(const std::string& value) {
  int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
  if(!n)throw std::string("Invalid emulator path encoding.");std::wstring result(n,L'\0');
  MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),result.data(),n);return result;
}
inline std::wstring normalized(std::wstring value) {
  for(auto& c:value){if(c==L'/')c=L'\\';c=static_cast<wchar_t>(towlower(c));}return value;
}
struct Process {
  HANDLE handle=nullptr;DWORD pid=0;std::string birth;std::wstring executable,guard;
  Process()=default;Process(const Process&)=delete;
  ~Process(){if(handle)CloseHandle(handle);}
};
inline BroommCemuWriterIdentity writer_record(HANDLE process,HMODULE module) {
  MODULEINFO info{};
  if(!GetModuleInformation(process,module,&info,sizeof(info))||info.SizeOfImage>16*1024*1024)throw std::string("Invalid Cemu writer module.");
  auto read=[&](uint64_t offset,void* output,size_t bytes) {
    SIZE_T copied=0;
    if(offset>info.SizeOfImage||bytes>info.SizeOfImage-offset||
        !ReadProcessMemory(process,reinterpret_cast<const char*>(module)+offset,output,bytes,&copied)||copied!=bytes)
      throw std::string("The live Cemu writer identity could not be read.");
  };
  IMAGE_DOS_HEADER dos{};read(0,&dos,sizeof(dos));
  if(dos.e_magic!=IMAGE_DOS_SIGNATURE||dos.e_lfanew<0)throw std::string("Invalid Cemu writer image.");
  IMAGE_NT_HEADERS64 image{};read(static_cast<DWORD>(dos.e_lfanew),&image,sizeof(image));
  if(image.Signature!=IMAGE_NT_SIGNATURE||image.FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||image.OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC)
    throw std::string("Invalid Cemu writer architecture.");
  const auto section=image.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
  IMAGE_EXPORT_DIRECTORY exports{};read(section.VirtualAddress,&exports,sizeof(exports));
  if(exports.NumberOfNames>64||exports.NumberOfFunctions>64)throw std::string("Invalid Cemu writer exports.");
  for(DWORD i=0;i<exports.NumberOfNames;++i) {
    DWORD name=0;read(exports.AddressOfNames+i*sizeof(DWORD),&name,sizeof(name));
    char symbol[25]{};read(name,symbol,sizeof(symbol));
    if(std::memcmp(symbol,"broomm_cemu_writer",sizeof("broomm_cemu_writer"))!=0)continue;
    WORD index=0;read(exports.AddressOfNameOrdinals+i*sizeof(WORD),&index,sizeof(index));
    if(index>=exports.NumberOfFunctions)throw std::string("Invalid Cemu writer ordinal.");
    DWORD address=0;read(exports.AddressOfFunctions+index*sizeof(DWORD),&address,sizeof(address));
    if(address>=section.VirtualAddress&&address-section.VirtualAddress<section.Size)throw std::string("Forwarded Cemu writer exports are unsupported.");
    BroommCemuWriterIdentity result{};read(address,&result,sizeof(result));return result;
  }
  throw std::string("Cemu has no live writer identity export.");
}
struct Identity {int64_t pid;std::string birth,executable,guard,writer,token;};
inline void inspect(Process& process,const Identity& identity) {
  const auto pid=identity.pid;if(pid<1||pid>MAXDWORD)throw std::string("Invalid Cemu process.");
  process.pid=static_cast<DWORD>(pid);process.birth=identity.birth;process.executable=normalized(wide(identity.executable));
  process.guard=normalized(wide(identity.guard));
  process.handle=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ|SYNCHRONIZE,FALSE,process.pid);
  if(!process.handle||WaitForSingleObject(process.handle,0)!=WAIT_TIMEOUT)throw std::string("The emulator process ended or cannot be inspected.");
  FILETIME created,exited,kernel,user;
  if(!GetProcessTimes(process.handle,&created,&exited,&kernel,&user)||
      std::to_string((static_cast<unsigned long long>(created.dwHighDateTime)<<32)|created.dwLowDateTime)!=process.birth)
    throw std::string("The emulator process identity changed.");
  wchar_t executable[4096];DWORD count=4096;
  if(!QueryFullProcessImageNameW(process.handle,0,executable,&count)||normalized(std::wstring(executable,count))!=process.executable)
    throw std::string("The emulator executable changed.");
  HMODULE modules[2048];DWORD bytes=0;HMODULE admitted=nullptr;
  if(!EnumProcessModulesEx(process.handle,modules,sizeof(modules),&bytes,LIST_MODULES_ALL)||bytes>sizeof(modules))
    throw std::string("The emulator's private writer could not be verified.");
  for(DWORD i=0;i<bytes/sizeof(HMODULE);++i) {
    wchar_t name[4096];DWORD n=GetModuleFileNameExW(process.handle,modules[i],name,4096);
    if(n&&n<4096&&normalized(std::wstring(name,n))==process.guard)admitted=modules[i];
  }
  if(!admitted)throw std::string("Cemu has no admitted Broomm writer.");
  const auto path=wide(identity.writer);
  HANDLE writer=CreateFileW(path.c_str(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  BY_HANDLE_FILE_INFORMATION info{};OVERLAPPED region{};
  if(writer==INVALID_HANDLE_VALUE)throw std::string("The private Cemu writer lock is unavailable.");
  bool regular=GetFileInformationByHandle(writer,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY));
  BroommCemuWriterIdentity record{};std::string token;
  try { record=writer_record(process.handle,admitted);token=identity.token; }
  catch(...){CloseHandle(writer);throw;}
  const bool same=record.magic==broomm_cemu_writer_magic&&record.version==1&&record.pid==process.pid&&
    std::to_string(record.birth)==process.birth&&record.volume==info.dwVolumeSerialNumber&&
    record.inode==((static_cast<uint64_t>(info.nFileIndexHigh)<<32)|info.nFileIndexLow)&&token.size()==64&&std::memcmp(record.token,token.data(),64)==0;
  bool locked=regular&&LockFileEx(writer,LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,0,MAXDWORD,MAXDWORD,&region);
  DWORD error=GetLastError();if(locked)UnlockFileEx(writer,0,MAXDWORD,MAXDWORD,&region);CloseHandle(writer);
  if(!regular||!same||locked||error!=ERROR_LOCK_VIOLATION)throw std::string("Cemu's writer lock is not confirmed. Existing progress was kept.");
}
struct PauseController {
  DWORD paused_pid=0,paused_thread=0;HANDLE paused_handle=nullptr;std::string paused_birth;
  ~PauseController(){try{resume();}catch(...) {if(paused_handle)CloseHandle(paused_handle);}}
  void resume() {
    if(!paused_pid)return;
    const DWORD pid=paused_pid,thread=paused_thread;
    // Keep the retained kernel process handle until debugger detachment. A
    // terminated process cannot redirect this operation to a recycled PID.
    if(WaitForSingleObject(paused_handle,0)==WAIT_TIMEOUT) {
      if(!ContinueDebugEvent(pid,thread,DBG_CONTINUE)||!DebugActiveProcessStop(pid))
        throw std::string("Windows could not resume Cemu. Close Broomm to detach its pause controller.");
    }
    CloseHandle(paused_handle);paused_handle=nullptr;paused_pid=0;paused_thread=0;paused_birth.clear();
  }
  void pause(Process& process) {
    if(paused_pid) {
      if(paused_pid!=process.pid||paused_birth!=process.birth)throw std::string("Another Cemu pause controller is still active.");
      return;
    }
    if(!DebugActiveProcess(process.pid))throw std::string("Windows could not pause Cemu. Another debugger or host policy may own it; input remains blocked.");
    if(!DebugSetProcessKillOnExit(FALSE)){DebugActiveProcessStop(process.pid);throw std::string("Windows could not establish a recoverable Cemu pause.");}
    const auto end=GetTickCount64()+2000;
    while(GetTickCount64()<end) {
      DEBUG_EVENT event{};
      if(!WaitForDebugEvent(&event,100))continue;
      DWORD disposition=DBG_CONTINUE;
      if(event.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT&&event.u.CreateProcessInfo.hFile)CloseHandle(event.u.CreateProcessInfo.hFile);
      if(event.dwDebugEventCode==LOAD_DLL_DEBUG_EVENT&&event.u.LoadDll.hFile)CloseHandle(event.u.LoadDll.hFile);
      if(event.dwDebugEventCode==EXCEPTION_DEBUG_EVENT) {
        if(event.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT&&event.u.Exception.dwFirstChance&&event.dwProcessId==process.pid) {
          paused_pid=process.pid;paused_thread=event.dwThreadId;paused_birth=process.birth;
          DuplicateHandle(GetCurrentProcess(),process.handle,GetCurrentProcess(),&paused_handle,0,FALSE,DUPLICATE_SAME_ACCESS);
          if(!paused_handle){ContinueDebugEvent(event.dwProcessId,event.dwThreadId,DBG_CONTINUE);DebugActiveProcessStop(process.pid);paused_pid=0;throw std::string("Windows could not retain the paused process identity.");}
          return;
        }
        disposition=DBG_EXCEPTION_NOT_HANDLED;
      }
      ContinueDebugEvent(event.dwProcessId,event.dwThreadId,disposition);
      if(event.dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT)break;
    }
    DebugActiveProcessStop(process.pid);throw std::string("Cemu did not acknowledge a Windows pause. Input remains blocked.");
  }
};
}
#endif
