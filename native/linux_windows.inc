// Window operations address only this emulator's native window. They do not
// select by a global title or affect another application/window manager.
static void psp_window_tick(void) {
 if(!getenv("BROOMM_PPSSPP"))return;
 void *(*find)(uint32_t)=symbol("SDL_GetWindowFromID");
 void (*show)(void *)=symbol("SDL_ShowWindow"),(*hide)(void *)=symbol("SDL_HideWindow"),(*raise)(void *)=symbol("SDL_RaiseWindow");
 if(!find||!show||!hide||!raise)return;void *window=NULL;
 for(uint32_t i=1;i<32&&!window;++i)window=find(i);if(!window)return;
 int actual=atomic_load(&control_paused);atomic_store(&session_paused,actual);
 if(atomic_load(&session_quit)) {
  atomic_store(&session_finishing,true);
  if(atomic_load(&session_worker_stopped)&&atomic_load(&control_finished)) {
   int (*push)(void *)=symbol("SDL_PushEvent");_Alignas(8) unsigned char event[56]={0};uint32_t type=0x100;memcpy(event,&type,4);
   static bool sent;if(push&&!sent){sent=true;push(event);}
  }return;
 }
 if(actual>=0){bool hidden=atomic_load(&session_gate)&&!atomic_load(&linux_orphaned);if(hidden!=ui_hidden){if(hidden)hide(window);else{show(window);raise(window);}ui_hidden=hidden;}}
 atomic_store(&app_active,actual>=0);
}
#include <X11/Xlib.h>
static void linux_sdk_window_tick(void) {
 if(getenv("BROOMM_PPSSPP"))return;
 static Display *display;static Window window;static bool hidden;
 void *library=dlopen("libX11.so.6",RTLD_LAZY|RTLD_NOLOAD);if(!library)return;
 Display *(*open_display)(const char *)=dlsym(library,"XOpenDisplay");
 Window (*root)(Display *)=dlsym(library,"XDefaultRootWindow");
 Atom (*atom)(Display *,const char *,Bool)=dlsym(library,"XInternAtom");
 int (*property)(Display *,Window,Atom,long,long,Bool,Atom,Atom *,int *,unsigned long *,unsigned long *,unsigned char **)=dlsym(library,"XGetWindowProperty");
 int (*release)(void *)=dlsym(library,"XFree");int (*flush)(Display *)=dlsym(library,"XFlush");
 int (*map)(Display *,Window)=dlsym(library,"XMapRaised"),(*unmap)(Display *,Window)=dlsym(library,"XUnmapWindow");
 Status (*send_event)(Display *,Window,Bool,long,XEvent *)=dlsym(library,"XSendEvent");
 if(!open_display||!root||!atom||!property||!release||!flush||!map||!unmap||!send_event){dlclose(library);return;}
 if(!display)display=open_display(NULL);if(!display){dlclose(library);return;}
 if(!window){Atom actual;int format;unsigned long count,left;unsigned char *data=NULL;
  if(!property(display,root(display),atom(display,"_NET_CLIENT_LIST",False),0,4096,False,AnyPropertyType,&actual,&format,&count,&left,&data)&&format==32&&count<=4096) {
   Window *windows=(void *)data;
   for(unsigned long i=0;i<count&&!window;++i){unsigned char *pid_data=NULL;unsigned long n,remaining;int bits;
    if(!property(display,windows[i],atom(display,"_NET_WM_PID",False),0,1,False,AnyPropertyType,&actual,&bits,&n,&remaining,&pid_data)&&bits==32&&n==1&&*(unsigned long *)pid_data==(unsigned long)getpid())window=windows[i];
    if(pid_data)release(pid_data);
   }
  }if(data)release(data);
 }
 if(window) {
  int actual=atomic_load(&control_paused);atomic_store(&session_paused,actual);atomic_store(&app_active,actual>=0);
  if(atomic_load(&session_quit)) {
   atomic_store(&session_finishing,true);
   if(atomic_load(&session_worker_stopped)){XEvent event;memset(&event,0,sizeof(event));event.xclient.type=ClientMessage;event.xclient.window=window;event.xclient.message_type=atom(display,"WM_PROTOCOLS",False);event.xclient.format=32;event.xclient.data.l[0]=(long)atom(display,"WM_DELETE_WINDOW",False);send_event(display,window,False,0,&event);}
  } else if(actual>=0) {
   bool wanted=atomic_load(&session_gate)&&!atomic_load(&linux_orphaned);
   if(wanted!=hidden){if(wanted)unmap(display,window);else map(display,window);hidden=wanted;}
  }flush(display);
 }
 dlclose(library);
}
