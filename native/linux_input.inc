#if BROOMM_SDL_MAJOR == 3
typedef bool Button;
typedef bool WatchResult;
#define BUTTON_NAME "SDL_GetGamepadButton"
#define AXIS_NAME "SDL_GetGamepadAxis"
#define JOY_BUTTON_NAME "SDL_GetJoystickButton"
#define JOY_AXIS_NAME "SDL_GetJoystickAxis"
#define PAD_JOY_NAME "SDL_GetGamepadJoystick"
#define JOY_ID_NAME "SDL_GetJoystickID"
#define EVENT_SIZE 128
#define ID_OFFSET 16
#define BUTTON_OFFSET 20
#else
typedef uint8_t Button;
typedef int WatchResult;
#define BUTTON_NAME "SDL_GameControllerGetButton"
#define AXIS_NAME "SDL_GameControllerGetAxis"
#define JOY_BUTTON_NAME "SDL_JoystickGetButton"
#define JOY_AXIS_NAME "SDL_JoystickGetAxis"
#define PAD_JOY_NAME "SDL_GameControllerGetJoystick"
#define JOY_ID_NAME "SDL_JoystickInstanceID"
#define EVENT_SIZE 56
#define ID_OFFSET 8
#define BUTTON_OFFSET 12
#endif

static FILE *log_file;
static const char *log_path;
static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;
static void *sdl;
static _Atomic int policy;
static void *joy[4], *pad[4];
static _Atomic uint32_t ids[4]={UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX};
static _Atomic uint64_t queries, changed, events, watcher_events, draws;
static _Atomic unsigned int consumed_ports;
static const char *control_path;
static _Thread_local bool fixture_call;
struct SymbolEntry { char name[160]; uintptr_t address; };
static struct SymbolEntry symbol_entries[4000];
static size_t symbol_count;
struct ApiSlot { const char *name; size_t index; };
#include "linux_abi_slots.h"
static void **api_table;
static void **api_slot(const char *name) {
    if(!api_table)return NULL;
    // Dynamic libraries must export each requested API. Older SDL releases
    // have shorter tables; their absent appended entries must never be read.
    if(sdl&&!dlsym(sdl,name))return NULL;
    for(size_t i=0;i<sizeof(known_slots)/sizeof(known_slots[0]);++i)
        if(!strcmp(known_slots[i].name,name))return api_table+known_slots[i].index;
    return NULL;
}

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
static _Atomic unsigned long long session_resume_serial;
static int session_pause_command(struct PauseTransition *control,int wanted,int actual) {
    return pause_transition(control,wanted,actual,atomic_load(&session_resume_serial));
}
// Published by the sampling worker before releasing its pause gate. A UI tick
// can miss a quick gate/release pair, but must not lose that explicit Resume.
static void set_session_wanted(int wanted) {
    if(!wanted&&atomic_load(&session_wanted))atomic_fetch_add(&session_resume_serial,1);
    atomic_store(&session_wanted,wanted);
}
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
static _Atomic bool app_active,linux_orphaned;
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
static _Atomic uint32_t psp_buttons;
static _Atomic uint64_t eden_program,eden_buttons;

#include "linux_symbols.inc"
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
    atomic_store(&session_gate,1);set_session_wanted(1);
    request_kind=kind;++request_serial;
    request_device=UINT32_MAX;
    record("SESSION_REQUEST serial=%llu kind=%s",request_serial,kind);
}

static bool hook(const char *name, void *replacement, void **original) {
    void *fn = symbol(name);
    void **slot = sdl?dispatch_slot(fn):api_slot(name); if(!slot)slot=dispatch_slot(fn);
    if(!slot)slot=api_slot(name);
    if (!slot) { record("HOOK_UNSUPPORTED name=%s public=%p", name, fn); return false; }
    *original = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    // The original may still be SDL's lazy default stub, but initialization below
    // has resolved the table before any replacement is published.
    __atomic_store_n(slot, replacement, __ATOMIC_RELEASE);
    record("HOOK name=%s public=%p slot=%p original=%p", name, fn, (void *)slot, *original);
    return true;
}

