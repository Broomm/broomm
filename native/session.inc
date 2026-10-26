// Broomm macOS bridge. Compiled into the owning emulator's architecture.
// IPC is private files: atomic snapshots, monotonic command revisions. Dart owns
// pairing decisions; this bridge owns same-runtime SDL sampling and virtual ports.
#include <sys/stat.h>
#include <signal.h>

struct Source { uint32_t id; void *handle; char name[256]; uint32_t buttons; int16_t axes[6]; int family;
    int sensors,sensor_ready,sensor_owned; float motion[2][3]; uint64_t motion_time;
    bool gyro_chord_ready,rt_down; };
static struct Source sources[32];
static int source_count;
static _Atomic bool input_ready;
static uint32_t routes[4]={UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX};
static int swaps[4];
static _Atomic int gyro_allowed[4]={1,1,1,1};
static bool pending_activation;
static unsigned long long revision, request_serial;
static _Atomic int session_gate=1, session_paused=-1, session_wanted=1;
static const char *request_kind="initial";
static uint32_t request_device=UINT32_MAX;
static _Atomic bool ui_pending;
static _Atomic double window_rect[4];
static int chord_held[32];
static uint32_t *(*native_joysticks)(int *);
static void (*sdl_free)(void *);
static bool session_test;
static _Atomic bool session_quit, session_finishing, session_worker_stopped;
static unsigned long long sample_serial;
static _Atomic unsigned int connected_ports;
static _Atomic int console_ports=-1;
static _Atomic bool app_active;
static _Atomic bool game_ended;
static _Atomic bool f5_down;
static _Atomic bool appkit_game_seen;
static double appkit_missing_since;
static uint32_t retro_driver_buttons[4];
static int32_t (*retro_driver_button)(unsigned int,uint16_t);
static void *test_joy[2];
static uint32_t test_ids[2]={UINT32_MAX,UINT32_MAX};
static bool test_freeze_status;
static _Atomic bool test_close_window;
static _Atomic int test_watch_step;
static _Atomic bool test_watch_failed;

#include "motion.inc"

#include "wii.inc"

#include "playstation.inc"
#include "ppsspp.inc"
#include "eden.inc"

static bool logical_id(uint32_t id) {
    for(int i=0;i<4;++i)if(ids[i]==id)return true;
    return false;
}
// RA's slot enumeration is deliberately limited to the stable logical ports.
// Native discovery below bypasses this hook and sees the actual same-runtime IDs.
#if BROOMM_SDL_MAJOR == 3
static int (*native_player_index)(void *);
static int logical_player_index(void *handle) {
    int index=fixture_index(handle,true);
    return index>=0?index:native_player_index(handle);
}
static uint32_t *logical_joysticks(int *count) {
    void *(*allocate)(size_t,size_t)=symbol("SDL_calloc");
    uint32_t *result=allocate(5,sizeof(uint32_t));
    if(!result){if(count)*count=0;return NULL;}
    int n=0;
    for(int i=0;i<4;++i)if(ids[i]!=UINT32_MAX)result[n++]=ids[i];
    if(count)*count=n;
    return result;
}
#endif

