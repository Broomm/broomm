// Existing, build-pinned PPSSPP interfaces. Dart owns the session workflow.
static _Atomic uint32_t psp_buttons;
static _Atomic int psp_test_key;
// BootState::Complete precedes EmuScreen's final main/render-thread setup.
// That setup writes CORE_RUNNING_CPU again. Wait for the actual frontend flags
// before publishing pairing, rather than losing the initial pause afterward.
static bool ppsspp_frontend_ready(void) {
#if defined(__arm64__)
    static bool finished,resolved,valid;
    static void **manager;static void *vtable;
    static bool (*try_lock)(void *);static void (*unlock)(void *);static int (*ui_state)(void);
    if(finished)return true;
    if(!resolved) {
        manager=symbol("g_screenManager");vtable=symbol("_ZTV9EmuScreen");
        try_lock=dlsym(RTLD_DEFAULT,"_ZNSt3__115recursive_mutex8try_lockEv");
        unlock=dlsym(RTLD_DEFAULT,"_ZNSt3__115recursive_mutex6unlockEv");
        ui_state=symbol("_Z10GetUIStatev");
        const uint32_t *key=symbol("_ZN13ScreenManager3keyERK8KeyInput"),*boot=symbol("_ZN9EmuScreen15ProcessGameBootERK4Path");
        valid=manager&&vtable&&try_lock&&unlock&&ui_state&&key&&boot&&
          key[6]==0x91002000&&key[8]==0xa9495676&&boot[9]==0x3943a008&&boot[11]==0x3948ae68;
        resolved=true;record("PPSSPP_FRONTEND_GUARD valid=%d",valid);
    }
    if(!valid||!*manager)return false;
    void *object=*manager,*mutex=(char *)object+8;
    if(!try_lock(mutex))return false;
    char *begin=*(char **)((char *)object+0x90),*end=*(char **)((char *)object+0x98);
    if(begin&&end>=begin&&(size_t)(end-begin)<=24*32&&(end-begin)%24==0) {
        for(char *p=begin;p<end;p+=24) {
            void *screen=*(void **)p;
            if(screen&&*(void **)screen==(char *)vtable+16&&
               !*(uint8_t *)((char *)screen+0xe8)&&!*(uint8_t *)((char *)screen+0x22b)&&ui_state()==2)finished=true;
        }
    }
    unlock(mutex);
    return finished;
#else
    return false;
#endif
}
static int ppsspp_tick(void) {
    if(!getenv("BROOMM_PPSSPP"))return -1;
    static bool resolved;
    static int (*boot)(void);
    static bool (*stepping)(void),(*inactive)(void),(*active)(void);
    static void (*pause_core)(int,uint32_t),(*resume_core)(void);
    static uint32_t (*buttons)(void);
    if(!resolved) {
        boot=symbol("_Z16PSP_GetBootStatev");
        stepping=symbol("_Z15Core_IsSteppingv");
        inactive=symbol("_Z15Core_IsInactivev");active=symbol("_Z13Core_IsActivev");
        pause_core=symbol("_Z10Core_Break11BreakReasonj");resume_core=symbol("_Z11Core_Resumev");
        buttons=symbol("_Z17__CtrlPeekButtonsv");resolved=true;
    }
    if(!boot||!stepping||!inactive||!active||!pause_core||!resume_core||boot()!=2||!ppsspp_frontend_ready())return -1;
    // Core_Break is explicitly asynchronous/free-threaded upstream. Wait for
    // its native pending-work flag to clear before acknowledging the pause.
    bool stopped=stepping()&&inactive();
    if(atomic_load(&session_wanted)) {
        if(!stopped&&active())pause_core(22,0); // BreakReason::UIPause, pinned v1.20.4.
    } else if(stopped)resume_core();
    if(buttons&&session_test)atomic_store(&psp_buttons,buttons());
    int key=atomic_exchange(&psp_test_key,0);
    if(session_test&&key) {
        int (*push)(void *)=symbol("SDL_PushEvent");
        if(push) {
            _Alignas(8) unsigned char event[56]={0};
            uint32_t type=0x300,scan=key==2?59:61,code=0x40000000u|scan;
            memcpy(event,&type,4);event[12]=1;memcpy(event+16,&scan,4);memcpy(event+20,&code,4);
            push(event);type=0x301;memcpy(event,&type,4);event[12]=0;push(event);
            record("PPSSPP_TEST_STATE_KEY action=%d",key);
        }
    }
    if(stepping()&&inactive())return 1;
    return active()&&!stepping()?0:-1;
}
