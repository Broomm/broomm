// Real Win32 processes exercise the shipped injector, writer and pause adapter.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "../../native/cemu_windows_host.h"
#include <fstream>
#include <iostream>
#include <vector>
#include <cassert>
extern "C" __declspec(dllexport) unsigned long long gameMeta_getTitleId() {return 0x0005000012345678ULL;}
static std::wstring env(const wchar_t* name) {wchar_t v[4096];DWORD n=GetEnvironmentVariableW(name,v,4096);return n&&n<4096?std::wstring(v,n):L"";}
static std::string utf8(const std::wstring& v) {int n=WideCharToMultiByte(CP_UTF8,0,v.data(),static_cast<int>(v.size()),nullptr,0,nullptr,nullptr);std::string r(n,'\0');WideCharToMultiByte(CP_UTF8,0,v.data(),static_cast<int>(v.size()),r.data(),n,nullptr,nullptr);return r;}
static std::wstring quote(const std::wstring& v) {std::wstring r=L"\"";size_t slashes=0;for(auto c:v){if(c==L'\\'){++slashes;continue;}r.append(c==L'"'?slashes*2+1:slashes,L'\\');slashes=0;r+=c;}r.append(slashes*2,L'\\');return r+L"\"";}
static LRESULT CALLBACK window(HWND h,UINT m,WPARAM w,LPARAM l) {if(m==WM_CLOSE){std::ofstream out(env(L"BROOMM_CEMU_CLOSED"));out<<"normal";DestroyWindow(h);PostQuitMessage(0);return 0;}return DefWindowProcW(h,m,w,l);}
static void write(const std::wstring& p,const std::string& value) {std::ofstream out(p,std::ios::binary);out<<value;out.close();assert(out);}
static PROCESS_INFORMATION launch(const std::wstring& helper,const std::wstring& dll,const std::wstring& child) {
  std::wstring cmd=quote(helper)+L" "+quote(dll)+L" "+quote(child)+L" --child "+quote(L"literal \"quoted\" tail\\");
  STARTUPINFOW si{};si.cb=sizeof(si);PROCESS_INFORMATION pi{};
  assert(CreateProcessW(helper.c_str(),cmd.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&si,&pi));CloseHandle(pi.hThread);return pi;
}
static void ended(PROCESS_INFORMATION& pi,DWORD expected) {assert(WaitForSingleObject(pi.hProcess,15000)==WAIT_OBJECT_0);DWORD code=1;assert(GetExitCodeProcess(pi.hProcess,&code)&&code==expected);CloseHandle(pi.hProcess);}
static bool refused(const broomm_remote::Identity& identity) {try{broomm_remote::Process p;broomm_remote::inspect(p,identity);return false;}catch(const std::string&){return true;}}
int wmain(int argc,wchar_t** argv) {
  if(argc==2&&!wcscmp(argv[1],L"--owner")){Sleep(INFINITE);return 0;}
  if(argc==3&&!wcscmp(argv[1],L"--child")) {
    assert(std::wstring(argv[2])==L"literal \"quoted\" tail\\");
    HANDLE writer=CreateFileW(env(L"BROOMM_CEMU_WRITER").c_str(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);OVERLAPPED range{};
    assert(writer!=INVALID_HANDLE_VALUE&&!LockFileEx(writer,LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,0,MAXDWORD,MAXDWORD,&range)&&GetLastError()==ERROR_LOCK_VIOLATION);CloseHandle(writer);
    WNDCLASSW cls{};cls.lpfnWndProc=window;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"BroommCemuFixture";assert(RegisterClassW(&cls));
    HWND main=CreateWindowW(cls.lpszClassName,L"Cemu 2.6 - FPS: 60",WS_OVERLAPPEDWINDOW,0,0,640,480,nullptr,nullptr,cls.hInstance,nullptr);assert(main);ShowWindow(main,SW_SHOW);
    FILETIME b,e,k,u;assert(GetProcessTimes(GetCurrentProcess(),&b,&e,&k,&u));
    write(env(L"BROOMM_CEMU_READY"),std::to_string(GetCurrentProcessId())+" "+std::to_string((static_cast<uint64_t>(b.dwHighDateTime)<<32)|b.dwLowDateTime));
    MSG message;while(GetMessageW(&message,nullptr,0,0)>0){TranslateMessage(&message);DispatchMessageW(&message);}return 0;
  }
  assert(argc==5);std::wstring helper=argv[1],dll=argv[2],self=argv[3],root=argv[4];
  CreateDirectoryW(root.c_str(),nullptr);
  const auto writer=root+L"\\writer.lock",status=root+L"\\status.json",command=root+L"\\command.txt",ready=root+L"\\ready",closed=root+L"\\closed";
  const std::string token(64,'a');write(writer,"");write(command,token+" 1 0 0\n");
  SetEnvironmentVariableW(L"BROOMM_CEMU_WRITER",writer.c_str());SetEnvironmentVariableW(L"BROOMM_CEMU_STATUS",status.c_str());SetEnvironmentVariableW(L"BROOMM_CEMU_COMMAND",command.c_str());SetEnvironmentVariableW(L"BROOMM_CEMU_TOKEN",std::wstring(64,L'a').c_str());SetEnvironmentVariableW(L"BROOMM_CEMU_READY",ready.c_str());SetEnvironmentVariableW(L"BROOMM_CEMU_CLOSED",closed.c_str());
  auto child=launch(helper,dll,self);DWORD pid=0;std::string birth;
  const auto until=GetTickCount64()+15000;
  while(GetTickCount64()<until){std::ifstream in(ready);if(in>>pid>>birth)break;if(WaitForSingleObject(child.hProcess,0)!=WAIT_TIMEOUT)break;Sleep(20);}assert(pid&&birth.size());
  broomm_remote::Identity identity{pid,birth,utf8(self),utf8(dll),utf8(writer),token};
  broomm_remote::Process process;broomm_remote::inspect(process,identity);
  auto changed=identity;changed.birth="1";assert(refused(changed));changed=identity;changed.token[0]='b';assert(refused(changed));
  const auto other=root+L"\\other.lock";write(other,"");HANDLE other_lock=CreateFileW(other.c_str(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);OVERLAPPED region{};assert(LockFileEx(other_lock,LOCKFILE_EXCLUSIVE_LOCK,0,MAXDWORD,MAXDWORD,&region));changed=identity;changed.writer=utf8(other);assert(refused(changed));CloseHandle(other_lock);
  broomm_remote::PauseController pause;pause.pause(process);assert(pause.paused_pid==pid);
  write(command,token+" 2 0 1\n");assert(WaitForSingleObject(child.hProcess,200)==WAIT_TIMEOUT); // normal close cannot run while frozen
  pause.resume();ended(child,0);
  std::ifstream close_result(closed);std::string result;close_result>>result;assert(result=="normal");close_result.close();assert(refused(identity));
  puts("PASS: writer admitted before application entry; literal arguments survive Windows quoting");
  puts("PASS: kernel pause/resume preserves normal close; changed birth, token and another busy lock are refused");
  // A supervised game loses its DSU producer when the verified launcher exits.
  // The native guard must request normal closure rather than retain stale input.
  DeleteFileW(ready.c_str());DeleteFileW(closed.c_str());
  std::wstring owner_command=quote(self)+L" --owner";STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION owner{};
  assert(CreateProcessW(self.c_str(),owner_command.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&startup,&owner));CloseHandle(owner.hThread);
  FILETIME born,exited,kernel,user;assert(GetProcessTimes(owner.hProcess,&born,&exited,&kernel,&user));
  SetEnvironmentVariableW(L"BROOMM_CEMU_SUPERVISED",L"1");
  SetEnvironmentVariableW(L"BROOMM_CEMU_LAUNCHER_PID",std::to_wstring(owner.dwProcessId).c_str());
  SetEnvironmentVariableW(L"BROOMM_CEMU_LAUNCHER_BIRTH",std::to_wstring((static_cast<uint64_t>(born.dwHighDateTime)<<32)|born.dwLowDateTime).c_str());
  write(command,token+" 1 0 0\n");auto supervised=launch(helper,dll,self);DWORD supervised_pid=0;std::string supervised_birth;
  const auto wait_ready=GetTickCount64()+15000;
  while(GetTickCount64()<wait_ready){std::ifstream in(ready);if(in>>supervised_pid>>supervised_birth)break;Sleep(20);}assert(supervised_pid);
  assert(TerminateProcess(owner.hProcess,0));ended(owner,0);ended(supervised,0);
  std::ifstream normal(closed);normal>>result;assert(result=="normal");
  SetEnvironmentVariableW(L"BROOMM_CEMU_SUPERVISED",L"0");
  puts("PASS: verified launcher death requests normal Cemu closure and cannot leave stale DSU input running");
  // An unavailable DLL must never admit the application entry point.
  DeleteFileW(ready.c_str());auto rejected=launch(helper,root+L"\\missing.dll",self);ended(rejected,78);assert(GetFileAttributesW(ready.c_str())==INVALID_FILE_ATTRIBUTES);
  puts("PASS: pre-entry injection failure cannot start the application writer");return 0;
}