static void json_text(FILE *out,const char *s) {
    fputc('"',out);
    for(const unsigned char *p=(const void *)s;*p;++p) {
        if(*p=='"'||*p=='\\'){fputc('\\',out);fputc(*p,out);}
        else if(*p<32)fprintf(out,"\\u%04x",*p);
        else fputc(*p,out);
    }
    fputc('"',out);
}
static void session_request(const char *kind) {
    atomic_store(&session_gate,1);atomic_store(&session_wanted,1);
    request_kind=kind;++request_serial;
    request_device=UINT32_MAX;
    record("SESSION_REQUEST serial=%llu kind=%s",request_serial,kind);
}
static void finish_session_close(void *window) {
    if(!atomic_load(&session_worker_stopped)) {
        dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),window,finish_session_close);
        return;
    }
    bool (*close_widget)(void *)=dlsym(RTLD_DEFAULT,"_ZN7QWidget5closeEv");
    void (*quit_app)(void)=dlsym(RTLD_DEFAULT,"_ZN16QCoreApplication4quitEv");
    if(getenv("BROOMM_MELONDS")||getenv("BROOMM_EDEN")) {
        close_widget=symbol("_ZN7QWidget5closeEv");
        quit_app=symbol("_ZN16QCoreApplication4quitEv");
    }
    if(qt_main&&close_widget&&quit_app) {
        if(close_widget(qt_main))quit_app();
        else dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),window,finish_session_close);
    } else {
        // Avalonia's native window may outlive its managed delegate after a
        // game closes. Resolve a CURRENT visible window at delivery time.
        // NSApplication::terminate skips Avalonia's window-lifetime teardown.
        id app=send0((id)objc_getClass("NSApplication"),"sharedApplication");
        id windows=send0(app,"windows"),current=NULL;
        unsigned long count=((unsigned long(*)(id,SEL))objc_msgSend)(windows,sel_registerName("count"));
        double area=0;
        for(unsigned long i=0;i<count;++i) {
            id candidate=((id(*)(id,SEL,unsigned long))objc_msgSend)(windows,sel_registerName("objectAtIndex:"),i);
            if(!((bool(*)(id,SEL))objc_msgSend)(candidate,sel_registerName("isVisible")))continue;
            const char *title=((const char *(*)(id,SEL))objc_msgSend)(send0(candidate,"title"),sel_registerName("UTF8String"));
            if(title&&strstr(title,"ContentDialogOverlay"))continue;
            CGRect frame=objc_rect(candidate,sel_registerName("frame"));
            if(frame.size.width*frame.size.height>area){area=frame.size.width*frame.size.height;current=candidate;}
        }
        if(current) {
            record("APPKIT_QUIT_CURRENT_WINDOW");
            ((void(*)(id,SEL,id))objc_msgSend)(current,sel_registerName("performClose:"),NULL);
        } else record("APPKIT_QUIT_NO_LIVE_WINDOW waiting_for_native_teardown");
    }
}
static void session_release_f5(void *window) {
    if(((bool(*)(id,SEL))objc_msgSend)((id)window,sel_registerName("isVisible")))release_f5(window);
    send0((id)window,"release");
    atomic_store(&f5_down,false);
}
static void appkit_observe_content(bool ready) {
    if(ready){appkit_game_seen=true;appkit_missing_since=0;}
    else if(appkit_game_seen) {
        struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);
        double now=(double)ts.tv_sec+ts.tv_nsec/1e9;
        if(!appkit_missing_since)appkit_missing_since=now;
        if(now-appkit_missing_since>1.0)atomic_store(&game_ended,true);
    }
}
static void session_ui(void *unused) {
    (void)unused;
    if(atomic_load(&session_finishing)){atomic_store(&ui_pending,false);return;}
    atomic_store(&pause_requested,atomic_load(&session_wanted));
    static bool symbols_resolved;
    static uint32_t *azahar_pause;
    if(!symbols_resolved){azahar_pause=symbol("_ZN11GMainWindow11OnPauseGameEv");symbols_resolved=true;}
    if(qt_main&&azahar_pause) {
        uint32_t *code=azahar_pause;
        if(code[4]==0xf9402408&&code[5]==0x91008108) {
            uint8_t *flag=(uint8_t *)*(void **)((char *)qt_main+0x48)+0x20;
            if((int)__atomic_load_n(flag,__ATOMIC_ACQUIRE)!=atomic_load(&session_wanted))qt_pause_applied=-1;
        }
    }
    qt_tick();
    int actual=-1;
    if(getenv("BROOMM_EDEN")) {
        actual=eden_tick();
    } else if(getenv("BROOMM_PPSSPP")) {
        actual=ppsspp_tick();
    } else if(getenv("BROOMM_PLAYSTATION")) {
        actual=playstation_tick();
    } else if(core_system_fn&&core_state_fn&&core_set_state_fn) {
        void *system=((void *(*)(void))core_system_fn)();
        int state=((int(*)(void *))core_state_fn)(system);
        // Dolphin's console sockets are separate from its host SDL devices.
        // Change the native per-run SI settings, just as its controller dialog
        // does. Keeping four host routes must not plug four pads into the game.
        static bool si_resolved;
        static const void *(*si_info)(int);
        static void (*si_set)(int,const void *,const int *);
        static int (*si_get)(const void *);
        static void *(*get_si)(void *);
        static int (*get_type)(void *,int);
        if(!si_resolved) {
            si_info=symbol("_ZN6Config18GetInfoForSIDeviceEi");
            si_set=symbol("_ZN6Config3SetINS_4InfoIN15SerialInterface9SIDevicesEEES3_EEvNS_9LayerTypeERKT_RKT0_");
            si_get=symbol("_ZN6Config11GetUncachedIN15SerialInterface9SIDevicesEEET_RKNS_4InfoIS3_EE");
            get_si=symbol("_ZNK4Core6System18GetSerialInterfaceEv");
            get_type=symbol("_ZNK15SerialInterface22SerialInterfaceManager13GetDeviceTypeEi");
            si_resolved=true;
        }
        if((state==1||state==2)&&si_info&&si_set&&si_get) {
            unsigned int ports=atomic_load(&connected_ports);
            for(int p=0;p<4;++p) {
                int type=!dolphin_wii&&(ports&(1u<<p))?6:0;
                const void *info=si_info(p);
                if(si_get(info)!=type) {si_set(6,info,&type);record("DOLPHIN_SI port=%d type=%d",p,type);}
            }
        }
        int desired=atomic_load(&session_wanted)?1:2;
        if((state==1||state==2)&&state!=desired)
            ((void(*)(void *,int,bool,bool))core_set_state_fn)(system,desired,true,false);
        state=((int(*)(void *))core_state_fn)(system);
        if(state==1||state==2)actual=state==1;
        wii_tick(state);
        // Read native device objects only while the CPU is confirmed paused.
        if(state==1) {
            if(get_si&&get_type) {
                void *si=get_si(system);int mask=0;
                for(int p=0;p<4;++p)if(get_type(si,p)==6)mask|=1<<p;
                atomic_store(&console_ports,mask);
            }
        }
    } else if(melonds_thread()) {
        void *thread=melonds_thread();
        if(__atomic_load_n((uint8_t *)thread+0x38,__ATOMIC_ACQUIRE)) {
            uint32_t state=__atomic_load_n((uint32_t *)((char *)thread+0x34),__ATOMIC_ACQUIRE);
            if(state==1||state==2)actual=state==2;
        }
    } else if(rpcs_status) {
        int state=(int)__atomic_load_n(rpcs_status,__ATOMIC_ACQUIRE);
        if(state==3||state==4)actual=state==4;
    } else if(qt_main&&azahar_pause&&azahar_game_loaded()) {
        uint32_t *code=azahar_pause;
        if(code[4]==0xf9402408&&code[5]==0x91008108) {
            uint8_t *flag=(uint8_t *)*(void **)((char *)qt_main+0x48)+0x20;
            actual=__atomic_load_n(flag,__ATOMIC_ACQUIRE)?1:0;
        }
    }
    id app=send0((id)objc_getClass("NSApplication"),"sharedApplication");
    atomic_store(&app_active,((bool(*)(id,SEL))objc_msgSend)(app,sel_registerName("isActive")));
    id windows=send0(app,"windows"),window=NULL;
    unsigned long count=((unsigned long(*)(id,SEL))objc_msgSend)(windows,sel_registerName("count"));
    double largest=0;bool appkit_content_exists=false;
    for(unsigned long i=0;i<count;++i) {
        id candidate=((id(*)(id,SEL,unsigned long))objc_msgSend)(windows,sel_registerName("objectAtIndex:"),i);
        const char *title=((const char *(*)(id,SEL))objc_msgSend)(send0(candidate,"title"),sel_registerName("UTF8String"));
        bool game_title=title&&(strstr(title,"(64-bit)")||strstr(title,"(32-bit)")||strstr(title,"Paused"));
        if(game_title)appkit_content_exists=true;
        if(!((bool(*)(id,SEL))objc_msgSend)(candidate,sel_registerName("isVisible"))&&
           !((bool(*)(id,SEL))objc_msgSend)(candidate,sel_registerName("isMiniaturized")))continue;
        if(title&&(strstr(title,"ContentDialogOverlay")||strstr(title,"Broomm")))continue;
        CGRect frame=objc_rect(candidate,sel_registerName("frame"));
        double area=frame.size.width*frame.size.height;
        if(area>largest){window=candidate;largest=area;}
    }
    if(window) {
        CGRect frame=objc_rect(window,sel_registerName("frame"));
        window_rect[0]=frame.origin.x;window_rect[1]=frame.origin.y;
        window_rect[2]=frame.size.width;window_rect[3]=frame.size.height;
        if(getenv("BROOMM_PAUSE_APPKIT_F5")) {
            const char *title=((const char *(*)(id,SEL))objc_msgSend)(send0(window,"title"),sel_registerName("UTF8String"));
            bool ready=title&&(strstr(title,"(64-bit)")||strstr(title,"(32-bit)")||strstr(title,"Paused"));
            if(ready&&atomic_exchange(&test_close_window,false)) {
                record("SESSION_TEST_CLOSE_GAME_WINDOW");
                send0(window,"retain");
                ((void(*)(id,SEL,id))objc_msgSend)(window,sel_registerName("performClose:"),NULL);
                send0(window,"release");
                atomic_store(&session_paused,-1);
                atomic_store(&ui_pending,false);
                return;
            }
            if(ready) {
                actual=strstr(title,"Paused")!=NULL;
                if(actual!=atomic_load(&session_wanted)&&!appkit_pause_applied&&!atomic_load(&f5_down)) {
                    // Avalonia polls its keyboard hotkeys only while active.
                    // A sendEvent into a background app was silently ignored
                    // when Broomm owned focus on Apply. Wait for activation.
                    if(!((bool(*)(id,SEL))objc_msgSend)(app,sel_registerName("isActive"))||
                       !((bool(*)(id,SEL))objc_msgSend)(window,sel_registerName("isKeyWindow"))) {
                        record("APPKIT_ACTIVATE wanted_pause=%d",atomic_load(&session_wanted));
                        ((void(*)(id,SEL,bool))objc_msgSend)(app,sel_registerName("activateIgnoringOtherApps:"),true);
                        ((void(*)(id,SEL,id))objc_msgSend)(window,sel_registerName("makeKeyAndOrderFront:"),NULL);
                        atomic_store(&session_paused,actual);
                        atomic_store(&ui_pending,false);
                        return;
                    }
                    ((void(*)(id,SEL))objc_msgSend)(window,sel_registerName("makeKeyWindow"));
                    atomic_store(&f5_down,true);
                    send_f5(window,10);
                    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),(void *)send0(window,"retain"),session_release_f5);
                    appkit_pause_applied=1;
                } else if(actual==atomic_load(&session_wanted))appkit_pause_applied=0;
            }
        }
    }
    if(getenv("BROOMM_PAUSE_APPKIT_F5"))appkit_observe_content(appkit_content_exists);
    // Azahar runs a modal direct-launch warning before BootGame and app.exec.
    // Closing there can return successfully, then BootGame starts behind the
    // closed window and QCoreApplication::quit has no running loop to stop.
    // Keep servicing startup until the pinned frontend has finished loading;
    // only then stop sampling and enter its normal close/save path.
    if(atomic_load(&session_quit)&&(!azahar_pause||azahar_game_loaded())&&atomic_exchange(&session_quit,false)) {
        atomic_store(&session_finishing,true);
        // Let queued native resume/state notifications finish before destroying
        // the presenter. Stop SDL sampling before the emulator tears SDL down.
        // RetroArch owns its QUIT command and save-RAM teardown. Closing its
        // Cocoa window concurrently can exit before that teardown writes SRAM.
        // Stop sampling SDL here; Dart sends QUIT through the verified channel.
        if(!getenv("BROOMM_RETROARCH"))
            dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),window,finish_session_close);
    }
    if(getenv("BROOMM_RETROARCH"))actual=-1; // Dart verifies the network command ACK.
    atomic_store(&session_paused,actual);
    atomic_store(&ui_pending,false);
}

