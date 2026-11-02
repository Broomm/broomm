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
    // Capture the pre-command gate before Wii reload can assert it. A plain
    // active-route publication must not manufacture an explicit Resume.
    bool was_blocked=atomic_load(&session_gate);
    if(dolphin_wii&&!quit) {
        for(int p=0;p<4;++p)atomic_store(&wii_modes[p],modes[p]);
        unsigned int present=0;
        for(int p=0;p<4;++p)for(int i=0;i<source_count;++i)
            if(routes[p]==sources[i].id)present|=1u<<p;
        atomic_store(&connected_ports,present);
        atomic_store(&wii_revision,next);
        atomic_store(&session_gate,1); // Native reload must finish before resume.
    }
    revision=next;pending_activation=active&&valid&&was_blocked;
    atomic_store(&session_gate,!active||!valid||pending_activation);
    set_session_wanted(pause||!valid||pending_activation);
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
    fprintf(out,",\"pauseReleaseSerial\":%llu",atomic_load(&session_resume_serial));
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

static void linux_route_events(unsigned mask) {
#if BROOMM_SDL_MAJOR == 2
    if(!getenv("BROOMM_RYUBING"))return;
    static unsigned previous;if(previous==mask)return;
    int (*push)(void *)=symbol("SDL_PushEvent");if(!push)return;
    // Rebuild the frontend's ordered device list while guest CPU/input are
    // gated. Unique GUIDs bind each list entry to its owned logical port.
    for(int phase=0;phase<2;++phase)for(int i=0;i<4;++i) {
        int p=phase?i:3-i;bool added=phase!=0;if(!((added?mask:previous)&(1u<<p)))continue;int index=-1;
        if(added)for(int n=0;n<unfiltered_count();++n)if(unfiltered_instance(n)==ids[p]){index=n;break;}
        if(added&&index<0)continue;
        _Alignas(8) unsigned char event[56]={0};uint32_t type=added?0x605:0x606,value=added?(uint32_t)index:ids[p];
        memcpy(event,&type,4);memcpy(event+8,&value,4);if(push(event)<0){atomic_store(&control_failed,true);return;}
    }
    previous=mask;
#else
    (void)mask;
#endif
}
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
        if(atomic_exchange(&control_failed,false))session_request("input-error");
        if(atomic_exchange(&watch_queue_overflow,false))session_request("input-error");
        if(atomic_exchange(&game_ended,false)) {
            session_request("game-ended");
            appkit_game_seen=false;
        }
        if(getppid()!=owner){atomic_store(&linux_orphaned,true);if(!atomic_load(&session_gate))session_request("launcher-exit");}
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
        atomic_store(&connected_ports,present_ports);linux_route_events(present_ports);
        if(pending_activation) {
            bool released=true;
            for(int i=0;i<source_count;++i)for(int p=0;p<4;++p)
                if(sources[i].id==routes[p]&&sources[i].buttons)released=false;
            if(!strcmp(request_kind,"gyro"))for(int i=0;i<source_count;++i)
                if(sources[i].id==request_device&&sources[i].axes[5]>8192)released=false;
            if(released&&(!getenv("BROOMM_RYUBING")||atomic_load(&console_ports)==(int)present_ports)&&(!dolphin_wii||atomic_load(&wii_applied)>=atomic_load(&wii_revision))){pending_activation=false;atomic_store(&session_gate,0);set_session_wanted(0);}
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