static Button (*real_button)(void *, int), (*real_joy_button)(void *, int);
static int16_t (*real_axis)(void *, int), (*real_joy_axis)(void *, int);
static void *(*pad_joystick)(void *);
static uint32_t (*joystick_id)(void *);
static int (*real_peep)(void *, int, int, uint32_t, uint32_t);
static void *(*real_open_pad)(uint32_t), *(*real_open_joy)(uint32_t);
static _Atomic int ryu_pad_refs[4];
static void (*ryu_real_close)(void *);
static _Thread_local bool ryu_delivered_event;
static void ryu_close_pad(void *handle) {
    int port=fixture_index(handle,true);
    if(getenv("BROOMM_RYUBING")&&!fixture_call&&port>=0&&atomic_load(&ryu_pad_refs[port])>0)atomic_fetch_sub(&ryu_pad_refs[port],1);
    ryu_real_close(handle);
}
static void ryu_before_poll(void) {
    if(!ryu_delivered_event)return;ryu_delivered_event=false;unsigned mask=0;
    for(int p=0;p<4;++p)if(atomic_load(&ryu_pad_refs[p])>0)mask|=1u<<p;
    atomic_store(&console_ports,(int)mask);
}
static void ryu_after_poll(void *event,int success) {
    if(!success||!getenv("BROOMM_RYUBING"))return;uint32_t type;memcpy(&type,event,4);
    if(type==0x605||type==0x606)ryu_delivered_event=true;
}
#ifdef BROOMM_SESSION_BRIDGE
#include "sdl2_ports.inc"
#endif
static uint32_t melonds_port_index(uint32_t requested) {
#if BROOMM_SDL_MAJOR == 2
    if(getenv("BROOMM_MELONDS")&&!fixture_call&&ids[0]!=UINT32_MAX) {
        int (*num)(void)=symbol("SDL_NumJoysticks");
        int (*instance)(int)=symbol("SDL_JoystickGetDeviceInstanceID");
        if(num&&instance)for(int i=0;i<num();++i)if((uint32_t)instance(i)==ids[0])return (uint32_t)i;
    }
#endif
    return requested;
}
#if BROOMM_SDL_MAJOR == 3
static bool (*real_poll)(void *), (*real_wait)(void *, int), (*real_wait_forever)(void *);
#else
static int (*real_poll)(void *), (*real_wait)(void *, int), (*real_wait_forever)(void *);
#endif
static void *open_pad_hook(uint32_t id) {
#if defined(BROOMM_SESSION_BRIDGE) && BROOMM_SDL_MAJOR == 2
    if(!fixture_call&&sdl2_port_limit()) {
        int index=sdl2_real_index((int)id);if(index<0)return NULL;
        return real_open_pad((uint32_t)index);
    }
#endif
    if(getenv("BROOMM_SESSION")&&(getenv("BROOMM_RETROARCH")||getenv("BROOMM_PLAYSTATION"))&&!fixture_call) {
        bool logical=false;for(int i=0;i<4;++i)if(ids[i]==id)logical=true;
        if(!logical)return NULL;
    }
    void *p=real_open_pad(melonds_port_index(id));
    if(getenv("BROOMM_RYUBING")&&!fixture_call&&p){int port=fixture_index(p,true);if(port>=0)atomic_fetch_add(&ryu_pad_refs[port],1);}
    record("OPEN_GAMEPAD id_or_index=%u handle=%p fixture_call=%d",id,p,fixture_call);
    return p;
}
static void *open_joy_hook(uint32_t id) {
#if defined(BROOMM_SESSION_BRIDGE) && BROOMM_SDL_MAJOR == 2
    if(!fixture_call&&sdl2_port_limit()) {
        int index=sdl2_real_index((int)id);if(index<0)return NULL;
        void *handle=real_open_joy((uint32_t)index);
        if(getenv("BROOMM_EDEN"))record("EDEN_OPEN_JOYSTICK logical=%u actual=%d handle=%p",id,index,handle);
        return handle;
    }
#endif
    if(getenv("BROOMM_SESSION")&&(getenv("BROOMM_RETROARCH")||getenv("BROOMM_PLAYSTATION"))&&!fixture_call) {
        bool logical=false;for(int i=0;i<4;++i)if(ids[i]==id)logical=true;
        if(!logical)return NULL;
    }
    void *p=real_open_joy(melonds_port_index(id));
    record("OPEN_JOYSTICK id_or_index=%u handle=%p fixture_call=%d",id,p,fixture_call);
    return p;
}