static bool discover_sources(void) {
    bool complete=true;
    uint32_t found[32];int count=0;
#if BROOMM_SDL_MAJOR == 3
    int n=0;uint32_t *list=native_joysticks(&n);
    if(!list||n<0){sdl_free(list);return false;}
    bool (*is_pad)(uint32_t)=symbol("SDL_IsGamepad");
    for(int i=0;i<n&&count<32;++i)if(!logical_id(list[i])&&is_pad(list[i]))found[count++]=list[i];
    sdl_free(list);
#else
    int (*num)(void)=symbol("SDL_NumJoysticks");
    uint32_t (*device_id)(int)=symbol("SDL_JoystickGetDeviceInstanceID");
    int (*is_pad)(int)=symbol("SDL_IsGameController");
    int n=num();
    if(n<0)return false;
    for(int i=0;i<n&&count<32;++i)if(!logical_id(device_id(i))&&is_pad(i))found[count++]=device_id(i);
#endif
    for(int i=source_count-1;i>=0;--i) {
        bool present=false;for(int j=0;j<count;++j)if(found[j]==sources[i].id)present=true;
        if(present)continue;
        for(int p=0;p<4;++p)if(routes[p]==sources[i].id)session_request("disconnect");
#if BROOMM_SDL_MAJOR == 3
        void (*close_pad)(void *)=symbol("SDL_CloseGamepad");
#else
        void (*close_pad)(void *)=symbol("SDL_GameControllerClose");
#endif
        record("SOURCE_REMOVED id=%u",sources[i].id);
        motion_close_source(&sources[i]);
        close_pad(sources[i].handle);
        sources[i]=sources[--source_count];chord_held[i]=chord_held[source_count];
    }
    for(int i=0;i<count;++i) {
        bool known=false;for(int j=0;j<source_count;++j)if(sources[j].id==found[i])known=true;
        if(known||source_count==32)continue;
        void *handle=NULL;
#if BROOMM_SDL_MAJOR == 3
        handle=real_open_pad(found[i]);
        const char *(*name_fn)(void *)=symbol("SDL_GetGamepadName");
#else
        for(int index=0;index<n;++index)if(device_id(index)==found[i])handle=real_open_pad((uint32_t)index);
        const char *(*name_fn)(void *)=symbol("SDL_GameControllerName");
#endif
        if(!handle){complete=false;continue;}
        struct Source *source=&sources[source_count];*source=(struct Source){.id=found[i],.handle=handle};
        snprintf(source->name,sizeof(source->name),"%s",name_fn(handle));
#if BROOMM_SDL_MAJOR == 3
        int (*type_fn)(void *)=symbol("SDL_GetGamepadType");
        int type=type_fn?type_fn(handle):0;
        source->family=(type==2||type==3)?1:(type>=4&&type<=6)?2:(type>=7&&type<=10)?3:type==11?4:0;
#else
        int (*type_fn)(void *)=symbol("SDL_GameControllerGetType");
        int type=type_fn?type_fn(handle):0;
        source->family=(type==1||type==2)?1:(type==3||type==4||type==7)?2:(type==5||(type>=11&&type<=13))?3:0;
#endif
        chord_held[source_count++]=0;
        record("SOURCE_ADDED id=%u name=%s",found[i],source->name);
    }
    return complete;
}

