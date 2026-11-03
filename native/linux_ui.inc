// Native UI work runs only on the process's main event-loop thread. No Qt copy
// is loaded: these calls resolve from the hash-pinned application's Qt runtime.
struct QtArray {void *allocation;void **data;long size;};
struct QtString {void *allocation;const uint16_t *data;long size;};
static void *qt_main;
static uint32_t *rpcs_status,*rpcs_ftotal,*rpcs_fdone,*rpcs_ptotal,*rpcs_pdone;
static uint64_t *rpcs_ftotal_bits,*rpcs_fknown_bits;
static void *core_system_fn,*core_state_fn,*core_set_state_fn;
static _Atomic bool linux_active;
static bool ui_hidden,had_game;
static _Atomic bool game_window_visible;
#include "linux_window_handoff.h"
static bool hide_game_window(void) {
 return broomm_hide_game_window(atomic_load(&session_gate),atomic_load(&linux_orphaned),getenv("BROOMM_MAPPED_LAUNCHER"));
}
#include "linux_qt_timer.inc"
static double last_game;
static pthread_mutex_t dispatch_lock=PTHREAD_MUTEX_INITIALIZER;
struct UiWork {void *context;void (*callback)(void *);};
static struct UiWork ui_work[128];static int ui_work_count;
static void linux_dispatch(void *context,void (*callback)(void *)) {
 pthread_mutex_lock(&dispatch_lock);
 for(int i=0;i<ui_work_count;++i)if(ui_work[i].context==context&&ui_work[i].callback==callback){pthread_mutex_unlock(&dispatch_lock);return;}
 if(ui_work_count<128)ui_work[ui_work_count++]=(struct UiWork){context,callback};
 else atomic_store(&watch_queue_overflow,true);
 pthread_mutex_unlock(&dispatch_lock);
}
static void qt_release(void *allocation,size_t item_size,size_t alignment) {
 if(!allocation||__atomic_fetch_sub((int *)allocation,1,__ATOMIC_ACQ_REL)!=1)return;
 void (*free_array)(void *,long long,long long)=dlsym(RTLD_DEFAULT,"_ZN10QArrayData10deallocateEPS_xx");
 if(free_array)free_array(allocation,(long long)item_size,(long long)alignment);
 else free(allocation); // These reviewed Qt 6 arrays use malloc alignment.
}
static void qt_text(struct QtString text,char *out,size_t capacity) {
 long n=text.size;if(n<0)n=0;if((size_t)n>=capacity)n=(long)capacity-1;
 for(long i=0;i<n;++i)out[i]=text.data[i]<128?(char)text.data[i]:'?';out[n]=0;
 qt_release(text.allocation,sizeof(uint16_t),_Alignof(uint16_t));
}
static const char *qt_class(void *object) {
 const void *(*meta)(void *)=(void *)((void **)*(void ***)object)[0];
 const char *(*name)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK11QMetaObject9classNameEv");
 return meta&&name?name(meta(object)):"";
}
struct Actions {void *pause,*loading,*configure,*stop;char pause_text[128];};
static bool trace_actions;
static void qt_actions(void *object,struct Actions *result,int depth) {
 if(!object||depth>12)return;
 const char *kind=qt_class(object);
 if(!strcmp(kind,"QAction")) {
  struct QtString (*text)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QAction4textEv");
  struct QtString (*object_name)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QObject10objectNameEv");
  char value[128]={0},name[128]={0};if(text)qt_text(text(object),value,sizeof(value));if(object_name)qt_text(object_name(object),name,sizeof(name));
  if(trace_actions)record("QT_ACTION name=%s text=%s",name,value);
  if(!strcmp(name,"action_Configure"))result->configure=object;
  if(!strcmp(value,"Stop"))result->stop=object;
  if(!strcmp(name,"action_Pause")||!strcmp(name,"actionPause")||!strcmp(name,"actionPauseEmulation")||(!getenv("BROOMM_EDEN")&&!strcmp(value,"Pause"))) {
   result->pause=object;snprintf(result->pause_text,sizeof(result->pause_text),"%s",value);
  }
 }
 if(!strcmp(kind,"LoadingScreen"))result->loading=object;
 // QObjectData::children is part of the reviewed Qt 6 object ABI. Read only on
 // the owning UI thread; full application/Qt inventories are verified at setup.
 void *data=*((void **)object+1);if(!data)return;
 struct QtArray children;memcpy(&children,(char *)data+24,sizeof(children));
 if(children.size<0||children.size>4096)return;
 for(long i=0;i<children.size;++i)qt_actions(children.data[i],result,depth+1);
}
static bool eden_ports(struct Actions *,int);
static int qt_action_pause(struct Actions *a) {
 bool (*enabled)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QAction9isEnabledEv");
 bool (*checked)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QAction9isCheckedEv");
 bool (*checkable)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QAction11isCheckableEv");
 bool (*visible)(const void *,const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QWidget11isVisibleToEPKS_");
 if(!a->pause||!enabled||!enabled(a->pause)||!checkable||!checked)return -1;
 if(getenv("BROOMM_MELONDS")&&(!a->stop||!enabled(a->stop)))return -1;
 if(a->loading&&visible&&visible(a->loading,qt_main))return -1;
 int actual=-1;
 if(checkable(a->pause))actual=checked(a->pause);
 else if(strstr(a->pause_text,"Continue")||strstr(a->pause_text,"Resume"))actual=1;
 else if(strstr(a->pause_text,"Pause"))actual=0;
 if(actual<0)return -1;
 static struct PauseTransition control=PAUSE_TRANSITION_INIT;
 if(!eden_ports(a,actual))return actual==0?0:-1;
 int command=session_pause_command(&control,atomic_load(&session_wanted),actual);
 if(command>=0) {
  void (*activate)(void *,int)=dlsym(RTLD_DEFAULT,"_ZN7QAction8activateENS_11ActionEventE");
  if(activate){activate(a->pause,0);record("QT_NATIVE_PAUSE requested=%d",command);}
 }
 return actual;
}
// Eden's own configuration dialog applies its native controller connections.
// Only our scoped call to the reviewed action is intercepted; user-opened
// dialogs execute normally. No OS window automation or guessed HID offsets.
static bool eden_configuring,eden_configured;
static unsigned eden_wanted,eden_applied=UINT32_MAX;
static void *qt_find_named(void *object,const char *name,int depth) {
 if(!object||depth>16)return NULL;
 struct QtString (*get_name)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK7QObject10objectNameEv");char actual[128]={0};
 if(get_name)qt_text(get_name(object),actual,sizeof(actual));if(!strcmp(name,actual))return object;
 void *data=*((void **)object+1);if(!data)return NULL;struct QtArray children;memcpy(&children,(char *)data+24,sizeof(children));
 if(children.size<0||children.size>4096)return NULL;
 for(long i=0;i<children.size;++i){void *found=qt_find_named(children.data[i],name,depth+1);if(found)return found;}return NULL;
}
int linux_dialog_exec(void *dialog) __asm__("_ZN7QDialog4execEv");
int linux_dialog_exec(void *dialog) {
 if(session_test){record("NATIVE_TEST_EXEC class=%s",qt_class(dialog));if(!strcmp(qt_class(dialog),"QMessageBox")){struct QtString (*get)(void *)=dlsym(RTLD_DEFAULT,"_ZNK11QMessageBox4textEv");char value[512]={0};if(get)qt_text(get(dialog),value,sizeof(value));record("NATIVE_TEST_EXEC_MESSAGE text=%s",value);}}
 if(eden_configuring&&!strcmp(qt_class(dialog),"ConfigureDialog")) {
  void (*set)(void *,bool)=dlsym(RTLD_DEFAULT,"_ZN15QAbstractButton10setCheckedEb");
  bool (*get)(const void *)=dlsym(RTLD_DEFAULT,"_ZNK15QAbstractButton9isCheckedEv");
  void *boxes[8]={0};if(!set||!get)return 0;
  for(int i=0;i<8;++i){char name[64];snprintf(name,sizeof(name),"checkboxPlayer%dConnected",i+1);boxes[i]=qt_find_named(dialog,name,0);if(!boxes[i]||strcmp(qt_class(boxes[i]),"QCheckBox"))return 0;}
  for(int i=7;i>=0;--i)set(boxes[i],false);
  for(int i=0;i<4;++i)if(eden_wanted&(1u<<i))set(boxes[i],true);
  for(int i=0;i<8;++i)if(get(boxes[i])!=(bool)((eden_wanted>>i)&1))return 0;
  eden_configured=true;return 1; // Caller executes ApplyConfiguration then Save.
 }
 int (*next)(void *)=dlsym(RTLD_NEXT,"_ZN7QDialog4execEv");
 bool owner=qt_start_dispatch();int result=next(dialog);if(owner)qt_stop_dispatch();return result;
}
static bool eden_ports(struct Actions *actions,int actual) {
 if(!getenv("BROOMM_EDEN"))return true;
 unsigned wanted=atomic_load(&connected_ports)&15;
 if(eden_applied==wanted)return true;
 if(actual!=1)return actual==0;
 if(!actions->configure)return false;
 void (*activate)(void *,int)=dlsym(RTLD_DEFAULT,"_ZN7QAction8activateENS_11ActionEventE");if(!activate)return false;
 eden_configuring=true;eden_configured=false;eden_wanted=wanted;
 activate(actions->configure,0);eden_configuring=false;
 if(eden_configured){eden_applied=wanted;atomic_store(&console_ports,(int)wanted);record("EDEN_NATIVE_PORTS applied=%u",wanted);return true;}
 record("EDEN_NATIVE_PORTS failed desired=%u",wanted);return false;
}
static _Atomic int sony_test_action;
static int dolphin_pause(void) {
 if(!core_system_fn||!core_state_fn||!core_set_state_fn)return -1;
 void *system=((void *(*)(void))core_system_fn)();
 int state=((int(*)(void *))core_state_fn)(system);
 static int previous=-99;if(state!=previous){record("DOLPHIN_NATIVE_STATE value=%d",state);previous=state;}
 if(state!=1&&state!=2)return -1;
 static struct PauseTransition control=PAUSE_TRANSITION_INIT;
 int command=session_pause_command(&control,atomic_load(&session_wanted),state==1);
 if(command>=0)((void(*)(void *,int,bool,bool))core_set_state_fn)(system,command?1:2,true,false);
 state=((int(*)(void *))core_state_fn)(system);
 // Preserve native console sockets separately from four stable SDL sources.
 const void *(*info)(int)=symbol("_ZN6Config18GetInfoForSIDeviceEi");
 void (*set)(int,const void *,const int *)=symbol("_ZN6Config3SetINS_4InfoIN15SerialInterface9SIDevicesEEES3_EEvNS_9LayerTypeERKT_RKT0_");
 int (*get)(const void *)=symbol("_ZN6Config11GetUncachedIN15SerialInterface9SIDevicesEEET_RKNS_4InfoIS3_EE");
 if(state==1&&info&&set&&get)for(int p=0;p<4;++p){const void *key=info(p);int wanted=!dolphin_wii&&(atomic_load(&connected_ports)&(1u<<p))?6:0;if(get(key)!=wanted)set(6,key,&wanted);}
 if(state==1&&!dolphin_wii){
  void *(*get_si)(void *)=symbol("_ZNK4Core6System18GetSerialInterfaceEv");
  int (*get_type)(void *,int)=symbol("_ZNK15SerialInterface22SerialInterfaceManager13GetDeviceTypeEi");
  if(get_si&&get_type){unsigned mask=0;void *si=get_si(system);for(int p=0;p<4;++p)if(get_type(si,p)==6)mask|=1u<<p;atomic_store(&console_ports,(int)mask);}
 }
 wii_tick(state);return state==1?1:state==2?0:-1;
}
static int rpcs_pause(void) {
 if(!rpcs_status||!qt_main)return -1;
 int state=(int)__atomic_load_n(rpcs_status,__ATOMIC_ACQUIRE);
 static int previous=-99;if(state!=previous){record("RPCS3_NATIVE_STATE value=%d",state);previous=state;}
 if(state!=3&&state!=4)return -1;
 static struct PauseTransition control=PAUSE_TRANSITION_INIT;
 int command=session_pause_command(&control,atomic_load(&session_wanted),state==4);
 void (*toggle)(void *)=symbol("_ZN11main_window13OnPlayOrPauseEv");
 if(command>=0&&toggle)toggle(qt_main);
 state=(int)__atomic_load_n(rpcs_status,__ATOMIC_ACQUIRE);return state==4?1:state==3?0:-1;
}
static void psp_window_tick(void);
static void session_ui(void *unused) {
 (void)unused;if(!atomic_load(&linux_active))return;
 if(getenv("BROOMM_PPSSPP")){psp_window_tick();return;}
 void **app=dlsym(RTLD_DEFAULT,"_ZN16QCoreApplication4selfE");
 struct QtArray (*top)(void)=dlsym(RTLD_DEFAULT,"_ZN12QApplication15topLevelWidgetsEv");
 if(session_test){static bool seen;if(!seen){seen=true;record("NATIVE_TEST_QT app_symbol=%d app_live=%d widgets_api=%d",app!=NULL,app&&*app!=NULL,top!=NULL);}}
 if(!app||!*app||!top)return;
 struct QtArray widgets=top();qt_main=NULL;
 if(widgets.size>=0&&widgets.size<256)for(long i=0;i<widgets.size;++i) {
  const char *name=qt_class(widgets.data[i]);
  if(session_test){static char classes[2048];if(name[0]&&!strstr(classes,name)&&strlen(classes)+strlen(name)+2<sizeof(classes)){strcat(classes,name);strcat(classes,";");record("NATIVE_TEST_WIDGET class=%s",name);}}
  if(session_test&&!strcmp(name,"QMessageBox")){
   struct QtString (*text)(void *)=dlsym(RTLD_DEFAULT,"_ZNK11QMessageBox4textEv");static char last[512];char value[512]={0};if(text)qt_text(text(widgets.data[i]),value,sizeof(value));if(strcmp(last,value)){snprintf(last,sizeof(last),"%s",value);record("NATIVE_TEST_DIALOG text=%s",value);}
  }
  if(!strcmp(name,"MainWindow")||!strcmp(name,"GMainWindow")||!strcmp(name,"main_window"))qt_main=widgets.data[i];
 }
 qt_release(widgets.allocation,sizeof(void *),_Alignof(void *));
 if(!qt_main)return;
 static bool backend_logged;if(!backend_logged){backend_logged=true;struct QtString (*platform)(void)=dlsym(RTLD_DEFAULT,"_ZN15QGuiApplication12platformNameEv");char backend[64]={0};if(platform)qt_text(platform(),backend,sizeof(backend));record("QT_MAIN_WINDOW class=%s backend=%s",qt_class(qt_main),backend);}
 if(atomic_load(&session_quit)) {
  atomic_store(&session_finishing,true);
  if(atomic_load(&session_worker_stopped)) {
   bool (*close_window)(void *)=dlsym(RTLD_DEFAULT,"_ZN7QWidget5closeEv");
   void (*quit)(void)=dlsym(RTLD_DEFAULT,"_ZN16QCoreApplication4quitEv");
   if(close_window&&close_window(qt_main)&&quit)quit();
  }
  return;
 }
 static void *traced;trace_actions=session_test&&traced!=qt_main;traced=qt_main;
 struct Actions actions={0};int actual=-1;
 if(core_system_fn)actual=dolphin_pause();
 else if(rpcs_status)actual=rpcs_pause();
 else if(getenv("BROOMM_PLAYSTATION")){qt_actions(qt_main,&actions,0);actual=qt_action_pause(&actions);}
 else {qt_actions(qt_main,&actions,0);actual=qt_action_pause(&actions);}
 if(session_test&&actual>=0) {
  int action=atomic_exchange(getenv("BROOMM_PLAYSTATION")?&sony_test_action:&test_native_pause_action,0);
  int wanted=action==4?1:action==5?0:-1;
  if(wanted>=0&&actual!=wanted) {
   if(core_system_fn)((void(*)(void *,int,bool,bool))core_set_state_fn)(((void *(*)(void))core_system_fn)(),wanted?1:2,true,false);
   else if(rpcs_status){void (*toggle)(void *)=symbol("_ZN11main_window13OnPlayOrPauseEv");if(toggle)toggle(qt_main);}
   else {void (*activate)(void *,int)=dlsym(RTLD_DEFAULT,"_ZN7QAction8activateENS_11ActionEventE");if(activate&&actions.pause)activate(actions.pause,0);}
   record("NATIVE_TEST_PAUSE requested=%d",wanted);
  }
 }
 atomic_store(&session_paused,actual);
 if(actual>=0){had_game=true;struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);last_game=t.tv_sec+t.tv_nsec/1e9;}
 else if(had_game){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);if(t.tv_sec+t.tv_nsec/1e9-last_game>1.0)atomic_store(&session_quit,true);}
 void (*visible)(void *,bool)=dlsym(RTLD_DEFAULT,"_ZN7QWidget10setVisibleEb");
 if(visible&&actual>=0){bool hide=hide_game_window();if(hide!=ui_hidden){visible(qt_main,!hide);ui_hidden=hide;}
  bool (*is_visible)(const void *,const void *)=symbol("_ZNK7QWidget11isVisibleToEPKS_");
  atomic_store(&game_window_visible,!hide&&is_visible&&is_visible(qt_main,NULL));}
 atomic_store(&app_active,actual>=0);
}
static _Thread_local bool in_ui;
static void linux_ui_tick(void) {
 if(!atomic_load(&linux_active)||in_ui||syscall(SYS_gettid)!=getpid())return;
 static uint64_t previous;struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);uint64_t tick=(uint64_t)now.tv_sec*1000000000u+now.tv_nsec;
 if(tick-previous<16000000u)return;previous=tick;in_ui=true;
 struct UiWork work[128];int count;pthread_mutex_lock(&dispatch_lock);count=ui_work_count;memcpy(work,ui_work,(size_t)count*sizeof(*work));ui_work_count=0;pthread_mutex_unlock(&dispatch_lock);
 for(int i=0;i<count;++i)work[i].callback(work[i].context);
 session_ui(NULL);in_ui=false;
}
#include "linux_windows.inc"
