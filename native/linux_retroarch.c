// Original Broomm SDL 3.4 interop, Linux x64. No emulator implementation code.
// Runs inside the reviewed RetroArch process. Dart owns session/save policy.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <linux/landlock.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include "ownership.inc"

struct VirtualDesc {
    uint32_t version;
    uint16_t type,padding,vendor,product,axes,buttons,balls,hats,touchpads,sensors,padding2[2];
    uint32_t button_mask,axis_mask;
    const char *name;
    void *touchpad_descs,*sensor_descs,*userdata;
    void (*update)(void *),(*player)(void *,int);
    bool (*rumble)(void *,uint16_t,uint16_t),(*rumble_triggers)(void *,uint16_t,uint16_t);
    bool (*led)(void *,uint8_t,uint8_t,uint8_t),(*effect)(void *,const void *,int);
    bool (*enable_sensors)(void *,bool);
    void (*cleanup)(void *);
};
_Static_assert(sizeof(struct VirtualDesc)==136,"SDL 3.4 virtual descriptor ABI");
typedef bool (*Watch)(void *,void *);
static uint32_t *(*raw_ids)(int *),*(*raw_pads)(int *);
static void *(*raw_open_joy)(uint32_t),*(*raw_open_pad)(uint32_t);
static void (*raw_close_pad)(void *),(*raw_close_joy)(void *),(*sdl_free)(void *);
static void *(*sdl_calloc)(size_t,size_t);
static uint32_t (*was_init)(uint32_t),(*attach)(const struct VirtualDesc *);
static bool (*detach)(uint32_t),(*is_pad)(uint32_t),(*button)(void *,int),(*set_button)(void *,int,bool);
static int16_t (*axis)(void *,int);
static bool (*set_axis)(void *,int,int16_t);
static void (*update)(void),(*lock_joy)(void),(*unlock_joy)(void);
static const char *(*pad_name)(void *);
static int (*pad_type)(void *);
static uint32_t (*joystick_id)(void *);
static void *(*pad_joystick)(void *);
static int (*pad_player)(void *),(*joy_player)(void *);
static void (*quit_sdl)(void),(*quit_subsystem)(uint32_t);
static bool (*poll_event)(void *),(*wait_event)(void *),(*wait_timeout)(void *,int);
static bool (*add_watch)(Watch,void *);
static void (*remove_watch)(Watch,void *);
static void *(*create_window)(const char *,int,int,uint64_t);
static bool (*show_window)(void *),(*hide_window)(void *),(*raise_window)(void *),(*swap_window)(void *);
static void (*destroy_window)(void *),(*pump_events)(void);
static uint64_t (*window_flags)(void *);
static const char *(*video_driver)(void);
static void *main_window;
static pthread_t window_thread;
static _Atomic bool ui_gate=true,window_control,window_visible;
static _Atomic bool orphaned,show_requested;
static pthread_once_t api_once=PTHREAD_ONCE_INIT;
static bool api_valid,creating,initialized,test_mode,active_session,worker_started;
static _Atomic bool finishing,worker_stopped;
static _Atomic uint32_t ports[4];
static void *port_joy[4],*test_joy[2],*test_port_pad[4];
static uint32_t test_ids[2];
static pthread_t worker_thread;
static pthread_mutex_t log_mutex=PTHREAD_MUTEX_INITIALIZER;
static const char *log_path;
#include "linux_write_policy.h"