static void read_command(void) {
    FILE *f=fopen(getenv("BROOMM_SESSION_COMMAND"),"r");if(!f)return;
    unsigned long long next;unsigned int r[4];int active,pause,s[4],quit=0,modes[4],gyro[4];
    int n=fscanf(f,"%llu %d %d %u %u %u %u %d %d %d %d %d %d %d %d %d %d %d %d %d",&next,&active,&pause,&r[0],&r[1],&r[2],&r[3],&s[0],&s[1],&s[2],&s[3],&quit,&modes[0],&modes[1],&modes[2],&modes[3],&gyro[0],&gyro[1],&gyro[2],&gyro[3]);
    fclose(f);
    if(n!=20||next<=revision||(active!=0&&active!=1)||(pause!=0&&pause!=1))return;
    for(int p=0;p<4;++p)if(modes[p]<0||modes[p]>3||(gyro[p]!=0&&gyro[p]!=1))return;
    for(int p=0;p<4;++p){if(s[p]!=0&&s[p]!=1)return;for(int q=0;q<p;++q)if(r[p]!=UINT32_MAX&&r[p]==r[q])return;}
    bool valid=true;
    for(int p=0;p<4;++p) {
        routes[p]=r[p];swaps[p]=s[p];atomic_store(&gyro_allowed[p],gyro[p]);
        if(active&&r[p]!=UINT32_MAX) {
            bool present=false;for(int i=0;i<source_count;++i)if(sources[i].id==r[p])present=true;
            if(!present)valid=false;
        }
    }
    if(quit==1)atomic_store(&session_quit,true);
    if(dolphin_wii&&!quit) {
        for(int p=0;p<4;++p)atomic_store(&wii_modes[p],modes[p]);
        unsigned int present=0;
        for(int p=0;p<4;++p)for(int i=0;i<source_count;++i)
            if(routes[p]==sources[i].id)present|=1u<<p;
        atomic_store(&connected_ports,present);
        atomic_store(&wii_revision,next);
        atomic_store(&session_gate,1); // Native reload must finish before resume.
    }
    bool was_blocked=atomic_load(&session_gate);
    revision=next;pending_activation=active&&valid&&was_blocked;
    atomic_store(&session_gate,!active||!valid||pending_activation);
    atomic_store(&session_wanted,pause||!valid||pending_activation);
    if(!valid)session_request("disconnect");
    record("SESSION_COMMAND revision=%llu active=%d valid=%d",revision,active,valid);
}

