// Build-pinned Sony adapters. Qt methods queue to their owning emulation
// thread; acknowledgement always comes from the real native state afterward.
// Addresses come only from reviewed application assets, after Dart verifies
// the executable hash. This does not load or modify a system installation.
static _Atomic int sony_test_action;
static int playstation_tick(void) {
    if(!getenv("BROOMM_PLAYSTATION"))return -1;
    static bool resolved,duck;
    static void **thread;
    static uint8_t *duck_valid,*duck_paused;
    static uint32_t *ps2_state;
    static int (*get_state)(void);
    static void (*set_paused)(void *,bool);
    if(!resolved) {
        duck=getenv("BROOMM_DUCK_VALID")!=NULL;
        const char *address=getenv(duck?"BROOMM_DUCK_VALID":"BROOMM_PS2_STATE");
        intptr_t slide=_dyld_get_image_vmaddr_slide(executable_index());
        if(address) {
            uintptr_t p=(uintptr_t)strtoull(address,NULL,16)+slide;
            if(duck)duck_valid=(void *)p;else ps2_state=(void *)p;
        }
        const char *paused=getenv("BROOMM_DUCK_PAUSED");
        if(duck&&paused)duck_paused=(void *)(strtoull(paused,NULL,16)+slide);
        get_state=duck?NULL:symbol("_ZN9VMManager8GetStateEv");
        thread=symbol(duck?"g_core_thread":"g_emu_thread");
        set_paused=symbol(duck?"_ZN10CoreThread15setSystemPausedEb":"_ZN9EmuThread11setVMPausedEb");
        resolved=true;
        record("PLAYSTATION_ADAPTER duck=%d state=%p getter=%p thread=%p pause=%p",duck,
            duck?(void *)duck_valid:(void *)ps2_state,(void *)get_state,(void *)thread,(void *)set_paused);
    }
    if(!thread||!*thread||!set_paused||(duck&&(!duck_valid||!duck_paused))||(!duck&&!ps2_state&&!get_state))return -1;
    // DuckStation's core enum is not an atomic cross-thread interface. These
    // two fields are owned by this UI thread and updated by the native core's
    // started/paused/resumed notifications. PS2 exposes atomic VM state.
    int state=duck?(*duck_valid?(*duck_paused?3:2):0):
        get_state?get_state():(int)__atomic_load_n(ps2_state,__ATOMIC_ACQUIRE);
    if(state!=2&&state!=3)return -1;
    int wanted=atomic_load(&session_wanted),actual=state==3;
    static int requested=-1;
    if(actual==wanted)requested=-1;
    else if(requested!=wanted) {
        requested=wanted;set_paused(*thread,wanted!=0);
        record("PLAYSTATION_PAUSE requested=%d raw_before=%d",wanted,state);
    }
    int action=atomic_exchange(&sony_test_action,0);
    if(session_test&&action) {
        if(duck&&action==2) {
            void (*f)(void *,bool,int)=symbol("_ZN10CoreThread9saveStateEbi");
            if(f){f(*thread,false,1);record("PLAYSTATION_TEST_STATE action=%d",action);}
        } else if(!duck&&action==2) {
            void (*f)(void *,int)=symbol("_ZN9EmuThread15saveStateToSlotEi");
            if(f){f(*thread,1);record("PLAYSTATION_TEST_STATE action=2");}
        } else if(!duck) {
            void (*f)(void *,int,bool)=symbol("_ZN9EmuThread17loadStateFromSlotEib");
            if(f){f(*thread,1,false);record("PLAYSTATION_TEST_STATE action=3");}
        }
    }
    return actual;
}