static void bridge_log(int line,const char *severity,const char *format,...) {
    pthread_mutex_lock(&log_mutex);
    static bool log_failed;
    struct stat statbuf;
    if(log_path&&stat(log_path,&statbuf)==0&&statbuf.st_size>=1024*1024) {
        for(int i=9;i>=1;--i) {
            char from[4096],to[4096];snprintf(to,sizeof(to),"%s.%d",log_path,i);
            if(i==9)unlink(to);
            if(i==1)snprintf(from,sizeof(from),"%s",log_path);
            else snprintf(from,sizeof(from),"%s.%d",log_path,i-1);
            rename(from,to);
        }
    }
    int fd=log_path?open(log_path,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_CLOEXEC,0600):-1;
    FILE *out=fd>=0?fdopen(fd,"a"):NULL;
    if(out) {
        struct timespec now;struct tm utc;char stamp[32];clock_gettime(CLOCK_REALTIME,&now);
        gmtime_r(&now.tv_sec,&utc);strftime(stamp,sizeof(stamp),"%Y-%m-%dT%H:%M:%S",&utc);
        fprintf(out,"%s.%03ldZ %s linux_retroarch.c:%d pid=%d ",stamp,now.tv_nsec/1000000,severity,line,getpid());
        if(log_failed){fputs("native logging resumed\n",out);log_failed=false;
            fprintf(out,"%s.%03ldZ %s linux_retroarch.c:%d pid=%d ",stamp,now.tv_nsec/1000000,severity,line,getpid());}
        va_list args;va_start(args,format);vfprintf(out,format,args);va_end(args);fputc('\n',out);fclose(out);
    } else if(!log_failed){fprintf(stderr,"Broomm: native controller log is unavailable; retrying\n");log_failed=true;}
    pthread_mutex_unlock(&log_mutex);
}
#define record(...) bridge_log(__LINE__,"info",__VA_ARGS__)
#define record_error(...) bridge_log(__LINE__,"error",__VA_ARGS__)

static void resolve_api(void) {
#define API(field,name) *(void **)(&field)=dlsym(RTLD_NEXT,name)
    API(raw_ids,"SDL_GetJoysticks");API(raw_pads,"SDL_GetGamepads");
    API(raw_open_joy,"SDL_OpenJoystick");API(raw_open_pad,"SDL_OpenGamepad");
    API(raw_close_pad,"SDL_CloseGamepad");API(raw_close_joy,"SDL_CloseJoystick");
    API(sdl_free,"SDL_free");API(sdl_calloc,"SDL_calloc");API(was_init,"SDL_WasInit");
    API(attach,"SDL_AttachVirtualJoystick");API(detach,"SDL_DetachVirtualJoystick");
    API(is_pad,"SDL_IsGamepad");API(button,"SDL_GetGamepadButton");API(axis,"SDL_GetGamepadAxis");
    API(set_button,"SDL_SetJoystickVirtualButton");API(set_axis,"SDL_SetJoystickVirtualAxis");
    API(update,"SDL_UpdateJoysticks");API(lock_joy,"SDL_LockJoysticks");API(unlock_joy,"SDL_UnlockJoysticks");
    API(pad_name,"SDL_GetGamepadName");API(pad_type,"SDL_GetGamepadType");
    API(joystick_id,"SDL_GetJoystickID");API(pad_joystick,"SDL_GetGamepadJoystick");
    API(pad_player,"SDL_GetGamepadPlayerIndex");API(joy_player,"SDL_GetJoystickPlayerIndex");
    API(quit_sdl,"SDL_Quit");API(quit_subsystem,"SDL_QuitSubSystem");
    API(poll_event,"SDL_PollEvent");API(wait_event,"SDL_WaitEvent");API(wait_timeout,"SDL_WaitEventTimeout");
    API(add_watch,"SDL_AddEventWatch");API(remove_watch,"SDL_RemoveEventWatch");
    API(create_window,"SDL_CreateWindow");API(show_window,"SDL_ShowWindow");API(hide_window,"SDL_HideWindow");
    API(raise_window,"SDL_RaiseWindow");API(destroy_window,"SDL_DestroyWindow");API(pump_events,"SDL_PumpEvents");
    API(swap_window,"SDL_GL_SwapWindow");API(window_flags,"SDL_GetWindowFlags");API(video_driver,"SDL_GetCurrentVideoDriver");
    int (*version)(void);API(version,"SDL_GetVersion");
    api_valid=version&&version()==3004000&&raw_ids&&raw_pads&&raw_open_joy&&raw_open_pad&&raw_close_pad&&raw_close_joy&&
        sdl_free&&sdl_calloc&&was_init&&attach&&detach&&is_pad&&button&&axis&&set_button&&set_axis&&update&&
        lock_joy&&unlock_joy&&pad_name&&pad_type&&joystick_id&&pad_joystick&&pad_player&&joy_player&&
        quit_sdl&&quit_subsystem&&poll_event&&wait_event&&wait_timeout&&add_watch&&remove_watch&&
        create_window&&show_window&&hide_window&&raise_window&&destroy_window&&pump_events&&swap_window&&window_flags&&video_driver;
#undef API
}
static bool logical(uint32_t id) {
    for(int i=0;i<4;++i)if(id&&id==atomic_load(&ports[i]))return true;
    return false;
}
static void create_ports(void) { // SDL joystick lock held; SDL uses a recursive lock.
    if(initialized||creating||!api_valid||!(was_init(0)&0x200))return;
    creating=true;
    if(test_mode&&getenv("BROOMM_TEST_PRECONNECTED"))for(int i=0;i<2;++i) {
        struct VirtualDesc d={.version=sizeof(d),.type=1,.vendor=0x1209,.product=(uint16_t)(0xc001+i),
            .axes=6,.buttons=21,.hats=1,.button_mask=0x1fffff,.axis_mask=0x3f,
            .name=i?"Broomm test source B":"Broomm test source A"};
        test_ids[i]=attach(&d);test_joy[i]=raw_open_joy(test_ids[i]);
    }
    initialized=true;
    for(int i=0;i<4;++i) {
        struct VirtualDesc d={.version=sizeof(d),.type=1,.vendor=0x1209,.product=(uint16_t)(0xb001+i),
            .axes=6,.buttons=21,.hats=1,.button_mask=0x1fffff,.axis_mask=0x3f,
            .name=(const char *[]){"Broomm Player 1","Broomm Player 2","Broomm Player 3","Broomm Player 4"}[i]};
        uint32_t id=attach(&d);atomic_store(&ports[i],id);port_joy[i]=raw_open_joy(id);
        if(test_mode&&id)test_port_pad[i]=raw_open_pad(id);
        if(!id||!port_joy[i])initialized=false;
    }
    creating=false;
}
static uint32_t *logical_ids(int *count,bool gamepads) {
    pthread_once(&api_once,resolve_api);
    if(!api_valid){if(count)*count=0;return NULL;}
    if(!active_session)return gamepads?raw_pads(count):raw_ids(count);
    lock_joy();create_ports();uint32_t *ids=sdl_calloc(5,sizeof(uint32_t));int n=0;
    if(ids)for(int i=0;i<4;++i)if(atomic_load(&ports[i]))ids[n++]=atomic_load(&ports[i]);
    unlock_joy();if(count)*count=n;return ids;
}
uint32_t *SDL_GetJoysticks(int *count){return logical_ids(count,false);}
uint32_t *SDL_GetGamepads(int *count){return logical_ids(count,true);}
int SDL_GetGamepadPlayerIndex(void *pad) {
    pthread_once(&api_once,resolve_api);if(!pad_player||!pad_joystick||!joystick_id)return -1;
    if(active_session){uint32_t id=joystick_id(pad_joystick(pad));for(int p=0;p<4;++p)if(id&&id==atomic_load(&ports[p]))return p;}
    return pad_player(pad);
}
int SDL_GetJoystickPlayerIndex(void *joy) {
    pthread_once(&api_once,resolve_api);if(!joy_player||!joystick_id)return -1;
    if(active_session){uint32_t id=joystick_id(joy);for(int p=0;p<4;++p)if(id&&id==atomic_load(&ports[p]))return p;}
    return joy_player(joy);
}