// Read only plain atomic counters from the exact hash-pinned executable. Never
// dereference RPCS3's C++ progress strings or alter its dialog/cache settings.
static void loading_status(FILE *out) {
    if(!rpcs_ftotal||!rpcs_fdone||!rpcs_ptotal||!rpcs_pdone||!rpcs_ftotal_bits||!rpcs_fknown_bits)return;
    struct Progress {uint64_t ft,fd,pt,pd,bits,known;} a={0},b={0};
    for(int attempt=0;attempt<3;attempt++) {
        a=(struct Progress){__atomic_load_n(rpcs_ftotal,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_fdone,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_ptotal,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_pdone,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_ftotal_bits,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_fknown_bits,__ATOMIC_ACQUIRE)};
        b=(struct Progress){__atomic_load_n(rpcs_ftotal,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_fdone,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_ptotal,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_pdone,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_ftotal_bits,__ATOMIC_ACQUIRE),__atomic_load_n(rpcs_fknown_bits,__ATOMIC_ACQUIRE)};
        if(!memcmp(&a,&b,sizeof(a)))break;
    }
    if(memcmp(&a,&b,sizeof(a))||a.fd>a.ft||a.pd>a.pt||a.known>a.bits||(!a.ft&&!a.pt))return;
    fprintf(out,",\"loading\":{\"filesTotal\":%llu,\"filesDone\":%llu,\"modulesTotal\":%llu,\"modulesDone\":%llu,\"totalBits\":%llu,\"knownBits\":%llu}",(unsigned long long)a.ft,(unsigned long long)a.fd,(unsigned long long)a.pt,(unsigned long long)a.pd,(unsigned long long)a.bits,(unsigned long long)a.known);
}

