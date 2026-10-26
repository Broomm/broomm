// Broomm build-pinned macOS fixture; never a general emulator ABI promise.
// No SDL copy is loaded: resolve and patch the emulator's own initialized DynAPI.
#define _DARWIN_C_SOURCE
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <math.h>

// AppKit returns NSRect indirectly on Intel; casting objc_msgSend as on ARM
// corrupts the receiver/return storage under Rosetta.
static CGRect objc_rect(id object,SEL selector) {
#if defined(__x86_64__)
    CGRect result;
    ((void(*)(CGRect *,id,SEL))objc_msgSend_stret)(&result,object,selector);
    return result;
#else
    return ((CGRect(*)(id,SEL))objc_msgSend)(object,selector);
#endif
}

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
#include "abi_slots.h"
static void **api_table;
static void **api_slot(const char *name) {
    if(!api_table)return NULL;
    for(size_t i=0;i<sizeof(known_slots)/sizeof(known_slots[0]);++i)
        if(!strcmp(known_slots[i].name,name))return api_table+known_slots[i].index;
    return NULL;
}
static uint32_t executable_index(void) {
    for(uint32_t i=0;i<_dyld_image_count();++i)
        if(_dyld_get_image_header(i)->filetype==MH_EXECUTE)return i;
    abort();
}

static void record(const char *format, ...) {
    pthread_mutex_lock(&log_lock);
    if(log_file&&ftello(log_file)>=1024*1024) {
        fclose(log_file);log_file=NULL;
        char from[4096],to[4096];
        for(int i=9;i>=1;--i) {
            snprintf(to,sizeof(to),"%s.%d",log_path,i);
            if(i==9)unlink(to);
            if(i==1)snprintf(from,sizeof(from),"%s",log_path);
            else snprintf(from,sizeof(from),"%s.%d",log_path,i-1);
            rename(from,to);
        }
        log_file=fopen(log_path,"a");
    }
    if(!log_file) {
        fprintf(stderr,"Broomm probe: log unavailable\n");
        log_file=fopen(log_path,"a");
        if(!log_file){pthread_mutex_unlock(&log_lock);return;}
    }
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    fprintf(log_file, "%lld.%03ld pid=%d ", (long long)ts.tv_sec, ts.tv_nsec / 1000000,getpid());
    va_list args;
    va_start(args, format);
    vfprintf(log_file, format, args);
    va_end(args);
    fputc('\n', log_file);
    fflush(log_file);
    pthread_mutex_unlock(&log_lock);
}

static void *symbol(const char *name) {
    void *found=dlsym(sdl,name);
    if(found)return found;
    void **entry=api_slot(name);
    if(entry)return __atomic_load_n(entry,__ATOMIC_ACQUIRE);
    for(size_t i=0;i<symbol_count;++i)
        if(!strcmp(symbol_entries[i].name,name))return (void *)symbol_entries[i].address;
    char real_name[200];snprintf(real_name,sizeof(real_name),"%s_REAL",name);
    for(size_t i=0;i<symbol_count;++i)
        if(!strcmp(symbol_entries[i].name,real_name))return (void *)symbol_entries[i].address;
    // Static SDL's public stubs can have local Mach-O visibility. These symbols
    // exist in these inspected binaries but dlsym intentionally cannot see them.
    uint32_t image=executable_index();
    const struct mach_header_64 *header=(const void *)_dyld_get_image_header(image);
    intptr_t slide=_dyld_get_image_vmaddr_slide(image);
    const struct load_command *lc=(const void *)(header+1);
    const struct symtab_command *symtab=NULL;
    uintptr_t linkedit=0;
    for(uint32_t i=0;i<header->ncmds;++i) {
        if(lc->cmd==LC_SYMTAB)symtab=(const void *)lc;
        if(lc->cmd==LC_SEGMENT_64) {
            const struct segment_command_64 *seg=(const void *)lc;
            if(!strcmp(seg->segname,"__LINKEDIT"))linkedit=seg->vmaddr+slide-seg->fileoff;
        }
        lc=(const void *)((const char *)lc+lc->cmdsize);
    }
    if(!symtab||!linkedit)return NULL;
    const struct nlist_64 *entries=(const void *)(linkedit+symtab->symoff);
    const char *strings=(const void *)(linkedit+symtab->stroff);
    for(uint32_t i=0;i<symtab->nsyms;++i) {
        if((entries[i].n_type&N_TYPE)!=N_SECT)continue;
        uint32_t off=entries[i].n_un.n_strx;
        if(off>=symtab->strsize)continue;
        const char *candidate=strings+off;
        if(candidate[0]=='_'&&!strcmp(candidate+1,name))return (void *)(entries[i].n_value+slide);
    }
    return NULL;
}