static bool allowed_event(const void *event) {
    if(!event||!active_session)return true;
    uint32_t type,which;memcpy(&type,event,4);
    if(type<0x600||type>0x65f)return true;
    memcpy(&which,(const char *)event+16,4);return logical(which);
}
static void apply_window_gate(void) {
    if(!active_session||!main_window||!atomic_load(&window_control)||atomic_load(&finishing)||
       !pthread_equal(pthread_self(),window_thread))return;
    bool requested=atomic_exchange(&show_requested,false);
    bool visible=(window_flags(main_window)&8u)==0,wanted=atomic_load(&orphaned)||!atomic_load(&ui_gate);
    if(visible!=wanted) {
        bool ok=wanted?show_window(main_window):hide_window(main_window);
        if(ok&&wanted)raise_window(main_window);
        if(ok)record("window visible=%d backend=%s",wanted,video_driver()?video_driver():"unknown");
    }
    if(requested&&wanted)raise_window(main_window);
    atomic_store(&window_visible,(window_flags(main_window)&8u)==0);
}
void *SDL_CreateWindow(const char *title,int width,int height,uint64_t flags) {
    pthread_once(&api_once,resolve_api);if(!create_window)return NULL;
    void *window=create_window(title,width,height,flags);
    if(active_session&&window){main_window=window;window_thread=pthread_self();
        record("renderer window created backend=%s",video_driver()?video_driver():"unknown");apply_window_gate();}
    return window;
}
bool SDL_ShowWindow(void *window) {
    pthread_once(&api_once,resolve_api);if(!show_window)return false;
    if(active_session&&window==main_window&&atomic_load(&window_control)&&atomic_load(&ui_gate))return hide_window(window);
    return show_window(window);
}
void SDL_DestroyWindow(void *window) {
    pthread_once(&api_once,resolve_api);if(window==main_window){main_window=NULL;atomic_store(&window_visible,false);}
    if(destroy_window)destroy_window(window);
}
void SDL_PumpEvents(void) {pthread_once(&api_once,resolve_api);if(pump_events)pump_events();apply_window_gate();}
bool SDL_GL_SwapWindow(void *window) {pthread_once(&api_once,resolve_api);apply_window_gate();return swap_window&&swap_window(window);}
bool SDL_PollEvent(void *event) {
    pthread_once(&api_once,resolve_api);if(!poll_event)return false;
    apply_window_gate();
    while(poll_event(event))if(allowed_event(event))return true;
    return false;
}
bool SDL_WaitEventTimeout(void *event,int timeout) {
    pthread_once(&api_once,resolve_api);if(!wait_timeout)return false;
    apply_window_gate();
    struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
    int64_t end=(int64_t)now.tv_sec*1000+now.tv_nsec/1000000+(timeout<0?0:timeout);
    int remaining=timeout;
    while(wait_timeout(event,remaining)) {
        if(allowed_event(event))return true;
        if(timeout>=0){clock_gettime(CLOCK_MONOTONIC,&now);remaining=(int)(end-((int64_t)now.tv_sec*1000+now.tv_nsec/1000000));if(remaining<=0)return false;}
    }
    return false;
}
bool SDL_WaitEvent(void *event){pthread_once(&api_once,resolve_api);return active_session?SDL_WaitEventTimeout(event,-1):wait_event&&wait_event(event);}
struct WatchEntry {Watch callback;void *data;bool used;};
static struct WatchEntry watches[32];
static pthread_mutex_t watch_mutex=PTHREAD_MUTEX_INITIALIZER;
static bool watch_thunk(void *context,void *event) {
    struct WatchEntry *entry=context;
    return !allowed_event(event)||entry->callback(entry->data,event);
}
bool SDL_AddEventWatch(Watch callback,void *data) {
    pthread_once(&api_once,resolve_api);if(!add_watch)return false;
    if(!active_session)return add_watch(callback,data);
    pthread_mutex_lock(&watch_mutex);struct WatchEntry *entry=NULL;
    for(int i=0;i<32;++i)if(!watches[i].used){entry=&watches[i];*entry=(struct WatchEntry){callback,data,true};break;}
    pthread_mutex_unlock(&watch_mutex);
    if(!entry){record_error("event-watch capacity reached");return false;}
    return add_watch(watch_thunk,entry);
}
void SDL_RemoveEventWatch(Watch callback,void *data) {
    pthread_once(&api_once,resolve_api);if(!remove_watch)return;
    if(!active_session){remove_watch(callback,data);return;}
    pthread_mutex_lock(&watch_mutex);struct WatchEntry *entry=NULL;
    for(int i=0;i<32;++i)if(watches[i].used&&watches[i].callback==callback&&watches[i].data==data){entry=&watches[i];break;}
    pthread_mutex_unlock(&watch_mutex);
    if(entry)remove_watch(watch_thunk,entry); // Keep callback storage until process exit.
}