static void write_status(void) {
    const char *path=getenv("BROOMM_SESSION_STATUS");char temp[4096];snprintf(temp,sizeof(temp),"%s.tmp",path);
    FILE *out=fopen(temp,"w");if(!out)return;
    fprintf(out,"{\"protocol\":4,\"pid\":%d,\"sample\":%llu,\"ack\":%llu,\"requestSerial\":%llu,\"request\":\"%s\",\"blocked\":%s,\"paused\":%d,\"window\":[%.1f,%.1f,%.1f,%.1f],\"devices\":[",getpid(),++sample_serial,revision,request_serial,request_kind,atomic_load(&session_gate)?"true":"false",atomic_load(&session_paused),window_rect[0],window_rect[1],window_rect[2],window_rect[3]);
    for(int i=0;i<source_count;++i) {
        if(i)fputc(',',out);
        fprintf(out,"{\"id\":%u,\"name\":",sources[i].id);json_text(out,sources[i].name);
        fprintf(out,",\"buttons\":%u,\"x\":%d,\"y\":%d,\"rx\":%d,\"ry\":%d,\"lt\":%d,\"rt\":%d,\"family\":%d,\"sensors\":%d,\"sensorReady\":%d,\"motionTime\":%llu,\"accel\":[%.6f,%.6f,%.6f],\"gyro\":[%.6f,%.6f,%.6f]}",sources[i].buttons,sources[i].axes[0],sources[i].axes[1],sources[i].axes[2],sources[i].axes[3],sources[i].axes[4],sources[i].axes[5],sources[i].family,sources[i].sensors,sources[i].sensor_ready,(unsigned long long)sources[i].motion_time,sources[i].motion[0][0],sources[i].motion[0][1],sources[i].motion[0][2],sources[i].motion[1][0],sources[i].motion[1][1],sources[i].motion[1][2]);
    }
    fprintf(out,"],\"ports\":[");
    for(int p=0;p<4;++p)fprintf(out,"%s%u",p?",":"",ids[p]);
    fprintf(out,"],\"logicalButtons\":[");
    for(int p=0;p<4;++p){unsigned int bits=0;for(int b=0;b<21;b++)if(real_button(pad[p],b))bits|=1u<<b;fprintf(out,"%s%u",p?",":"",bits);}
    fprintf(out,"],\"connectedPorts\":%u,\"consolePorts\":%d,\"appActive\":%s,\"pspButtons\":%u",atomic_load(&connected_ports),atomic_load(&console_ports),atomic_load(&app_active)?"true":"false",atomic_load(&psp_buttons));
    fprintf(out,",\"nativeProgram\":\"%016llx\",\"switchButtons\":%llu",(unsigned long long)atomic_load(&eden_program),(unsigned long long)atomic_load(&eden_buttons));
    if(dolphin_wii) {
        fprintf(out,",\"wiiApplied\":%llu,\"wiiSources\":%u,\"wiiSelected\":[",atomic_load(&wii_applied),atomic_load(&wii_sources));
        for(int p=0;p<4;++p)fprintf(out,"%s%d",p?",":"",atomic_load(&wii_selected[p]));
        fprintf(out,"],\"wiiActive\":[");for(int p=0;p<4;++p)fprintf(out,"%s%d",p?",":"",atomic_load(&wii_active[p]));
        fprintf(out,"],\"wiiOrientation\":[");for(int p=0;p<4;++p)fprintf(out,"%s%d",p?",":"",atomic_load(&wii_orientation[p]));
        fprintf(out,"],\"wiiButtons\":[");for(int p=0;p<4;++p)fprintf(out,"%s%u",p?",":"",atomic_load(&wii_buttons[p]));fputc(']',out);
        if(session_test) {
            fprintf(out,",\"wiiPointer\":[");
            for(int p=0;p<4;++p)fprintf(out,"%s[%.6f,%.6f]",p?",":"",atomic_load(&wii_pointer[p][0]),atomic_load(&wii_pointer[p][1]));
            fputc(']',out);
        }
    }
    if(session_test) {
        fprintf(out,",\"watchDeferralVerified\":%s",atomic_load(&test_watch_step)==2&&!atomic_load(&test_watch_failed)?"true":"false");
        fprintf(out,",\"testSourceIds\":[%u,%u],\"driverButtons\":[",test_ids[0],test_ids[1]);
        for(int p=0;p<4;++p)fprintf(out,"%s%u",p?",":"",retro_driver_buttons[p]);
        fputc(']',out);
    }
    motion_write_status(out);
    loading_status(out);
    fprintf(out,",\"inputReady\":%s",atomic_load(&input_ready)?"true":"false");
    fprintf(out,",\"queries\":%llu,\"consumedPorts\":%u}\n",(unsigned long long)atomic_load(&queries),atomic_load(&consumed_ports));fclose(out);rename(temp,path);
}