static int fixture_index(void *handle, bool gamepad) {
    void *j = gamepad && pad_joystick ? pad_joystick(handle) : handle;
    if (!j || !joystick_id) return -1;
    uint32_t id = joystick_id(j);
    for(int i=0;i<4;++i) if(ids[i]!=UINT32_MAX && id==ids[i]) return i;
    return -1;
}

static void trace_query(const char *api, int index, int input, int raw, int effective,
                        void *caller) {
    if (fixture_call) return;
    if(index>=0&&index<4)atomic_fetch_or(&consumed_ports,1u<<index);
    uint64_t n = atomic_fetch_add(&queries, 1);
    if (raw != effective) atomic_fetch_add(&changed, 1);
    static _Atomic int changed_mode=-1;
    static _Atomic long log_second=-1;
    bool emit=n<16;
    if(raw!=effective&&atomic_exchange(&changed_mode,atomic_load(&policy))!=atomic_load(&policy))emit=true;
    if(n%120==0) {
        struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
        if(atomic_exchange(&log_second,now.tv_sec)!=now.tv_sec)emit=true;
    }
    if (emit) {
        Dl_info info = {0}; dladdr(caller, &info);
        record("QUERY api=%s fixture=%d input=%d raw=%d effective=%d mode=%d caller=%s+0x%lx",
               api, index, input, raw, effective, atomic_load(&policy),
               info.dli_fname ? info.dli_fname : "?",
               (unsigned long)((uintptr_t)caller - (uintptr_t)info.dli_fbase));
    }
}

static Button mapped_button(void *handle, int button, bool gamepad, void *caller) {
    Button (*read)(void *, int) = gamepad ? real_button : real_joy_button;
    int i = fixture_index(handle, gamepad), mode = atomic_load(&policy);
    Button raw = read(handle, button);
    void *source = handle;
    int mapped = button;
    if (i >= 0 && mode == 1 && button >= 0 && button <= 1) mapped = 1 - button;
    if (i >= 0 && mode == 2) source = gamepad ? pad[1 - i] : joy[1 - i];
    Button value = source && (source!=handle||mapped!=button) ? read(source, mapped) : raw;
    trace_query(gamepad ? BUTTON_NAME : JOY_BUTTON_NAME, i, button, raw, value, caller);
    return value;
}
static Button button_hook(void *p, int b) { return mapped_button(p, b, true, __builtin_return_address(0)); }
static Button joy_button_hook(void *p, int b) { return mapped_button(p, b, false, __builtin_return_address(0)); }
static int16_t mapped_axis(void *handle, int axis, bool gamepad, void *caller) {
    int16_t (*read)(void *, int) = gamepad ? real_axis : real_joy_axis;
    int i = fixture_index(handle, gamepad), mode = atomic_load(&policy);
    int16_t raw = read(handle, axis);
    void *source = i >= 0 && mode == 2 ? (gamepad ? pad[1-i] : joy[1-i]) : handle;
    int16_t value = source && source!=handle ? read(source, axis) : raw;
    trace_query(gamepad ? AXIS_NAME : JOY_AXIS_NAME, i, axis, raw, value, caller);
    return value;
}
static int16_t axis_hook(void *p, int a) { return mapped_axis(p, a, true, __builtin_return_address(0)); }
static int16_t joy_axis_hook(void *p, int a) { return mapped_axis(p, a, false, __builtin_return_address(0)); }