// Validate the inspected public dispatch stub before touching its writable
// DynAPI slot. The emulator executable and bundled SDL are pinned separately.
static void **dispatch_slot(void *function) {
    if (!function) return NULL;
#if defined(__x86_64__)
    const uint8_t *p=function;
    // RPCS3 d08d568d's SDL3: frame prologue, RIP-relative MOV to RAX,
    // frame epilogue and indirect jump. Some void stubs use JMP [RIP+disp32].
    if(memcmp(p,"\x55\x48\x89\xe5",4))return NULL;
    int32_t displacement;
    if(!memcmp(p+4,"\x48\x8b\x05",3)&&!memcmp(p+11,"\x5d\xff\xe0",3)) {
        memcpy(&displacement,p+7,4);
        return (void **)(p+11+displacement);
    }
    if(!memcmp(p+4,"\x5d\xff\x25",3)) {
        memcpy(&displacement,p+7,4);
        return (void **)(p+11+displacement);
    }
    return NULL;
#elif defined(__arm64__)
    uint32_t a, l, b;
    memcpy(&a, function, 4); memcpy(&l, (char *)function + 4, 4);
    memcpy(&b, (char *)function + 8, 4);
    // PPSSPP 1.20.4's bundled SDL2 framework: Apple's linker relaxes the
    // page load into NOP + PC-relative 64-bit literal LDR + BR. Keep the
    // opcode/register checks, and independently verify the common table below.
    if(a==0xd503201f && (l&0xff000000)==0x58000000 &&
       (b&0xfffffc1f)==0xd61f0000 && ((b>>5)&31)==(l&31)) {
        int64_t displacement=(l>>5)&0x7ffff;
        if(displacement&(1<<18))displacement-=1<<19;
        return (void **)((uintptr_t)function+4+displacement*4);
    }
    if ((a & 0x9f000000) != 0x90000000 ||
        (l & 0xffc00000) != 0xf9400000 ||
        (b & 0xfffffc1f) != 0xd61f0000 ||
        ((l >> 5) & 31) != (a & 31) ||
        ((b >> 5) & 31) != (l & 31)) return NULL;
    int64_t pages = (((a >> 5) & 0x7ffff) << 2) | ((a >> 29) & 3);
    if (pages & (1 << 20)) pages -= 1 << 21;
    uintptr_t page = ((uintptr_t)function & ~(uintptr_t)4095) + pages * 4096;
    return (void **)(page + ((l >> 10) & 0xfff) * 8);
#else
    return NULL;
#endif
}