#include "test_sources.inc"

static void session_worker(void) {
    session_test=getenv("BROOMM_SESSION_TEST")!=NULL;
    dolphin_wii=getenv("BROOMM_DOLPHIN_WII")!=NULL;
    (void)session_test;
    sdl_free=symbol("SDL_free");
#if BROOMM_SDL_MAJOR == 3
    native_joysticks=symbol("SDL_GetJoysticks");
#endif
#if BROOMM_SDL_MAJOR == 3
    if(getenv("BROOMM_RETROARCH")||getenv("BROOMM_PLAYSTATION")) {
        hook("SDL_GetJoysticks",logical_joysticks,(void **)&native_joysticks);
        hook("SDL_GetGamepadPlayerIndex",logical_player_index,(void **)&native_player_index);
        if(session_test)retro_driver_button=symbol("sdl3_joypad_button");
    }
#endif
    void (*lock)(void)=symbol("SDL_LockJoysticks"),(*unlock)(void)=symbol("SDL_UnlockJoysticks");
    if(!lock||!unlock||!real_button||!real_axis||!real_joy_button||!real_joy_axis) {
        record("SESSION_FATAL required SDL input hooks unavailable");
        return;
    }
    lock();
    if(session_test&&getenv("BROOMM_TEST_PRECONNECTED"))test_sources_tick();
    if(!attach_fixtures()){unlock();record("SESSION_FATAL virtual ports unavailable");return;}
    unlock();
#if BROOMM_SDL_MAJOR == 3
    bool (*set_button)(void *,int,bool)=symbol("SDL_SetJoystickVirtualButton");
    bool (*set_axis)(void *,int,int16_t)=symbol("SDL_SetJoystickVirtualAxis");
    void (*update)(void)=symbol("SDL_UpdateJoysticks");
#else
    int (*set_button)(void *,int,uint8_t)=symbol("SDL_JoystickSetVirtualButton");
    int (*set_axis)(void *,int,int16_t)=symbol("SDL_JoystickSetVirtualAxis");
    void (*update)(void)=symbol("SDL_JoystickUpdate");
#endif
    pid_t owner=getppid();
    bool discovery_failed=false;
    for(unsigned long tick=0;!atomic_load(&session_finishing);++tick) {
        if(atomic_exchange(&watch_queue_overflow,false))session_request("input-error");
        if(atomic_exchange(&game_ended,false)) {
            session_request("game-ended");
            appkit_game_seen=false;
        }
        if(getppid()!=owner&&!atomic_load(&session_gate))session_request("launcher-exit");
        fixture_call=true;
        lock();test_watch_tick();test_sources_tick();update();
        if(tick%16==0) {
            bool ready=discover_sources();atomic_store(&input_ready,ready);
            if(!ready&&!discovery_failed)session_request("input-error");
            discovery_failed=!ready;
        }
        if(tick%4==0)read_command();
        for(int i=0;i<source_count;++i) {
            struct Source *src=&sources[i];src->buttons=0;
            for(int b=0;b<21;++b)if(real_button(src->handle,b))src->buttons|=1u<<b;
            for(int a=0;a<6;++a)src->axes[a]=real_axis(src->handle,a);
            motion_sample_source(src);
            bool assigned=false;for(int p=0;p<4;++p)if(routes[p]==src->id)assigned=true;
            bool chord=(src->buttons&(1u<<4))&&(src->buttons&(1u<<8));
            if(chord&&!chord_held[i]&&assigned&&!atomic_load(&session_gate))session_request("menu");
            chord_held[i]=chord;
            if(src->axes[5]>=16384)src->rt_down=true;
            if(src->axes[5]<=8192)src->rt_down=false;
            if(!(src->buttons&(1u<<7))&&!src->rt_down)src->gyro_chord_ready=true;
            if(src->gyro_chord_ready&&(src->buttons&(1u<<7))&&src->rt_down) {
                src->gyro_chord_ready=false;
                // Gate before publishing logical input, just like the menu
                // chord. Dart owns the setting and native config transition.
                if(assigned&&!atomic_load(&session_gate)&&!(src->buttons&((1u<<4)|(1u<<8)|(1u<<9)|(1u<<10)))) {
                    session_request("gyro");request_device=src->id;
                }
            }
        }
        unsigned int present_ports=0;
        for(int p=0;p<4;++p)for(int i=0;i<source_count;++i)
            if(routes[p]==sources[i].id)present_ports|=1u<<p;
        atomic_store(&connected_ports,present_ports);
        if(pending_activation) {
            bool released=true;
            for(int i=0;i<source_count;++i)for(int p=0;p<4;++p)
                if(sources[i].id==routes[p]&&sources[i].buttons)released=false;
            if(!strcmp(request_kind,"gyro"))for(int i=0;i<source_count;++i)
                if(sources[i].id==request_device&&sources[i].axes[5]>8192)released=false;
            if(released&&(!dolphin_wii||atomic_load(&wii_applied)>=atomic_load(&wii_revision))){pending_activation=false;atomic_store(&session_gate,0);atomic_store(&session_wanted,0);}
        }
        for(int p=0;p<4;++p) {
            struct Source *src=NULL;
            for(int i=0;i<source_count;++i)if(sources[i].id==routes[p])src=&sources[i];
            bool live=src&&!atomic_load(&session_gate);
            for(int b=0;b<21;++b) {
                int mapped=swaps[p]&&b<4?b^1:b;
                set_button(joy[p],b,live&&real_button(src->handle,mapped));
            }
            for(int a=0;a<6;++a) {
                int value=live?real_axis(src->handle,a):0;
                // SDL gamepad trigger values are 0..32767; virtual joystick
                // axes are -32768..32767, including trigger release at -32768.
                if(a>=4)value=value*2-32768;
                set_axis(joy[p],a,(int16_t)value);
            }
        }
        update();
        motion_route_and_emit(tick%2==0);
        if(retro_driver_button)for(int p=0;p<4;++p) {
            uint32_t bits=0;
            for(int b=0;b<21;++b)if(retro_driver_button((unsigned)p,(uint16_t)b))bits|=1u<<b;
            retro_driver_buttons[p]=bits;
        }
        unlock();fixture_call=false;
        if(tick%4==0&&!test_freeze_status)write_status();
        if(tick%8==0&&!atomic_load(&session_finishing)&&!atomic_exchange(&ui_pending,true))dispatch_async_f(dispatch_get_main_queue(),NULL,session_ui);
        // A disappeared launcher never releases input or automatically resumes.
        usleep(8000);
    }
    atomic_store(&session_worker_stopped,true);
}