static void remap_event(void *event, const char *path) {
    if (!event) return;
    uint32_t type, id;
    memcpy(&type, event, 4);
#if defined(BROOMM_SESSION_BRIDGE) && BROOMM_SDL_MAJOR == 2
    if(sdl2_port_event(event,type))return;
#endif
    if (!((type >= 0x600 && type <= 0x604) || (type >= 0x650 && type <= 0x652))) return;
    memcpy(&id, (char *)event + ID_OFFSET, 4);
    int i = id == ids[0] && ids[0]!=UINT32_MAX ? 0 : id == ids[1] && ids[1]!=UINT32_MAX ? 1 : -1;
    if (i < 0) return;
    int mode = atomic_load(&policy);
    uint8_t *button = (uint8_t *)event + BUTTON_OFFSET;
    if (mode == 1 && (type == 0x603 || type == 0x604 || type == 0x651 || type == 0x652) && *button <= 1)
        *button = 1 - *button;
    if (mode == 2) { id = ids[1-i]; memcpy((char *)event + ID_OFFSET, &id, 4); }
    uint64_t n = atomic_fetch_add(&events, 1);
    if (n < 20 || n%32==0) record("EVENT path=%s type=0x%x fixture=%d delivered_id=%u control=%u mode=%d",
                       path, type, i, id, *button, mode);
}
#if BROOMM_SDL_MAJOR == 3
static bool poll_hook(void *e) { linux_ui_tick();ryu_before_poll();bool r = real_poll(e); if (r) remap_event(e,"poll");ryu_after_poll(e,r);return r; }
static bool wait_hook(void *e, int ms) { bool r = real_wait(e,ms); if (r) remap_event(e,"wait"); return r; }
static bool wait_forever_hook(void *e) { bool r=real_wait_forever(e);if(r)remap_event(e,"wait_forever");return r; }
#else
static int poll_hook(void *e) { linux_ui_tick();ryu_before_poll();int r = real_poll(e); if (r) remap_event(e,"poll");ryu_after_poll(e,r);return r; }
static int wait_hook(void *e, int ms) { int r = real_wait(e,ms); if (r) remap_event(e,"wait"); return r; }
static int wait_forever_hook(void *e) { int r=real_wait_forever(e);if(r)remap_event(e,"wait_forever");return r; }
#endif
static int peep_hook(void *e, int n, int action, uint32_t min, uint32_t max) {
    int r = real_peep(e,n,action,min,max);
    if (e && action != 0) for (int i=0; i<r; ++i) remap_event((char *)e+i*EVENT_SIZE,"peep");
    return r;
}

