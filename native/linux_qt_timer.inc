// Dispatch through the emulator's actual Qt event loop. Recent GLib/Qt builds
// can issue poll syscalls internally, bypassing libc interposition entirely.
// This small native timer introduces no Qt runtime/SDK dependency in Broomm.
static void *linux_qt_timer,*linux_qt_vtable;
static bool linux_qt_running;
static void qt_timer_event(void *object,void *event) {
 (void)event;if(object==linux_qt_timer)linux_ui_tick();
}
static bool qt_start_dispatch(void) {
 if(!atomic_load(&linux_active)||linux_qt_running)return false;
 void (*construct)(void *,void *)=dlsym(RTLD_DEFAULT,"_ZN6QTimerC1EP7QObject");
 void (*start)(void *,int)=dlsym(RTLD_DEFAULT,"_ZN6QTimer5startEi");
 void *(*allocate)(size_t)=dlsym(RTLD_DEFAULT,"_Znwm");
 void *timer_event=dlsym(RTLD_DEFAULT,"_ZN6QTimer10timerEventEP11QTimerEvent");
 void **table=dlsym(RTLD_DEFAULT,"_ZTV6QTimer");Dl_info image;void *metadata=NULL;
 if(!construct||!start||!allocate||!timer_event||!table||!dladdr1(table,&image,&metadata,RTLD_DL_SYMENT)||!metadata){record("QT_TIMER_UNAVAILABLE constructor=%d start=%d allocator=%d callback=%d table=%d",construct!=NULL,start!=NULL,allocate!=NULL,timer_event!=NULL,table!=NULL);return false;}
 size_t bytes=((const ElfW(Sym) *)metadata)->st_size;
 if(bytes<12*sizeof(void *)||bytes>256||table[9]!=timer_event){record("SESSION_FATAL Qt timer ABI did not match");return false;}
 // Qt 6 QObject contains its vptr and d_ptr. QTimer declares no extra data;
 // its state is in QTimerPrivate. Confirmed in the reviewed Qt headers/builds.
 void *object=allocate(2*sizeof(void *));construct(object,NULL);
 if(*(void ***)object!=table+2){void (*destroy)(void *)=(void *)((void **)*(void ***)object)[4];destroy(object);return false;}
 void **copy=malloc(bytes);if(!copy)_exit(73);memcpy(copy,table,bytes);copy[9]=(void *)qt_timer_event;
 *(void ***)object=copy+2;linux_qt_timer=object;linux_qt_vtable=copy;linux_qt_running=true;start(object,16);
 record("QT_MAIN_DISPATCH native_timer=verified");return true;
}
static void qt_stop_dispatch(void) {
 void *object=linux_qt_timer;linux_qt_running=false;linux_qt_timer=NULL;
 if(object){void (*destroy)(void *)=(void *)((void **)*(void ***)object)[4];destroy(object);free(linux_qt_vtable);linux_qt_vtable=NULL;}
}
int linux_qt_application_exec(void) __asm__("_ZN12QApplication4execEv");
int linux_qt_application_exec(void) {
 int (*next)(void)=dlsym(RTLD_NEXT,"_ZN12QApplication4execEv");bool owner=qt_start_dispatch();int result=next();if(owner)qt_stop_dispatch();return result;
}
int linux_qt_core_exec(void) __asm__("_ZN16QCoreApplication4execEv");
int linux_qt_core_exec(void) {
 int (*next)(void)=dlsym(RTLD_NEXT,"_ZN16QCoreApplication4execEv");bool owner=qt_start_dispatch();int result=next();if(owner)qt_stop_dispatch();return result;
}
int linux_qt_event_exec(void *,int) __asm__("_ZN10QEventLoop4execE6QFlagsINS_17ProcessEventsFlagEE");
int linux_qt_event_exec(void *loop,int flags) {
 int (*next)(void *,int)=dlsym(RTLD_NEXT,"_ZN10QEventLoop4execE6QFlagsINS_17ProcessEventsFlagEE");
 bool owner=syscall(SYS_gettid)==getpid()&&qt_start_dispatch();int result=next(loop,flags);if(owner)qt_stop_dispatch();return result;
}
