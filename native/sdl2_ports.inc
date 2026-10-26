// SDL2 uses device indices in its discovery API and instance IDs in events.
// Expose only the logical ports to opted-in emulators; Broomm discovery bypasses
// this view in the same runtime. Translate at each consuming API boundary.
#if BROOMM_SDL_MAJOR == 2
static int (*unfiltered_count)(void);
static uint32_t (*unfiltered_instance)(int);
static int (*unfiltered_is_gamepad)(int);
struct PortGuid { unsigned char bytes[16]; };
static struct PortGuid (*unfiltered_guid)(int);
static const char *(*unfiltered_joy_name)(int),*(*unfiltered_pad_name)(int);
static int sdl2_port_limit(void) {
    return getenv("BROOMM_PPSSPP")?1:getenv("BROOMM_EDEN")?4:0;
}
static int sdl2_real_index(int logical) {
    if(!unfiltered_count||!unfiltered_instance||logical<0||logical>=sdl2_port_limit()||ids[logical]==UINT32_MAX)return -1;
    for(int i=0;i<unfiltered_count();++i)if(unfiltered_instance(i)==ids[logical])return i;
    return -1;
}
static int sdl2_count(void) {
    if(fixture_call||!sdl2_port_limit())return unfiltered_count();
    int count=0;for(int i=0;i<sdl2_port_limit();++i)if(ids[i]!=UINT32_MAX)++count;
    return count;
}
static uint32_t sdl2_instance(int index) {
    if(fixture_call||!sdl2_port_limit())return unfiltered_instance(index);
    return index>=0&&index<sdl2_port_limit()?ids[index]:UINT32_MAX;
}
static int sdl2_is_gamepad(int index) {
    if(!fixture_call&&sdl2_port_limit())index=sdl2_real_index(index);
    return index<0?0:unfiltered_is_gamepad(index);
}
static struct PortGuid sdl2_guid(int index) {
    if(!fixture_call&&sdl2_port_limit())index=sdl2_real_index(index);
    return index<0?(struct PortGuid){{0}}:unfiltered_guid(index);
}
static const char *sdl2_joy_name(int index) {
    if(!fixture_call&&sdl2_port_limit())index=sdl2_real_index(index);
    return index<0?NULL:unfiltered_joy_name(index);
}
static const char *sdl2_pad_name(int index) {
    if(!fixture_call&&sdl2_port_limit())index=sdl2_real_index(index);
    return index<0?NULL:unfiltered_pad_name(index);
}
static void install_sdl2_ports(void) {
    if(!sdl2_port_limit())return;
    hook("SDL_NumJoysticks",sdl2_count,(void **)&unfiltered_count);
    hook("SDL_JoystickGetDeviceInstanceID",sdl2_instance,(void **)&unfiltered_instance);
    hook("SDL_IsGameController",sdl2_is_gamepad,(void **)&unfiltered_is_gamepad);
    hook("SDL_JoystickGetDeviceGUID",sdl2_guid,(void **)&unfiltered_guid);
    hook("SDL_JoystickNameForIndex",sdl2_joy_name,(void **)&unfiltered_joy_name);
    hook("SDL_GameControllerNameForIndex",sdl2_pad_name,(void **)&unfiltered_pad_name);
}
static bool sdl2_port_event(void *event,uint32_t type) {
    if(!sdl2_port_limit())return false;
    // Device-added events carry an index, removed events an instance ID.
    if(type!=0x605&&type!=0x606&&type!=0x653&&type!=0x654)return false;
    uint32_t value;memcpy(&value,(char *)event+ID_OFFSET,4);
    bool added=type==0x605||type==0x653;
    uint32_t instance=added&&unfiltered_instance?unfiltered_instance((int)value):value;
    int port=-1;for(int i=0;i<sdl2_port_limit();++i)if(ids[i]!=UINT32_MAX&&ids[i]==instance){port=i;break;}
    if(port<0){type=0;memcpy(event,&type,4);}
    else if(added){value=(uint32_t)port;memcpy((char *)event+ID_OFFSET,&value,4);}
    return true;
}
#endif