typedef WatchResult (*Watch)(void *, void *);
struct WatchEntry { Watch callback; void *userdata; _Atomic bool active; };
static struct WatchEntry watches[16];
static pthread_mutex_t watch_lock = PTHREAD_MUTEX_INITIALIZER;
#if BROOMM_SDL_MAJOR == 3
static bool (*real_add_watch)(Watch, void *);
#else
static void (*real_add_watch)(Watch, void *);
#endif
static void (*real_del_watch)(Watch, void *);
// Azahar's watcher takes its own controller-map lock and calls SDL. Delivering
// it synchronously under SDL's joystick lock can invert locks or recurse into
// the same map during GameControllerOpen. Defer only that pinned integration.
struct DeferredWatch { struct WatchEntry *entry; _Alignas(8) unsigned char event[EVENT_SIZE]; };
#ifdef BROOMM_SESSION_BRIDGE
static void motion_observe_event(const void *event);
#endif
static struct DeferredWatch deferred_watches[1024];
static size_t deferred_head,deferred_count;
static bool deferred_scheduled;
static _Atomic bool watch_queue_overflow;
static pthread_mutex_t deferred_lock=PTHREAD_MUTEX_INITIALIZER;
static void drain_watches(void *unused) {
    (void)unused;
    for(int n=0;n<64;++n) {
        pthread_mutex_lock(&deferred_lock);
        if(!deferred_count){deferred_scheduled=false;pthread_mutex_unlock(&deferred_lock);return;}
        struct DeferredWatch next=deferred_watches[deferred_head];
        deferred_head=(deferred_head+1)%1024;--deferred_count;
        pthread_mutex_unlock(&deferred_lock);
        if(atomic_load(&next.entry->active)) {
#if defined(BROOMM_SESSION_BRIDGE) && BROOMM_SDL_MAJOR == 2
            uint32_t pending_type;memcpy(&pending_type,next.event,4);
            if(getenv("BROOMM_EDEN")&&(pending_type==0x605||pending_type==0x653)) {
                // SDL emits these inside AttachVirtual, before its new instance
                // ID can be published. Resolve the index on deferred delivery.
                remap_event(next.event,"watch-added");
                memcpy(&pending_type,next.event,4);if(!pending_type)continue;
            }
#endif
            next.entry->callback(next.entry->userdata,next.event);
#ifdef BROOMM_SESSION_BRIDGE
            motion_observe_event(next.event);
#endif
        }
    }
    dispatch_async_f(dispatch_get_main_queue(),NULL,drain_watches);
}
static WatchResult watch_thunk(void *data, void *event) {
    struct WatchEntry *w = data;
    _Alignas(8) unsigned char copy[EVENT_SIZE];
    memcpy(copy,event,EVENT_SIZE);
    uint32_t event_type;memcpy(&event_type,copy,4);
    bool pending_added=false;
#if defined(BROOMM_SESSION_BRIDGE) && BROOMM_SDL_MAJOR == 2
    pending_added=getenv("BROOMM_EDEN")&&(event_type==0x605||event_type==0x653);
#endif
    if(!pending_added)remap_event(copy,"watch");
    atomic_fetch_add(&watcher_events,1);
    memcpy(&event_type,copy,4);
    bool input_event=(event_type>=0x600&&event_type<0x610)||(event_type>=0x650&&event_type<0x660);
    bool test_event=event_type==0x8001&&getenv("BROOMM_SESSION_TEST");
    if(getenv("BROOMM_DEFER_SDL_WATCHES")&&(input_event||test_event)) {
        pthread_mutex_lock(&deferred_lock);
        // Keep the latest continuous sample for each device/control. Button
        // edges and hotplug remain ordered, including their release events.
        if(event_type==0x600||event_type==0x650||event_type==0x659) {
            for(size_t n=deferred_count;n>0;--n) {
                struct DeferredWatch *prior=&deferred_watches[(deferred_head+n-1)%1024];
                if(prior->entry==w&&memcmp(prior->event,copy,4)==0&&memcmp(prior->event+8,copy+8,5)==0) {
                    memcpy(prior->event,copy,EVENT_SIZE);pthread_mutex_unlock(&deferred_lock);return 1;
                }
            }
        }
        if(deferred_count==1024) {
            // Fail closed on an unresponsive main loop; do not block SDL while
            // holding its lock or silently discard a button-release event.
            record("WATCH_QUEUE_OVERFLOW input_gate_closed");
            atomic_store(&watch_queue_overflow,true);
        } else {
            size_t tail=(deferred_head+deferred_count++)%1024;
            deferred_watches[tail].entry=w;memcpy(deferred_watches[tail].event,copy,EVENT_SIZE);
            if(!deferred_scheduled){deferred_scheduled=true;dispatch_async_f(dispatch_get_main_queue(),NULL,drain_watches);}
        }
        pthread_mutex_unlock(&deferred_lock);
        return 1; // SDL event-watch return values are ignored.
    }
    WatchResult result=w->callback(w->userdata,copy);
#ifdef BROOMM_SESSION_BRIDGE
    motion_observe_event(copy);
#endif
    return result;
}
static struct WatchEntry *save_watch(Watch cb, void *data) {
    pthread_mutex_lock(&watch_lock);
    struct WatchEntry *w = NULL;
    for (int i=0;i<16;++i) if (!watches[i].callback) {
        w=&watches[i]; *w=(struct WatchEntry){cb,data,true}; break;
    }
    pthread_mutex_unlock(&watch_lock);
    Dl_info info={0}; dladdr((void *)cb,&info);
    record("WATCH_REGISTER callback=%p image=%s wrapped=%d", (void *)cb,
           info.dli_fname ? info.dli_fname : "?", w!=NULL);
    return w;
}
#if BROOMM_SDL_MAJOR == 3
static bool add_watch_hook(Watch cb, void *data) {
    struct WatchEntry *w=save_watch(cb,data);
    return real_add_watch(w?watch_thunk:cb,w?(void *)w:data);
}
#else
static void add_watch_hook(Watch cb, void *data) {
    struct WatchEntry *w=save_watch(cb,data);
    real_add_watch(w?watch_thunk:cb,w?(void *)w:data);
}
#endif
static void del_watch_hook(Watch cb, void *data) {
    struct WatchEntry *w=NULL;
    for (int i=0;i<16;++i) if (watches[i].callback==cb && watches[i].userdata==data && watches[i].active) {
        w=&watches[i]; w->active=false; break;
    }
    real_del_watch(w?watch_thunk:cb,w?(void *)w:data);
    // Keep callback storage alive: SDL may still be completing a callback.
}