static bool hook(const char *name, void *replacement, void **original) {
    void *fn = symbol(name);
    void **slot = dispatch_slot(fn);
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
#ifdef BROOMM_SESSION_BRIDGE
#include "../../../native/sdl2_ports.inc"
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
static bool poll_hook(void *e) { bool r = real_poll(e); if (r) remap_event(e,"poll"); return r; }
static bool wait_hook(void *e, int ms) { bool r = real_wait(e,ms); if (r) remap_event(e,"wait"); return r; }
static bool wait_forever_hook(void *e) { bool r=real_wait_forever(e);if(r)remap_event(e,"wait_forever");return r; }
#else
static int poll_hook(void *e) { int r = real_poll(e); if (r) remap_event(e,"poll"); return r; }
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

static void update_fixtures(int tick) {
    void (*lock)(void)=symbol("SDL_LockJoysticks");
    void (*unlock)(void)=symbol("SDL_UnlockJoysticks");
#if BROOMM_SDL_MAJOR == 3
    bool (*set_button)(void *,int,bool)=symbol("SDL_SetJoystickVirtualButton");
    bool (*set_axis)(void *,int,int16_t)=symbol("SDL_SetJoystickVirtualAxis");
    void (*update)(void)=symbol("SDL_UpdateJoysticks");
#else
    int (*set_button)(void *,int,uint8_t)=symbol("SDL_JoystickSetVirtualButton");
    int (*set_axis)(void *,int,int16_t)=symbol("SDL_JoystickSetVirtualAxis");
    void (*update)(void)=symbol("SDL_JoystickUpdate");
#endif
    if(!set_button||!set_axis||!update) return;
    if(lock&&unlock)lock();
    // Repeated edges exercise event-cache consumers as well as polling consumers.
    for(int i=0;i<2;++i) {
        set_button(joy[i],0,(tick&1)?(i==0):false);
        set_button(joy[i],1,(tick&1)?(i==1):false);
        set_axis(joy[i],0,(tick&1)?(i?-23456:12345):0);
    }
    update();
    if(tick&1) {
        fixture_call=true;
        Button (*button)(void *,int)=symbol(BUTTON_NAME);
        int16_t (*axis)(void *,int)=symbol(AXIS_NAME);
        int mode=atomic_load(&policy);
        int b=button(pad[0],0), a=axis(pad[0],0);
        int expected_b=mode==0?1:0, expected_a=mode==2?-23456:12345;
        record("SELF_CHECK mode=%d raw_a0=%d delivered_a0=%d raw_axis=%d delivered_axis=%d pass=%d",
            mode,(int)real_button(pad[0],0),b,(int)real_axis(pad[0],0),a,
            b==expected_b && a==expected_a);
        fixture_call=false;
    }
    if(lock&&unlock)unlock();
}

// AppKit view is deliberately separate from renderer hooking. This proves only
// an in-process native view; fullscreen/render-backend acceptance is a later check.
static id overlay;
static id send0(id obj,const char *sel);
static int appkit_pause_applied;
static void send_f5(id window,int type) {
    id app=send0((id)objc_getClass("NSApplication"),"sharedApplication");
    id chars=((id(*)(id,SEL,const char *))objc_msgSend)((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"\xef\x9c\x88");
    long number=((long(*)(id,SEL))objc_msgSend)(window,sel_registerName("windowNumber"));
    id event=((id(*)(id,SEL,unsigned long,CGPoint,unsigned long,double,long,id,id,id,bool,unsigned short))objc_msgSend)(
        (id)objc_getClass("NSEvent"),sel_registerName("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        (unsigned long)type,CGPointMake(0,0),0,0,number,NULL,chars,chars,false,96);
    ((void(*)(id,SEL,id))objc_msgSend)(app,sel_registerName("sendEvent:"),event);
    record("APPKIT_F5 type=%d window=%ld",type,number);
}
static void release_f5(void *window) {send_f5((id)window,11);}
static _Atomic int menu_requested, pause_requested;
static void *qt_main;
static void *melonds_thread(void) {
    if(!getenv("BROOMM_MELONDS")||!qt_main)return NULL;
    static const uint32_t *pause;
    if(!pause)pause=symbol("_ZN10MainWindow7onPauseEb");
    // Official 1.1 macOS ARM64, additionally locked to its executable hash in
    // Dart. Guard both native object accesses against their actual instructions.
    if(!pause||pause[8]!=0xf9404814||pause[9]!=0x3940e288)return NULL;
    return *(void **)((char *)qt_main+0x90);
}
static void *core_system_fn, *core_state_fn, *core_set_state_fn;
static uint32_t *rpcs_status;
static uint32_t *rpcs_ftotal, *rpcs_fdone, *rpcs_ptotal, *rpcs_pdone;
static uint64_t *rpcs_ftotal_bits, *rpcs_fknown_bits;
static int qt_pause_applied;
struct QtArray {void *allocation;void **data;long size;};
struct QtString {void *allocation;const uint16_t *data;long size;};
static bool azahar_game_loaded(void) {
    static bool resolved;
    static const uint32_t *complete;
    static bool (*visible_to)(const void *,const void *);
    if(!resolved) {
        complete=symbol("_ZN11GMainWindow14OnLoadCompleteEv");
        visible_to=dlsym(RTLD_DEFAULT,"_ZNK7QWidget11isVisibleToEPKS_");
        resolved=true;
    }
    // Pinned 2126.1.2 loads LoadingScreen* at +0x70, then its fade
    // animation at +0x48. EmuThread exists before shader loading finishes.
    if(!qt_main||!complete||!visible_to||complete[4]!=0xf9403808||complete[5]!=0xf9402500||
       !*(uint8_t *)((char *)qt_main+0x111)||!*(void **)((char *)qt_main+0x118))return false;
    void *loading=*(void **)((char *)qt_main+0x70);
    // Compare to the owning window so minimizing it is not mistaken for load
    // completion. LoadingScreen hides only after its completion animation.
    return loading&&!visible_to(loading,qt_main);
}
static void qt_tick(void) {
    struct QtArray (*top_levels)(void)=(getenv("BROOMM_MELONDS")||getenv("BROOMM_EDEN"))?symbol("_ZN12QApplication15topLevelWidgetsEv"):dlsym(RTLD_DEFAULT,"_ZN12QApplication15topLevelWidgetsEv");
    if(!top_levels)return;
    // These concrete classes live in the pinned main executable. Missing class
    // methods cannot appear later; avoid repeated full Mach-O scans at 15 Hz.
    static bool metas_resolved;
    static void *main_meta,*rpcs_meta,*dolphin_meta;
    if(!metas_resolved) {
        main_meta=symbol("_ZNK11GMainWindow10metaObjectEv");
        rpcs_meta=symbol("_ZNK11main_window10metaObjectEv");
        dolphin_meta=symbol("_ZNK10MainWindow10metaObjectEv");
        metas_resolved=true;
    }
    void *message_meta=getenv("BROOMM_EDEN")?symbol("_ZNK11QMessageBox10metaObjectEv"):dlsym(RTLD_DEFAULT,"_ZNK11QMessageBox10metaObjectEv");
    struct QtString (*message_text)(void *)=getenv("BROOMM_EDEN")?symbol("_ZNK11QMessageBox4textEv"):dlsym(RTLD_DEFAULT,"_ZNK11QMessageBox4textEv");
    void *(*new_object)(size_t)=dlsym(RTLD_DEFAULT,"_Znwm");
    void (*close_constructor)(void *)=dlsym(RTLD_DEFAULT,"_ZN11QCloseEventC1Ev");
    void (*post_event)(void *,void *,int)=dlsym(RTLD_DEFAULT,"_ZN16QCoreApplication9postEventEP7QObjectP6QEventi");
    struct QtArray widgets=qt_main?(struct QtArray){0}:top_levels();
    if(widgets.size<0||widgets.size>128)return;
    for(long i=0;i<widgets.size;++i) {
        void *w=widgets.data[i];if(!w)continue;
        void **vtable=*(void ***)w;
        if((main_meta&&vtable[0]==main_meta)||(rpcs_meta&&vtable[0]==rpcs_meta)||(dolphin_meta&&vtable[0]==dolphin_meta)) {
            if(!qt_main)record("QT_MAIN_WINDOW object=%p",w);
            qt_main=w;
        }
        if(message_meta&&vtable[0]==message_meta&&message_text) {
            struct QtString text=message_text(w);
            char ascii[1024];long n=text.size;
            if(n<0||n>=1024)continue;
            for(long c=0;c<n;++c)ascii[c]=text.data[c]<128?(char)text.data[c]:'?';
            ascii[n]=0;record("QT_MESSAGE text=%s",ascii);
            // This exact startup warning blocks ROM loading for a directly
            // launched private Azahar. Never auto-dismiss game or load errors.
            if(new_object&&close_constructor&&post_event&&strstr(ascii,"executable is being run directly")) {
                void *event=new_object(256);close_constructor(event);post_event(w,event,0);
                record("QT_QUEUE_CLOSE_TERMINAL_WARNING");
            }
        }
    }
    // QtArray/QString temporary references are intentionally retained in this
    // short-lived C ABI experiment. A production adapter needs ownership-safe ABI.
    int wanted=atomic_load(&pause_requested);
    void *melon=melonds_thread();
    if(melon&&__atomic_load_n((uint8_t *)melon+0x38,__ATOMIC_ACQUIRE)) {
        uint32_t state=__atomic_load_n((uint32_t *)((char *)melon+0x34),__ATOMIC_ACQUIRE);
        if((state==1||state==2)&&((state==2)!=wanted)) {
            void (*pause)(void *,bool)=symbol("_ZN10MainWindow7onPauseEb");
            pause(qt_main,wanted!=0);
            record("MELONDS_PAUSE before=%u requested=%d after=%u",state,wanted,__atomic_load_n((uint32_t *)((char *)melon+0x34),__ATOMIC_ACQUIRE));
        }
    }
    if(qt_main&&main_meta&&qt_pause_applied!=wanted) {
        void (*pause)(void *)=symbol("_ZN11GMainWindow11OnPauseGameEv");
        void (*resume)(void *,bool)=symbol("_ZN11GMainWindow12OnResumeGameEb");
        if(pause&&resume) {
            if(getenv("BROOMM_SESSION")) {
                const uint32_t *resume_code=(const void *)resume;
                // 2126.1.2: OnResumeGame loads EmuThread* at this+0x118.
                // A frame-limiter flag exists before any game: it is NOT ready.
                const uint32_t *continue_code=symbol("_ZN11GMainWindow19OnPauseContinueGameEv");
                if(resume_code[15]!=0xf9408e75||!continue_code||continue_code[0]!=0x39444408||
                   !*(uint8_t *)((char *)qt_main+0x111)||!*(void **)((char *)qt_main+0x118))return;
                if(wanted&&!azahar_game_loaded())return;
            }
            uint32_t *code=(void *)pause;
            uint8_t *frame_advancing=NULL;
            // The inspected 2126.1.2 arm64 method loads System& at +0x48,
            // then atomically exchanges the FrameLimiter flag at System+0x20.
            // Reject a changed instruction layout instead of guessing offsets.
            if(code[4]==0xf9402408 && code[5]==0x91008108)
                frame_advancing=(uint8_t *)*(void **)((char *)qt_main+0x48)+0x20;
            int before=frame_advancing?__atomic_load_n(frame_advancing,__ATOMIC_ACQUIRE):-1;
            if(wanted)pause(qt_main);else resume(qt_main,false);
            int after=frame_advancing?__atomic_load_n(frame_advancing,__ATOMIC_ACQUIRE):-1;
            qt_pause_applied=wanted;record("QT_PAUSE_CALLED value=%d before_frame_advancing=%d after_frame_advancing=%d",wanted,before,after);
        }
    }
    if(qt_main&&rpcs_meta&&qt_pause_applied!=wanted) {
        void (*toggle)(void *)=symbol("_ZN11main_window13OnPlayOrPauseEv");
        if(toggle){
            int before=rpcs_status?(int)__atomic_load_n(rpcs_status,__ATOMIC_ACQUIRE):-1;
            if(before!=3&&before!=4) {record("QT_PAUSE_NOT_READY raw_state=%d",before);return;}
            if((wanted&&before==3)||(!wanted&&before==4))toggle(qt_main);
            int after=rpcs_status?(int)__atomic_load_n(rpcs_status,__ATOMIC_ACQUIRE):-1;
            qt_pause_applied=wanted;record("QT_PAUSE_TOGGLED value=%d raw_before=%d raw_after=%d",wanted,before,after);
        }
    }
}
static id send0(id obj,const char *sel) { return ((id(*)(id,SEL))objc_msgSend)(obj,sel_registerName(sel)); }
static void draw_overlay(id self,SEL selector,CGRect dirty) {
    (void)selector;(void)dirty;
    id ctx=send0((id)objc_getClass("NSGraphicsContext"),"currentContext");
    CGContextRef cg=((CGContextRef(*)(id,SEL))objc_msgSend)(ctx,sel_registerName("CGContext"));
    CGContextSetRGBFillColor(cg,0.04,0.08,0.15,0.96);
    CGContextFillRect(cg,CGRectMake(0,0,520,135));
    char message[160]; snprintf(message,sizeof(message),"Broomm injected probe   |   input mode %d",atomic_load(&policy));
    CFStringRef text=CFStringCreateWithCString(NULL,message,kCFStringEncodingUTF8);
    CTFontRef font=CTFontCreateWithName(CFSTR("Helvetica"),19,NULL);
    CGColorRef white=CGColorCreateGenericRGB(1,1,1,1);
    const void *keys[]={kCTFontAttributeName,kCTForegroundColorAttributeName};
    const void *values[]={font,white};
    CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef string=CFAttributedStringCreate(NULL,text,attrs);
    CTLineRef line=CTLineCreateWithAttributedString(string);
    CGContextSetTextPosition(cg,18,65); CTLineDraw(line,cg);
    CFRelease(line);CFRelease(string);CFRelease(attrs);CGColorRelease(white);CFRelease(font);CFRelease(text);
    uint64_t n=atomic_fetch_add(&draws,1);
    if(n<5) record("OVERLAY_DRAW view=%p count=%llu",(void *)self,(unsigned long long)n+1);
}
static void ui_tick(void *unused) {
    (void)unused;
    qt_tick();
    if(core_system_fn && core_state_fn && core_set_state_fn) {
        void *system=((void *(*)(void))core_system_fn)();
        int before=((int(*)(void *))core_state_fn)(system);
        int wanted=atomic_load(&pause_requested)?1:2;
        if((before==1||before==2)&&before!=wanted)
            ((void(*)(void *,int,bool,bool))core_set_state_fn)(system,wanted,true,false);
        int after=((int(*)(void *))core_state_fn)(system);
        record("CORE_STATE before=%d requested=%d after=%d",before,wanted,after);
    }
    if(!menu_requested) return;
    id app=send0((id)objc_getClass("NSApplication"),"sharedApplication");
    id window=send0(app,"mainWindow");
    if(!window) window=send0(app,"keyWindow");
    if(window) {
        id title=send0(window,"title");
        const char *s=((const char *(*)(id,SEL))objc_msgSend)(title,sel_registerName("UTF8String"));
        if(s&&strstr(s,"ContentDialogOverlay"))window=NULL;
    }
    if(!window) {
        id windows=send0(app,"windows");
        unsigned long count=((unsigned long(*)(id,SEL))objc_msgSend)(windows,sel_registerName("count"));
        double largest=0;
        for(unsigned long i=0;i<count;++i) {
            id candidate=((id(*)(id,SEL,unsigned long))objc_msgSend)(windows,sel_registerName("objectAtIndex:"),i);
            id content=send0(candidate,"contentView");
            id title=send0(candidate,"title");
            const char *s=((const char *(*)(id,SEL))objc_msgSend)(title,sel_registerName("UTF8String"));
            if(s&&strstr(s,"ContentDialogOverlay"))continue;
            CGRect bounds=objc_rect(content,sel_registerName("bounds"));
            double area=bounds.size.width*bounds.size.height;
            if(area>largest) {window=candidate;largest=area;}
        }
    }
    if(!window) {record("OVERLAY_NO_WINDOW");return;}
    id title=send0(window,"title");
    const char *title_text=((const char *(*)(id,SEL))objc_msgSend)(title,sel_registerName("UTF8String"));
    record("WINDOW_TITLE value=%s",title_text?title_text:"");
    int desired_pause=atomic_load(&pause_requested);
    if(getenv("BROOMM_PAUSE_APPKIT_F5")&&desired_pause!=appkit_pause_applied) {
        ((void(*)(id,SEL))objc_msgSend)(window,sel_registerName("makeKeyWindow"));
        send_f5(window,10);
        dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),(void *)window,release_f5);
        appkit_pause_applied=desired_pause;
    }
    if(!overlay) {
        Class cls=objc_allocateClassPair(objc_getClass("NSView"),"BroommProbeView",0);
        if(!cls) cls=objc_getClass("BroommProbeView");
        else {class_addMethod(cls,sel_registerName("drawRect:"),(IMP)draw_overlay,"v@:{CGRect={CGPoint=dd}{CGSize=dd}}");objc_registerClassPair(cls);}
        id allocated=send0((id)cls,"alloc");
        overlay=((id(*)(id,SEL,CGRect))objc_msgSend)(allocated,sel_registerName("initWithFrame:"),CGRectMake(24,24,520,135));
        id content=send0(window,"contentView");
        ((void(*)(id,SEL,id))objc_msgSend)(content,sel_registerName("addSubview:"),overlay);
        record("OVERLAY_ATTACHED window=%p content=%p view=%p",(void *)window,(void *)content,(void *)overlay);
    }
    ((void(*)(id,SEL,bool))objc_msgSend)(overlay,sel_registerName("setNeedsDisplay:"),true);
}

#ifdef BROOMM_SESSION_BRIDGE
static void install_motion_hooks(void);
#endif
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
#endif
#endif
}

static uint32_t (*resolve_was_init(void))(uint32_t) {
    void *fn=symbol("SDL_WasInit");
    if(!fn)fn=symbol("SDL_WasInit_REAL");
    return fn;
}
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
    if(version)record("SDL_VERSION value=%d",version());
#else
    void (*version)(void *)=symbol("SDL_GetVersion");
    uint8_t v[3]={0};if(version){version(v);record("SDL_VERSION value=%d.%d.%d",v[0],v[1],v[2]);}
#endif
}

