// Eden v0.2.1 macOS ARM64 only. Dart verifies the entire pinned executable.
// Offsets are independently checked against native methods' instructions and
// source; reads observe state. Only upstream methods mutate pause/input state.
static _Atomic uint64_t eden_program,eden_buttons;
static int eden_tick(void) {
    if(!getenv("BROOMM_EDEN"))return -1;
#if defined(__aarch64__)
    static bool resolved,valid;
    static void **main_window,**system;
    static void (*pause_game)(void *),(*start_game)(void *),(*connect_pad)(void *,bool),(*disconnect_pad)(void *);
    static void (*set_running)(void *,bool),(*update_menu)(void *);
    static bool (*visible_to)(void *,void *);
    static uint64_t (*pad_buttons)(void *);
    if(!resolved) {
        main_window=symbol("_ZN8QtCommon10rootObjectE");system=symbol("_ZN8QtCommon6systemE");
        pause_game=symbol("_ZN10MainWindow11OnPauseGameEv");start_game=symbol("_ZN10MainWindow11OnStartGameEv");
        set_running=symbol("_ZN9EmuThread10SetRunningEb");update_menu=symbol("_ZN10MainWindow15UpdateMenuStateEv");
        visible_to=symbol("_ZNK7QWidget11isVisibleToEPKS_");
        connect_pad=symbol("_ZN4Core3HID18EmulatedController7ConnectEb");
        disconnect_pad=symbol("_ZN4Core3HID18EmulatedController10DisconnectEv");
        pad_buttons=symbol("_ZNK4Core3HID18EmulatedController14GetNpadButtonsEv");
        const uint32_t *p=(const void *)pause_game,*l=symbol("_ZN10MainWindow14OnLoadCompleteEv"),*progress=symbol("_ZN13LoadingScreen14OnLoadProgressEN9VideoCore17LoadCallbackStageEmm");
        valid=p&&l&&progress&&progress[15]==0xb9405268&&p[4]==0xf940e000&&l[5]==0xf9404c08&&main_window&&system&&
            start_game&&set_running&&update_menu&&visible_to&&connect_pad&&disconnect_pad&&pad_buttons;
        resolved=true;record("EDEN_ADAPTER valid=%d",valid);
    }
    if(!valid||!*main_window||!*system)return -1;
    void *window=*main_window;qt_main=window;
    void *impl=*(void **)*system;
    // The native UI receives LoadCallbackStage::Complete after disk shader
    // resources finish. Its fade-out waits for a first frame, which a failing
    // game may never render. Native CPU pause acknowledgment remains required.
    if(!impl||!*(uint8_t *)((char *)window+0x1b8)||
       !*(void **)((char *)window+0x1c0))return -1;
    void *loading=*(void **)((char *)window+0x98);
    if(!loading||(*(uint32_t *)((char *)loading+0x50)!=2&&visible_to(loading,window)))return -1;
    uint8_t *state=(uint8_t *)impl+0x1ac2c0;
    if(!__atomic_load_n(state+2,__ATOMIC_ACQUIRE)||__atomic_load_n(state+1,__ATOMIC_ACQUIRE))return -1;
    bool paused=__atomic_load_n(state,__ATOMIC_ACQUIRE)!=0;
    bool wanted=atomic_load(&session_wanted)!=0;
    // Apply socket changes while the CPU is paused, then resume through the
    // owning native thread's interface. UI sleep/Discord/play-time callbacks
    // are not a pause acknowledgment and do not own this transition.
    unsigned int wanted_ports=atomic_load(&connected_ports),actual_ports=0;
    bool port_change=false;
    for(int p=0;p<10;++p) {
        void *pad=*(void **)((char *)impl+0x2d0+p*sizeof(void *));
        if(pad&&(__atomic_load_n((uint8_t *)pad+0x56,__ATOMIC_ACQUIRE)!=0)!=(p<4&&(wanted_ports&(1u<<p))))port_change=true;
    }
    void *thread=*(void **)((char *)window+0x1c0);
    if(!paused&&(wanted||port_change)) {
        set_running(thread,false);paused=__atomic_load_n(state,__ATOMIC_ACQUIRE)!=0;
        update_menu(window);record("EDEN_PAUSE requested=1 native=%d",paused);
    }
    for(int p=0;p<10;++p) {
        void *pad=*(void **)((char *)impl+0x2d0+p*sizeof(void *));
        if(!pad)continue;
        bool connected=__atomic_load_n((uint8_t *)pad+0x56,__ATOMIC_ACQUIRE)!=0;
        bool desired=p<4&&(wanted_ports&(1u<<p));
        if(paused&&desired!=connected) {if(desired)connect_pad(pad,false);else disconnect_pad(pad);}
        if(p<4&&__atomic_load_n((uint8_t *)pad+0x56,__ATOMIC_ACQUIRE))actual_ports|=1u<<p;
        if(p==0&&session_test)atomic_store(&eden_buttons,pad_buttons(pad));
    }
    if(paused&&!wanted&&actual_ports==wanted_ports) {
        set_running(thread,true);update_menu(window);
        paused=__atomic_load_n(state,__ATOMIC_ACQUIRE)!=0;
        record("EDEN_PAUSE requested=0 native=%d",paused);
    }
    atomic_store(&console_ports,(int)actual_ports);
    atomic_store(&eden_program,*(uint64_t *)impl);
    return paused?1:0;
#else
    return -1;
#endif
}
