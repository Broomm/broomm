// Dolphin 2609 only; the launch supervisor verifies the executable hash.
// Read/reload on the main thread with emulation paused, like Dolphin's dialog.
static bool dolphin_wii;
static _Atomic unsigned long long wii_revision, wii_applied;
static _Atomic int wii_modes[4], wii_selected[4], wii_active[4], wii_orientation[4];
static _Atomic unsigned int wii_sources;
static _Atomic unsigned int wii_buttons[4];
struct WiiCursorState { double x,y; };
static _Atomic double wii_pointer[4][2];
static void wii_tick(int state) {
    if(!dolphin_wii||(state!=1&&state!=2))return;
    static bool resolved;
    static void *(*config)(void);
    static bool (*load)(void *);
    static void *(*controller)(void *,int);
    static void *(*group)(void *,int);
    static unsigned int (*selected)(void *);
    static int (*extension)(void *);
    static bool (*sideways)(void *),(*upright)(void *);
    static const void *(*info)(int);
    static void (*set)(int,const void *,const int *);
    static int (*get)(const void *);
    static uint16_t (*buttons)(void *);
    static struct WiiCursorState (*cursor)(void *,bool);
    if(!resolved) {
        config=symbol("_ZN7Wiimote9GetConfigEv");load=symbol("_ZN11InputConfig10LoadConfigEv");
        controller=symbol("_ZNK11InputConfig13GetControllerEi");
        group=symbol("_ZNK10WiimoteEmu7Wiimote15GetWiimoteGroupENS_12WiimoteGroupE");
        selected=symbol("_ZNK13ControllerEmu11Attachments21GetSelectedAttachmentEv");
        extension=symbol("_ZNK10WiimoteEmu7Wiimote24GetActiveExtensionNumberEv");
        sideways=symbol("_ZNK10WiimoteEmu7Wiimote10IsSidewaysEv");
        upright=symbol("_ZNK10WiimoteEmu7Wiimote9IsUprightEv");
        info=symbol("_ZN6Config23GetInfoForWiimoteSourceEi");
        set=symbol("_ZN6Config3SetINS_4InfoI13WiimoteSourceEES2_EEvNS_9LayerTypeERKT_RKT0_");
        get=symbol("_ZN6Config11GetUncachedI13WiimoteSourceEET_RKNS_4InfoIS2_EE");
        buttons=symbol("_ZN10WiimoteEmu7Wiimote26GetCurrentlyPressedButtonsEv");
        cursor=symbol("_ZN13ControllerEmu6Cursor8GetStateEb");
        resolved=true;
    }
    if(!config||!load||!controller||!group||!selected||!sideways||!upright||!info||!set||!get)return;
    if(state==2) {
        // This getter takes Dolphin's own controller state lock. Test evidence
        // only; do not inspect mutable emulated extension objects while running.
        if(session_test&&buttons)for(int p=0;p<4;++p) {
            void *pad=controller(config(),p);
            if(pad) {
                bool previous=fixture_call;fixture_call=true;
                atomic_store(&wii_buttons[p],buttons(pad));fixture_call=previous;
                // GetState(false) only reads raw control references; it does
                // not advance relative pointer state or the emulated camera.
                if(cursor) {
                    fixture_call=true;
                    struct WiiCursorState point=cursor(group(pad,3),false);
                    atomic_store(&wii_pointer[p][0],isfinite(point.x)?point.x:0);
                    atomic_store(&wii_pointer[p][1],isfinite(point.y)?point.y:0);
                    fixture_call=previous;
                }
            }
        }
        return;
    }
    unsigned long long wanted=atomic_load(&wii_revision);
    bool pending=wanted>atomic_load(&wii_applied);
    if(pending) {
        FILE *f=fopen(getenv("BROOMM_WII_CONFIG"),"r");
        char line[256];unsigned long long file_revision=0;
        if(f){while(fgets(line,sizeof(line),f))if(sscanf(line,"Revision = %llu",&file_revision)==1)break;fclose(f);}
        // A later publication can overtake this command; never apply mismatched data.
        if(file_revision!=wanted)return;
        if(!load(config())) {record("WII_RELOAD_FAILED revision=%llu",wanted);return;}
    }
    bool match=true;unsigned int mask=0;
    for(int p=0;p<4;++p) {
        void *pad=controller(config(),p);if(!pad){match=false;continue;}
        int ext=(int)selected(group(pad,7)),side=sideways(pad),up=upright(pad);
        atomic_store(&wii_selected[p],ext);atomic_store(&wii_orientation[p],side?2:up?1:0);
        if(extension)atomic_store(&wii_active[p],extension(pad));
        if(session_test&&buttons) {
            bool previous=fixture_call;fixture_call=true;
            atomic_store(&wii_buttons[p],buttons(pad));fixture_call=previous;
        }
        int mode=atomic_load(&wii_modes[p]);
        if(ext!=(mode==1?2:mode==2?1:0)||side!=(mode==3)||up!=(mode==0))match=false;
        int source=(atomic_load(&connected_ports)&(1u<<p))?1:0;
        if(get(info(p))!=source)set(6,info(p),&source);
        if(get(info(p))==1)mask|=1u<<p;
    }
    atomic_store(&wii_sources,mask);
    if(pending&&match&&wanted==atomic_load(&wii_revision)) {
        atomic_store(&wii_applied,wanted);
        record("WII_RELOAD_CONFIRMED revision=%llu sources=%u",wanted,mask);
    }
}