// The layout below is SDL 3.4's published virtual joystick ABI, not copied SDL code.
struct VirtualDesc {
    uint32_t version;
    uint16_t type,padding,vendor,product,axes,buttons,balls,hats,touchpads,sensors,padding2[2];
    uint32_t button_mask,axis_mask;
    const char *name;
    void *touchpad_descs,*sensor_descs,*userdata;
    void (*update)(void *), (*player)(void *,int);
    bool (*rumble)(void *,uint16_t,uint16_t), (*rumble_triggers)(void *,uint16_t,uint16_t);
    bool (*led)(void *,uint8_t,uint8_t,uint8_t), (*effect)(void *,const void *,int);
    bool (*enable_sensors)(void *,bool);
    void (*cleanup)(void *);
};
_Static_assert(sizeof(struct VirtualDesc)==136,"SDL3 descriptor ABI");

static bool attach_fixtures(void) {
    fixture_call=true;
    for(int i=0;i<(getenv("BROOMM_SESSION")?4:2);++i) {
#if BROOMM_SDL_MAJOR == 3
        struct VirtualDesc desc={.version=sizeof(desc),.type=1,.vendor=0x1209,
            .product=(uint16_t)(0xb001+i),.axes=6,.buttons=21,.hats=1,
            .button_mask=0x1fffff,.axis_mask=0x3f,.name=(const char *[]){"Broomm Probe A","Broomm Probe B","Broomm Probe C","Broomm Probe D"}[i]};
        uint32_t (*attach)(const struct VirtualDesc *)=symbol("SDL_AttachVirtualJoystick");
        void *(*open)(uint32_t)=symbol("SDL_OpenJoystick");
        void *(*open_pad)(uint32_t)=symbol("SDL_OpenGamepad");
        if(!attach||!open||!open_pad) return false;
        uint32_t id=attach(&desc);
        joy[i]=open(id); pad[i]=open_pad(id);
#else
        int (*attach)(int,int,int,int)=symbol("SDL_JoystickAttachVirtual");
        void *(*open)(int)=symbol("SDL_JoystickOpen");
        void *(*open_pad)(int)=symbol("SDL_GameControllerOpen");
        if(!attach||!open||!open_pad) return false;
        int index=attach(1,6,21,1);
        if(index<0){const char *(*error)(void)=symbol("SDL_GetError");record("VIRTUAL_ATTACH_FAILED error=%s",error?error():"unknown");}
        joy[i]=open(index); pad[i]=open_pad(index);
#endif
        if(joy[i]) ids[i]=joystick_id(joy[i]);
        record("FIXTURE index=%d id=%u joystick=%p gamepad=%p",i,ids[i],joy[i],pad[i]);
        struct Guid {uint8_t bytes[16];};
#if BROOMM_SDL_MAJOR == 3
        struct Guid (*guid_fn)(void *)=symbol("SDL_GetJoystickGUID");
        const char *(*name_fn)(void *)=symbol("SDL_GetJoystickName");
        struct Guid guid=guid_fn(joy[i]);
#else
        struct Guid (*guid_fn)(void *)=symbol("SDL_JoystickGetGUID");
        const char *(*name_fn)(void *)=symbol("SDL_JoystickName");
        struct Guid guid=guid_fn(joy[i]);
#endif
        char hex[33];for(int b=0;b<16;++b)snprintf(hex+b*2,3,"%02x",guid.bytes[b]);
        record("FIXTURE_IDENTITY index=%d name=%s guid=%s",i,name_fn(joy[i]),hex);
        if(!joy[i]||!pad[i]||ids[i]==UINT32_MAX) {fixture_call=false;return false;}
    }
    fixture_call=false;return true;
}