struct Source {uint32_t id,buttons;void *pad;char name[256];int16_t axes[6];int family;bool chord;};
static struct Source sources[32];static int source_count;
static bool discovery_ready;
static uint32_t routes[4]={UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX};
static int swaps[4];static bool blocked=true,pending;
static unsigned long long revision,sample,serial=1,release_serial;
static const char *request="initial";
static void request_gate(const char *kind) {
    if(blocked&&!strcmp(request,kind))return;
    blocked=true;pending=false;request=kind;++serial;record("gate request=%s serial=%llu",kind,serial);
}
static struct Source *source_for(uint32_t id){for(int i=0;i<source_count;++i)if(sources[i].id==id)return &sources[i];return NULL;}
static void discover(void) {
    int n=0;uint32_t *ids=raw_ids(&n);
    if(!ids||n<0||n>4096){sdl_free(ids);discovery_ready=false;request_gate("input-error");return;}
    discovery_ready=true;
    for(int i=source_count-1;i>=0;--i) {
        bool found=false;for(int j=0;j<n;++j)if(ids[j]==sources[i].id)found=true;
        if(found)continue;
        for(int p=0;p<4;++p)if(routes[p]==sources[i].id)request_gate("disconnect");
        raw_close_pad(sources[i].pad);sources[i]=sources[--source_count];
    }
    for(int i=0;i<n&&source_count<32;++i) {
        if(logical(ids[i])||source_for(ids[i])||!is_pad(ids[i]))continue;
        void *pad=raw_open_pad(ids[i]);if(!pad){discovery_ready=false;request_gate("input-error");continue;}
        struct Source *s=&sources[source_count++];*s=(struct Source){.id=ids[i],.pad=pad};
        const char *name=pad_name(pad);snprintf(s->name,sizeof(s->name),"%s",name?name:"Gamepad");
        int type=pad_type(pad);s->family=(type==2||type==3)?1:(type>=4&&type<=6)?2:(type>=7&&type<=10)?3:type==11?4:0;
        if(test_mode&&(ids[i]==test_ids[0]||ids[i]==test_ids[1]))s->family=1;
        record("source connected id=%u family=%d",s->id,s->family);
    }
    sdl_free(ids);
}
static void read_command(void) {
    const char *path=getenv("BROOMM_SESSION_COMMAND");FILE *in=path?fopen(path,"r"):NULL;if(!in)return;
    unsigned long long next;unsigned int ids[4];int active,pause,swap[4],quit,modes[4],gyro[4];
    int count=fscanf(in,"%llu %d %d %u %u %u %u %d %d %d %d %d %d %d %d %d %d %d %d %d",
        &next,&active,&pause,&ids[0],&ids[1],&ids[2],&ids[3],&swap[0],&swap[1],&swap[2],&swap[3],&quit,
        &modes[0],&modes[1],&modes[2],&modes[3],&gyro[0],&gyro[1],&gyro[2],&gyro[3]);fclose(in);
    if(count!=20||next<=revision||(active!=0&&active!=1)||(pause!=0&&pause!=1)||(quit!=0&&quit!=1))return;
    bool valid=true;
    for(int p=0;p<4;++p) {
        if((swap[p]!=0&&swap[p]!=1)||(gyro[p]!=0&&gyro[p]!=1)||modes[p]<0||modes[p]>3)return;
        for(int q=0;q<p;++q)if(ids[p]!=UINT32_MAX&&ids[p]==ids[q])return;
        if(ids[p]!=UINT32_MAX&&!source_for(ids[p]))valid=false;
    }
    revision=next;memcpy(routes,ids,sizeof(routes));memcpy(swaps,swap,sizeof(swaps));
    pending=active&&valid&&blocked;blocked=!active||!valid||pending;
    if(!valid)request_gate("disconnect");
    if(quit)atomic_store(&finishing,true); // Dart sends the verified native QUIT command.
    record("command revision=%llu active=%d valid=%d",revision,active,valid);
}
static void fixture_input(void) {
    if(!test_mode)return;
    const char *path=getenv("BROOMM_TEST_INPUT");FILE *in=path?fopen(path,"r"):NULL;
    unsigned int bits[2]={0,0},present=3,triggers=0;
    if(in){(void)fscanf(in,"%u %u %u %u",&bits[0],&bits[1],&present,&triggers);fclose(in);}
    for(int i=0;i<2;++i)if(test_joy[i]) {
        if(!(present&(1u<<i))){detach(test_ids[i]);raw_close_joy(test_joy[i]);test_joy[i]=NULL;continue;}
        for(int b=0;b<21;++b)set_button(test_joy[i],b,(bits[i]&(1u<<b))!=0);
        for(int a=0;a<6;++a)set_axis(test_joy[i],a,a>=4?(i==0&&(triggers&(1u<<(a-4)))?32767:-32768):0);
    }
}
static void json_text(FILE *out,const char *text) {
    fputc('"',out);for(const unsigned char *p=(const void *)text;*p;++p) {
        if(*p=='"'||*p=='\\'){fputc('\\',out);fputc(*p,out);}
        else if(*p<32)fprintf(out,"\\u%04x",*p);else fputc(*p,out);
    }fputc('"',out);
}
static void write_status(void) {
    const char *path=getenv("BROOMM_SESSION_STATUS");if(!path)return;
    char temp[4096];int n=snprintf(temp,sizeof(temp),"%s.tmp-%d",path,getpid());if(n<0||(size_t)n>=sizeof(temp))return;
    int fd=open(temp,O_CREAT|O_WRONLY|O_TRUNC|O_NOFOLLOW|O_CLOEXEC,0600);FILE *out=fd>=0?fdopen(fd,"w"):NULL;
    if(!out){record_error("status unavailable errno=%d",errno);return;}
    unsigned mask=0;for(int p=0;p<4;++p)if(source_for(routes[p]))mask|=1u<<p;
    fprintf(out,"{\"protocol\":4,\"pid\":%d,\"sample\":%llu,\"ack\":%llu,\"requestSerial\":%llu,\"request\":\"%s\",\"blocked\":%s,\"paused\":-1,\"pauseReleaseSerial\":%llu,\"window\":[0,0,0,0],\"connectedPorts\":%u,\"inputReady\":%s,\"devices\":[",
        getpid(),++sample,revision,serial,request,blocked?"true":"false",release_serial,mask,initialized&&discovery_ready?"true":"false");
    for(int i=0;i<source_count;++i) {
        struct Source *s=&sources[i];if(i)fputc(',',out);
        fprintf(out,"{\"id\":%u,\"name\":",s->id);json_text(out,s->name);
        fprintf(out,",\"buttons\":%u,\"x\":%d,\"y\":%d,\"rx\":%d,\"ry\":%d,\"lt\":%d,\"rt\":%d,\"family\":%d,\"sensors\":0,\"sensorReady\":0}",s->buttons,s->axes[0],s->axes[1],s->axes[2],s->axes[3],s->axes[4],s->axes[5],s->family);
    }
    fputc(']',out);
    fprintf(out,",\"gameWindowVisible\":%s",atomic_load(&window_visible)?"true":"false");
    if(test_mode) {
        fprintf(out,",\"testSourceIds\":[%u,%u],\"testLogicalTriggers\":[",test_ids[0],test_ids[1]);
        for(int i=0;i<4;++i)fprintf(out,"%s[%d,%d]",i?",":"",test_port_pad[i]?axis(test_port_pad[i],4):-1,test_port_pad[i]?axis(test_port_pad[i],5):-1);
        fputc(']',out);
    }
    fputs("}\n",out);if(fclose(out)!=0||rename(temp,path)!=0)record_error("status publication failed errno=%d",errno);
}
static void *worker(void *unused) {
    (void)unused;pthread_once(&api_once,resolve_api);
    if(!api_valid){record_error("required SDL 3.4 API unavailable");atomic_store(&worker_stopped,true);return NULL;}
    const char *launcher=getenv("BROOMM_LAUNCHER_PID");
    pid_t owner=launcher?(pid_t)strtol(launcher,NULL,10):getppid();
    if(owner<=1){record_error("invalid launcher process identity");atomic_store(&worker_stopped,true);return NULL;}
    for(unsigned tick=0;!atomic_load(&finishing);++tick) {
        if(!(was_init(0)&0x200)){usleep(10000);continue;}
        lock_joy();create_ports();fixture_input();update();
        if(tick%16==0)discover();
        for(int i=0;i<source_count;++i) {
            struct Source *s=&sources[i];s->buttons=0;
            for(int b=0;b<21;++b)if(button(s->pad,b))s->buttons|=1u<<b;
            for(int a=0;a<6;++a)s->axes[a]=axis(s->pad,a);
            bool assigned=false;for(int p=0;p<4;++p)if(routes[p]==s->id)assigned=true;
            bool chord=(s->buttons&(1u<<4))&&(s->buttons&(1u<<8));
            if(assigned&&!blocked&&chord&&!s->chord)request_gate("menu");
            s->chord=chord;
        }
        if(tick%4==0)read_command();
        if(getppid()!=owner){atomic_store(&orphaned,true);if(!blocked)request_gate("launcher-exit");}
        if(pending) {
            bool released=true;for(int p=0;p<4;++p){struct Source *s=source_for(routes[p]);if(s&&s->buttons)released=false;}
            if(released){pending=false;blocked=false;++release_serial;}
        }
        atomic_store(&ui_gate,blocked);
        if(!atomic_load(&window_control)&&tick%4==0) {
            const char *command=getenv("BROOMM_SESSION_COMMAND");
            const char *slash=command?strrchr(command,'/'):NULL;
            if(slash){char path[4096];snprintf(path,sizeof(path),"%.*s/bridge-window-ready.txt",(int)(slash-command),command);
                int fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);char ready=0;
                if(fd>=0){if(read(fd,&ready,1)==1&&ready=='1')atomic_store(&window_control,true);close(fd);}}
        }
        if(atomic_load(&orphaned)&&tick%4==0) {
            const char *root=getenv("BROOMM_LINUX_PROFILE");
            if(root){char path[4096],text[64]={0};snprintf(path,sizeof(path),"%s/bridge-recovery-show.txt",root);
                int fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
                if(fd>=0){ssize_t n=read(fd,text,sizeof(text)-1);close(fd);if(n>0){
                    static unsigned long long previous;unsigned long long value=strtoull(text,NULL,10);
                    if(value&&value!=previous){previous=value;atomic_store(&show_requested,true);}
                }}}
        }
        for(int p=0;p<4;++p)if(port_joy[p]) {
            struct Source *s=source_for(routes[p]);
            for(int b=0;b<21;++b) {
                int input=swaps[p]&&b<4?b^1:b;
                set_button(port_joy[p],b,s&&!blocked&&(s->buttons&(1u<<input)));
            }
            for(int a=0;a<6;++a) {
                int value=s&&!blocked?s->axes[a]:0;
                // Gamepad triggers are 0..32767; virtual joystick triggers
                // start at -32768. Preserve neutral instead of half-pressing.
                if(a>=4)value=value*2-32768;
                set_axis(port_joy[p],a,(int16_t)value);
            }
        }
        update();if(tick%4==0)write_status();unlock_joy();usleep(8000);
    }
    record("sampling stopped before native SDL teardown");atomic_store(&worker_stopped,true);return NULL;
}
static void stop_sampling(void) {
    if(!active_session||!worker_started)return;
    atomic_store(&finishing,true);
    for(int i=0;i<5000&&!atomic_load(&worker_stopped);++i)usleep(1000);
    if(!atomic_load(&worker_stopped)) {record_error("controller worker did not stop; native teardown refused");_exit(74);}
}
void SDL_Quit(void) {pthread_once(&api_once,resolve_api);stop_sampling();if(quit_sdl)quit_sdl();}
void SDL_QuitSubSystem(uint32_t flags) {
    pthread_once(&api_once,resolve_api);if(flags&0x200)stop_sampling();if(quit_subsystem)quit_subsystem(flags);
}
__attribute__((constructor)) static void start(void) {
    bool session=getenv("BROOMM_SESSION")&&getenv("BROOMM_RETROARCH");
    bool configuration=getenv("BROOMM_CONFIGURATION_ROOT")!=NULL;
    if(!session&&!configuration)return;
    const char *expected=getenv("BROOMM_SESSION_EXECUTABLE");char executable[4096];
    ssize_t length=readlink("/proc/self/exe",executable,sizeof(executable)-1);
    if(!expected||length<0)return;
    executable[length]=0;if(strcmp(executable,expected))return; // Do not inject workflow behavior into helpers.
    log_path=getenv("BROOMM_PROBE_LOG");test_mode=getenv("BROOMM_SESSION_TEST")!=NULL;
    if(configuration) {
        const char *path=getenv("BROOMM_CONFIGURATION_SESSION_LOCK");
        int fd=path?open(path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600):-1;
        struct flock lock={.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
        if(fd<0||fcntl(fd,F_SETLK,&lock)<0)_exit(73);
        // Intentionally retain fd: the independent configuration process owns it.
    }
    acquire_session_writer();
    const char *root=getenv("BROOMM_CONFIGURATION_ROOT");
    if(!root)root=getenv("BROOMM_LINUX_PROFILE");
    if(!private_writes(root)){record_error("private write protection unavailable errno=%d",errno);_exit(73);}
    record("Linux private write protection active");
    if(configuration)return;
    active_session=true;record("Linux RetroArch bridge loaded");
    if(pthread_create(&worker_thread,NULL,worker,NULL)!=0){record_error("could not start controller worker");_exit(73);}
    worker_started=true;pthread_detach(worker_thread);
}
