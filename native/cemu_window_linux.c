#define _GNU_SOURCE
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
static Display *guard_display;
static int (*previous_error)(Display *,XErrorEvent *);
static int window_error(Display *display,XErrorEvent *error) {
  // A disappearing owned view must not invoke Xlib's fatal default handler
  // or alter Cemu's other display connection.
  return display==guard_display?0:previous_error?previous_error(display,error):0;
}
void broomm_cemu_window_initialize(void) { XInitThreads(); previous_error=XSetErrorHandler(window_error); }
static bool game_ready;
bool broomm_cemu_window_ready(void) { return game_ready; }
bool broomm_cemu_window_geometry(double out[5]) { (void)out;return false; }

static bool pad_title(const char *title) {
  const char *titles=getenv("BROOMM_CEMU_PAD_TITLES");
  if(!titles)titles="GamePad View";
  for(const char *at=titles;*at;) {
    const char *end=strchr(at,'|');size_t n=end?(size_t)(end-at):strlen(at);
    if(!strncmp(title,at,n)&&(strlen(title)==n||!strncmp(title+n," - FPS:",7)))return true;
    if(!end)break;at=end+1;
  }
  return false;
}

// The pinned Linux Cemu is X11. Operate only on its own top-level windows.
void broomm_cemu_window_tick(bool playing, bool quit, uint64_t request) {
  static Display *display;
  static bool attempted, ordered;
  static uint64_t closed_revision=UINT64_MAX;
  if (!attempted) { attempted=true; display=XOpenDisplay(NULL);guard_display=display; }
  if (!display) return;
  Atom actual; int format; unsigned long count,left; unsigned char *bytes=NULL;
  if (XGetWindowProperty(display,DefaultRootWindow(display),XInternAtom(display,"_NET_CLIENT_LIST",False),0,4096,False,XA_WINDOW,&actual,&format,&count,&left,&bytes) || !bytes) return;
  Window main=0,pad=0;
  game_ready=false;
  if (actual==XA_WINDOW && format==32 && !left && count<=4096) {
    for (unsigned long i=0;i<count;++i) {
      Window window=((Window *)bytes)[i]; unsigned char *owner=NULL; unsigned long owners,remaining;
      if (XGetWindowProperty(display,window,XInternAtom(display,"_NET_WM_PID",False),0,1,False,XA_CARDINAL,&actual,&format,&owners,&remaining,&owner)) continue;
      bool ours=owner&&actual==XA_CARDINAL&&format==32&&owners==1&&*(unsigned long *)owner==(unsigned long)getpid();
      if(owner)XFree(owner); if(!ours)continue;
      char *name=NULL;unsigned char* utf8=NULL;unsigned long names,more;
      if(!XGetWindowProperty(display,window,XInternAtom(display,"_NET_WM_NAME",False),0,1024,False,XInternAtom(display,"UTF8_STRING",False),&actual,&format,&names,&more,&utf8)&&utf8&&format==8&&!more)name=(char*)utf8;
      else {if(utf8)XFree(utf8);XFetchName(display,window,&name);}
      if(name) {
        if(pad_title(name)) { if(pad){main=0;XFree(name);break;}pad=window; }
        else if(!strncmp(name,"Cemu",4)) { if(main){main=0;XFree(name);break;}main=window;game_ready=strstr(name," - FPS:")!=NULL; }
        XFree(name);
      }
    }
  }
  XFree(bytes);
  if (!playing) ordered=false;
  if (main && quit && request!=closed_revision) {
    XEvent event={0};event.xclient.type=ClientMessage;event.xclient.window=main;
    event.xclient.message_type=XInternAtom(display,"WM_PROTOCOLS",False);event.xclient.format=32;
    event.xclient.data.l[0]=(long)XInternAtom(display,"WM_DELETE_WINDOW",False);event.xclient.data.l[1]=CurrentTime;
    XSendEvent(display,main,False,NoEventMask,&event);closed_revision=request;
  }
  if(main&&pad&&getenv("BROOMM_REMOTE_SCREEN")) {
    static Window sized;
    if(sized!=pad) {
      // The WebRTC desktop backend captures the whole window. A private,
      // borderless 16:9 GamePad keeps video and normalized touch aligned.
      struct {unsigned long flags,functions,decorations;long input;unsigned long status;} hints={2,0,0,0,0};
      Atom motif=XInternAtom(display,"_MOTIF_WM_HINTS",False);
      XChangeProperty(display,pad,motif,motif,32,PropModeReplace,(unsigned char*)&hints,5);
      int width=DisplayWidth(display,DefaultScreen(display)),height=DisplayHeight(display,DefaultScreen(display));
      if(width>1600)width=1600;if(width*9/16>height)width=height*16/9;
      XMoveResizeWindow(display,pad,0,0,(unsigned)width,(unsigned)(width*9/16));sized=pad;
    }
    Window focused;int revert;XGetInputFocus(display,&focused,&revert);
    if(playing&&(!ordered||focused==pad)){XRaiseWindow(display,main);ordered=true;}
  }
  XFlush(display);
}