#ifdef BROOMM_SESSION_BRIDGE
#include "../../../native/session.inc"
#endif

static void *worker(void *unused) {
    (void)unused;
    const char *library=getenv("BROOMM_SDL_LIBRARY");
    if(!sdl) {
        for(int attempt=0;attempt<1200&&!sdl;++attempt) {
            sdl=library?dlopen(library,RTLD_NOW|RTLD_NOLOAD):RTLD_DEFAULT;
            if(!sdl) usleep(50000);
        }
        if(!sdl) {record("SDL_NOT_LOADED");return NULL;}
        initialize_dispatch();
        uint32_t (*was_init)(uint32_t)=resolve_was_init();
        if(!was_init) {record("SDL_MISSING_WAS_INIT");return NULL;}
        was_init(0);install_hooks();
    }
    uint32_t (*was_init)(uint32_t)=resolve_was_init();
    for(int attempt=0;attempt<1200;++attempt) {
        if(was_init(0)&0x200) break;
        usleep(50000);
    }
    record("SDL_READY flags=0x%x",was_init(0));
    #ifdef BROOMM_SESSION_BRIDGE
    if(getenv("BROOMM_SESSION")) {session_worker();return NULL;}
#endif
    bool fixtures=getenv("BROOMM_VIRTUAL_PADS") && attach_fixtures();
    for(int tick=0;tick<1200;++tick) {
        int mode=0,menu=0,pause=0;
        FILE *f=control_path?fopen(control_path,"r"):NULL;
        if(f) {if(fscanf(f,"%d %d %d",&mode,&menu,&pause)<2) mode=menu=0;fclose(f);}
        if(mode<0||mode>2) mode=0;
        if(mode!=atomic_load(&policy)) record("POLICY old=%d new=%d",atomic_load(&policy),mode);
        atomic_store(&policy,mode); menu_requested=menu;pause_requested=pause;
        if(fixtures)update_fixtures(tick);
        if(tick%4==0) {
            record("COUNTERS query=%llu changed=%llu events=%llu watched=%llu draws=%llu",
                (unsigned long long)atomic_load(&queries),(unsigned long long)atomic_load(&changed),
                (unsigned long long)atomic_load(&events),(unsigned long long)atomic_load(&watcher_events),
                (unsigned long long)atomic_load(&draws));
            dispatch_async_f(dispatch_get_main_queue(),NULL,ui_tick);
        }
        usleep(500000);
    }
    return NULL;
}