static void install_hooks(void) {
    pad_joystick=symbol(PAD_JOY_NAME);joystick_id=symbol(JOY_ID_NAME);
    hook(BUTTON_NAME,(void *)button_hook,(void **)&real_button);
    hook(JOY_BUTTON_NAME,(void *)joy_button_hook,(void **)&real_joy_button);
    hook(AXIS_NAME,(void *)axis_hook,(void **)&real_axis);
    hook(JOY_AXIS_NAME,(void *)joy_axis_hook,(void **)&real_joy_axis);
    hook("SDL_PollEvent",(void *)poll_hook,(void **)&real_poll);
    hook("SDL_PeepEvents",(void *)peep_hook,(void **)&real_peep);
    hook("SDL_WaitEventTimeout",(void *)wait_hook,(void **)&real_wait);
    hook("SDL_WaitEvent",(void *)wait_forever_hook,(void **)&real_wait_forever);
#if BROOMM_SDL_MAJOR == 3
    (void)ryu_close_pad;
    hook("SDL_OpenGamepad",(void *)open_pad_hook,(void **)&real_open_pad);
    hook("SDL_OpenJoystick",(void *)open_joy_hook,(void **)&real_open_joy);
#else
    hook("SDL_GameControllerOpen",(void *)open_pad_hook,(void **)&real_open_pad);
    hook("SDL_JoystickOpen",(void *)open_joy_hook,(void **)&real_open_joy);
#endif
    hook("SDL_AddEventWatch",(void *)add_watch_hook,(void **)&real_add_watch);
#if BROOMM_SDL_MAJOR == 3
    hook("SDL_RemoveEventWatch",(void *)del_watch_hook,(void **)&real_del_watch);
#else
    hook("SDL_DelEventWatch",(void *)del_watch_hook,(void **)&real_del_watch);
#endif
#ifdef BROOMM_SESSION_BRIDGE
    if(getenv("BROOMM_SESSION"))install_motion_hooks();
#if BROOMM_SDL_MAJOR == 2
    install_sdl2_ports();
    if(getenv("BROOMM_RYUBING"))hook("SDL_GameControllerClose",ryu_close_pad,(void **)&ryu_real_close);
#endif
#endif
}

static uint32_t (*resolve_was_init(void))(uint32_t) {
    void *fn=symbol("SDL_WasInit");
    if(!fn)fn=symbol("SDL_WasInit_REAL");
    return fn;
}
static bool abi_valid;
static void initialize_dispatch(void) {
    // SDL_Init(0) resolves DynAPI without opening any subsystem. Some static
    // builds dead-strip unused public WasInit, while retaining its REAL target.
#if BROOMM_SDL_MAJOR == 3
    bool (*init)(uint32_t)=symbol("SDL_Init");
#else
    int (*init)(uint32_t)=symbol("SDL_Init");
#endif
    if(init)init(0);
#if BROOMM_SDL_MAJOR == 2
    // melonDS's static LTO build omits unused game-controller public stubs.
    // These three surviving stubs independently establish the same SDL2 table.
    const char *checks[]={JOY_BUTTON_NAME,JOY_AXIS_NAME,"SDL_GameControllerOpen"};
    // Eden's SDL2 LTO retains different public entry points. Still require
    // three independent stubs to agree on the same append-only ABI table.
    if(getenv("BROOMM_EDEN")) {
        checks[0]="SDL_GameControllerOpen";checks[1]="SDL_JoystickOpen";checks[2]="SDL_AddEventWatch";
    }
#else
    const char *checks[]={BUTTON_NAME,JOY_BUTTON_NAME,AXIS_NAME};
#endif
    void **candidate=NULL;
    bool valid=true;
    for(size_t i=0;i<3;++i) {
        void *public=symbol(checks[i]);
        void **slot=dispatch_slot(public);
        size_t index=0;bool known=false;
        for(size_t j=0;j<sizeof(known_slots)/sizeof(known_slots[0]);++j)
            if(!strcmp(known_slots[j].name,checks[i])) {index=known_slots[j].index;known=true;break;}
        if(!slot||!known) {valid=false;break;}
        void **base=slot-index;
        if(candidate&&candidate!=base) {valid=false;break;}
        candidate=base;
    }
    if(valid&&candidate) {api_table=candidate;record("DYNAPI_TABLE verified_base=%p checks=3",(void *)api_table);}
    else record("DYNAPI_TABLE_UNVERIFIED");
#if BROOMM_SDL_MAJOR == 3
    int (*version)(void)=symbol("SDL_GetVersion");
    int actual=version?version():0;record("SDL_VERSION value=%d",actual);
#else
    void (*version)(void *)=symbol("SDL_GetVersion");
    uint8_t v[3]={0};if(version)version(v);int actual=v[0]*10000+v[1]*100+v[2];record("SDL_VERSION value=%d.%d.%d",v[0],v[1],v[2]);
#endif
 const char *expected=getenv("BROOMM_EXPECT_SDL_VERSION");
 abi_valid=api_table&&(!expected||atoi(expected)==actual);
 if(!abi_valid)record("SESSION_FATAL native SDL ABI did not match the reviewed build");
}

