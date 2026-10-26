// Opt-in automated integration fixture. Never enabled in the interactive app.
static pthread_mutex_t test_watch_lock=PTHREAD_MUTEX_INITIALIZER;
static WatchResult test_watch_callback(void *unused,void *event) {
    (void)unused;
    uint32_t type;int code;memcpy(&type,event,4);memcpy(&code,(char *)event+12,4);
    if(type!=0x8001)return 1;
    if(pthread_mutex_trylock(&test_watch_lock)!=0) {atomic_store(&test_watch_failed,true);return 1;}
    if(code==10) {
        atomic_store(&test_watch_step,1);
        _Alignas(8) unsigned char nested[EVENT_SIZE]={0};type=0x8001;code=11;
        memcpy(nested,&type,4);memcpy(nested+12,&code,4);
        void (*lock)(void)=symbol("SDL_LockJoysticks"),(*unlock)(void)=symbol("SDL_UnlockJoysticks");
        int (*push)(void *)=symbol("SDL_PushEvent");
        lock();push(nested);unlock();
        if(atomic_load(&test_watch_step)!=1)atomic_store(&test_watch_failed,true);
    } else if(code==11) {
        if(atomic_load(&test_watch_step)!=1||!pthread_main_np())atomic_store(&test_watch_failed,true);
        atomic_store(&test_watch_step,2);
    }
    pthread_mutex_unlock(&test_watch_lock);return 1;
}
static void test_watch_tick(void) {
    static bool registered;
    if(!session_test||!getenv("BROOMM_DEFER_SDL_WATCHES")||registered)return;
    registered=true;add_watch_hook(test_watch_callback,NULL);
    _Alignas(8) unsigned char event[EVENT_SIZE]={0};uint32_t type=0x8001;int code=10;
    memcpy(event,&type,4);memcpy(event+12,&code,4);
    int (*push)(void *)=symbol("SDL_PushEvent");push(event);
}
static void test_sources_tick(void) {
    if(!session_test)return;
    const char *motion_file=getenv("BROOMM_TEST_MOTION");
    if(motion_file) {
        FILE *motion=fopen(motion_file,"r");
        for(int i=0;i<2;++i) {
            test_motion_support[i]=test_motion_ready[i]=0;
            if(motion&&fscanf(motion,"%d %d %f %f %f %f %f %f",&test_motion_support[i],&test_motion_ready[i],
                &test_motion_data[i][0][0],&test_motion_data[i][0][1],&test_motion_data[i][0][2],
                &test_motion_data[i][1][0],&test_motion_data[i][1][1],&test_motion_data[i][1][2])!=8)
                test_motion_support[i]=test_motion_ready[i]=0;
        }
        if(motion)fclose(motion);
    }
    unsigned int masks[2]={0,0},present=3,freeze=0,close_window=0;
    int axes[2][6]={{12000,0,0,0,-32768,-32768},{-12000,0,0,0,-32768,-32768}};
    const char *file=getenv("BROOMM_TEST_INPUT");FILE *f=file?fopen(file,"r"):NULL;
    if(f) {
        if(fscanf(f,"%u %u %u %u %u %d %d %d %d %d %d %d %d %d %d",&masks[0],&masks[1],&present,&freeze,&close_window,
            &axes[0][2],&axes[0][3],&axes[0][5],&axes[1][2],&axes[1][3],&axes[1][5],
            &axes[0][0],&axes[0][1],&axes[1][0],&axes[1][1])<3) {
            masks[0]=masks[1]=0;
        }
        fclose(f);
    }
    test_freeze_status=freeze==1;
    static unsigned int sony_previous;
    static unsigned int psp_previous;
    if(getenv("BROOMM_PPSSPP")&&close_window!=psp_previous) {
        if(close_window==2||close_window==3)atomic_store(&psp_test_key,(int)close_window);
        psp_previous=close_window;
    }
    if(getenv("BROOMM_PLAYSTATION")&&close_window!=sony_previous) {
        if(close_window==2||close_window==3)atomic_store(&sony_test_action,(int)close_window);
        sony_previous=close_window;
    }
    static bool close_sent;
    if(close_window==1&&!close_sent){close_sent=true;atomic_store(&test_close_window,true);}
    for(int i=0;i<2;++i) {
        if((present&(1u<<i))&&!test_joy[i]) {
#if BROOMM_SDL_MAJOR == 3
            struct VirtualDesc d={.version=sizeof(d),.type=1,.vendor=0x1209,.product=(uint16_t)(0xc001+i),
              .axes=6,.buttons=21,.button_mask=0x1fffff,.axis_mask=0x3f,.name=i?"Broomm test source B":"Broomm test source A"};
            uint32_t (*attach)(const struct VirtualDesc *)=symbol("SDL_AttachVirtualJoystick");
            test_ids[i]=attach(&d);test_joy[i]=real_open_joy(test_ids[i]);
#else
            int (*attach)(int,int,int,int)=symbol("SDL_JoystickAttachVirtual");
            int index=attach(1,6,21,1);test_joy[i]=real_open_joy((uint32_t)index);
            test_ids[i]=joystick_id(test_joy[i]);
#endif
        }
        if(!(present&(1u<<i))&&test_joy[i]) {
#if BROOMM_SDL_MAJOR == 3
            bool (*detach)(uint32_t)=symbol("SDL_DetachVirtualJoystick");
            void (*close_joy)(void *)=symbol("SDL_CloseJoystick");
            detach(test_ids[i]);
#else
            int (*num)(void)=symbol("SDL_NumJoysticks");
            uint32_t (*id_fn)(int)=symbol("SDL_JoystickGetDeviceInstanceID");
            int (*detach)(int)=symbol("SDL_JoystickDetachVirtual");
            void (*close_joy)(void *)=symbol("SDL_JoystickClose");
            for(int n=0;n<num();++n)if(id_fn(n)==test_ids[i]){detach(n);break;}
#endif
            close_joy(test_joy[i]);test_joy[i]=NULL;test_ids[i]=UINT32_MAX;
        }
        if(!test_joy[i])continue;
#if BROOMM_SDL_MAJOR == 3
        bool (*button)(void *,int,bool)=symbol("SDL_SetJoystickVirtualButton");
        bool (*axis)(void *,int,int16_t)=symbol("SDL_SetJoystickVirtualAxis");
#else
        int (*button)(void *,int,uint8_t)=symbol("SDL_JoystickSetVirtualButton");
        int (*axis)(void *,int,int16_t)=symbol("SDL_JoystickSetVirtualAxis");
#endif
        for(int b=0;b<21;b++)button(test_joy[i],b,(masks[i]&(1u<<b))!=0);
        for(int a=0;a<6;++a)axis(test_joy[i],a,(int16_t)axes[i][a]);
    }
}