#ifdef BROOMM_SESSION_BRIDGE
#include "../../../native/ownership.inc"
#include "../../../native/eden_probe.inc"
#include "../../../native/ppsspp_storage.inc"
#endif
__attribute__((constructor)) static void start(void) {
#ifdef BROOMM_SESSION_BRIDGE
    if(eden_vulkan_probe())return;
    if(getenv("BROOMM_SESSION"))acquire_session_writer();
#endif
    const char *path=getenv("BROOMM_PROBE_LOG");
    if(!path) return;
    log_path=path;
    log_file=fopen(path,"a");if(!log_file)return;
    control_path=getenv("BROOMM_PROBE_CONTROL");
    record("INJECTED pid=%d sdl_major=%d",getpid(),BROOMM_SDL_MAJOR);
    const char *status=getenv("BROOMM_EMU_STATUS");
    if(status)rpcs_status=(void *)(strtoull(status,NULL,16)+_dyld_get_image_vmaddr_slide(executable_index()));
    const char *symbol_path=getenv("BROOMM_SYMBOL_FILE");
    FILE *symbols=symbol_path?fopen(symbol_path,"r"):NULL;
    if(symbols) {
        unsigned long long address;char name[160];
        while(symbol_count<4000&&fscanf(symbols,"%llx %159s",&address,name)==2) {
            struct SymbolEntry *e=&symbol_entries[symbol_count++];
            memcpy(e->name,name,strlen(name)+1);e->address=address+_dyld_get_image_vmaddr_slide(executable_index());
        }
        fclose(symbols);record("LOCAL_SYMBOLS count=%zu",symbol_count);
    }
    if(rpcs_status) {
        rpcs_ftotal=symbol("g_progr_ftotal"); rpcs_fdone=symbol("g_progr_fdone");
        rpcs_ptotal=symbol("g_progr_ptotal"); rpcs_pdone=symbol("g_progr_pdone");
        rpcs_ftotal_bits=symbol("g_progr_ftotal_bits"); rpcs_fknown_bits=symbol("g_progr_fknown_bits");
        record("RPCS_LOADING_COUNTERS available=%d",rpcs_ftotal&&rpcs_fdone&&rpcs_ptotal&&rpcs_pdone&&rpcs_ftotal_bits&&rpcs_fknown_bits?1:0);
    }
    const char *system=getenv("BROOMM_CORE_SYSTEM"), *state=getenv("BROOMM_CORE_STATE"),
               *set_state=getenv("BROOMM_CORE_SET_STATE");
    if(system&&state&&set_state) {
        intptr_t slide=_dyld_get_image_vmaddr_slide(executable_index());
        core_system_fn=(void *)(strtoull(system,NULL,16)+slide);
        core_state_fn=(void *)(strtoull(state,NULL,16)+slide);
        core_set_state_fn=(void *)(strtoull(set_state,NULL,16)+slide);
    }
    const char *library=getenv("BROOMM_SDL_LIBRARY");
    // Libraries already linked at process startup can be patched before event
    // watchers register. Late-loaded Ryubing SDL is handled by the worker.
    sdl=library?dlopen(library,RTLD_NOW|RTLD_NOLOAD):RTLD_DEFAULT;
    if(sdl)initialize_dispatch();
    uint32_t (*was_init)(uint32_t)=sdl?resolve_was_init():NULL;
    if(was_init) {was_init(0);install_hooks();}
    else sdl=NULL;
    pthread_t thread;
    int error=pthread_create(&thread,NULL,worker,NULL);
    if(error)record("WORKER_FAILED error=%d",error);else pthread_detach(thread);
}
