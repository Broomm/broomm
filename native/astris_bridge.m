// Astris 1.0.32+2398e7c80, macOS ARM64. No emulator implementation is copied.
// The application verifies the complete pinned bundle before loading this
// adapter. Export offsets and managed readback fields belong to this build only.
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>
#include <unistd.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include "ownership.inc"

static NSString *as_root, *as_user;
static NSUserDefaults *as_defaults;
static NSMutableDictionary *as_preferences;
static NSMutableDictionary *as_options;
static BOOL as_session, as_initialized, as_pending, as_gate=YES, as_wanted=YES;
static BOOL as_inspected;
static _Atomic bool as_ready, as_ended;
static uintptr_t as_library;
static uint64_t as_revision, as_sample, as_serial=1;
static NSString *as_request=@"initial";
static uint32_t as_device=UINT32_MAX, as_routes[4]={UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX};
static int as_swaps[4], as_gyro[4]={1,1,1,1}, as_handles[4]={-1,-1,-1,-1};
static NSMutableArray<GCController *> *as_controllers;
static NSMutableArray<NSNumber *> *as_ids;
static uint32_t as_next_id=1, as_ports;
static int as_paused=-1;
static void (*as_first_callback)(void);

static void *as_native(size_t offset) {
    if(!as_library)for(uint32_t i=0;i<_dyld_image_count();i++)
        if([@(_dyld_get_image_name(i)) hasSuffix:@"/libryujinx.dylib"])
            as_library=(uintptr_t)_dyld_get_image_header(i);
    if(!as_library)_exit(73);
    return (void *)(as_library+offset);
}

// The managed copy has no application-container sandbox; Dart supplies a
// stricter write policy around its private root instead. Its frontend still
// requires a successful security-scope call even for these already accessible
// URLs. Adapt only the resolved ROM and this profile's data directory, without
// granting access to any other path or bypassing kernel file permissions.
static IMP as_scope_start_original,as_scope_stop_original;
static BOOL as_owned_url(NSURL *url) {
    if(!url.isFileURL)return NO;
    NSString *path=url.URLByStandardizingPath.path;
    const char *rom=getenv("BROOMM_ASTRIS_ROM");
    return access(path.fileSystemRepresentation,R_OK)==0 &&
        ((rom&&[path isEqualToString:@(rom)])||[path isEqualToString:as_user]||[path hasPrefix:[as_user stringByAppendingString:@"/"]]);
}
static BOOL as_scope_start(NSURL *url,SEL selector) {
    return as_owned_url(url)?YES:((BOOL(*)(id,SEL))as_scope_start_original)(url,selector);
}
static void as_scope_stop(NSURL *url,SEL selector) {
    if(!as_owned_url(url))((void(*)(id,SEL))as_scope_stop_original)(url,selector);
}
static void as_private_urls(void) {
    Class cls=object_getClass([NSURL fileURLWithPath:as_user]);
    SEL start=@selector(startAccessingSecurityScopedResource),stop=@selector(stopAccessingSecurityScopedResource);
    Method first=class_getInstanceMethod(cls,start),last=class_getInstanceMethod(cls,stop);
    as_scope_start_original=method_getImplementation(first);as_scope_stop_original=method_getImplementation(last);
    class_addMethod(cls,start,(IMP)as_scope_start,method_getTypeEncoding(first));
    class_addMethod(cls,stop,(IMP)as_scope_stop,method_getTypeEncoding(last));
    method_setImplementation(class_getInstanceMethod(cls,start),(IMP)as_scope_start);
    method_setImplementation(class_getInstanceMethod(cls,stop),(IMP)as_scope_stop);
}

// NSUserDefaults normally uses cfprefsd outside a child HOME. Keep this
// frontend's preferences in an explicit private plist instead. Volatile-domain
// reads preserve native AppStorage/KVO behavior without system preference writes.
static void as_save_preferences(id object, SEL selector, id value, NSString *key) {
    (void)selector;
    if(object!=as_defaults)return;
    @synchronized(as_defaults) {
        struct stat info;
        NSString *path=[as_root stringByAppendingPathComponent:@"frontend.plist"];
        if(lstat(path.fileSystemRepresentation,&info)==0&&!S_ISREG(info.st_mode))_exit(73);
        if(value)as_preferences[key]=value;else[as_preferences removeObjectForKey:key];
        [as_defaults willChangeValueForKey:key];
        [as_defaults setVolatileDomain:as_preferences forName:NSArgumentDomain];
        [as_defaults didChangeValueForKey:key];
        NSError *error=nil;
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:as_preferences format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        if(!data||![data writeToFile:[as_root stringByAppendingPathComponent:@"frontend.plist"] options:NSDataWritingAtomic error:&error])
            NSLog(@"Broomm Astris: private preferences could not be saved (%@)", error.localizedDescription);
        [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:as_defaults];
    }
}
static void as_remove(id o,SEL s,NSString *k){as_save_preferences(o,s,nil,k);}
static void as_bool(id o,SEL s,BOOL v,NSString *k){as_save_preferences(o,s,@(v),k);}
static void as_integer(id o,SEL s,NSInteger v,NSString *k){as_save_preferences(o,s,@(v),k);}
static void as_double(id o,SEL s,double v,NSString *k){as_save_preferences(o,s,@(v),k);}
static void as_float(id o,SEL s,float v,NSString *k){as_save_preferences(o,s,@(v),k);}
static BOOL as_sync(id o,SEL s){(void)o;(void)s;return YES;}
static id as_standard(id o,SEL s){(void)o;(void)s;return as_defaults;}
static void as_preference_method(const char *name,IMP replacement) {
    Method method=class_getInstanceMethod(NSUserDefaults.class,sel_registerName(name));
    class_addMethod(object_getClass(as_defaults),sel_registerName(name),replacement,method_getTypeEncoding(method));
}
static void as_private_preferences(void) {
    // Never fall through to Astris's system-wide persistent preference domain.
    // A fresh suite supplies registration/global OS defaults only; all emulator
    // preferences are restored from and written to the private plist below.
    as_defaults=[[NSUserDefaults alloc] initWithSuiteName:[@"app.broomm.astris." stringByAppendingString:NSUUID.UUID.UUIDString]];
    Class privateClass=objc_allocateClassPair(NSUserDefaults.class,"BroommAstrisPreferences",0);
    objc_registerClassPair(privateClass);
    object_setClass(as_defaults,privateClass);
    as_preference_method("setObject:forKey:",(IMP)as_save_preferences);
    as_preference_method("removeObjectForKey:",(IMP)as_remove);
    as_preference_method("setBool:forKey:",(IMP)as_bool);
    as_preference_method("setInteger:forKey:",(IMP)as_integer);
    as_preference_method("setDouble:forKey:",(IMP)as_double);
    as_preference_method("setFloat:forKey:",(IMP)as_float);
    as_preference_method("synchronize",(IMP)as_sync);
    method_setImplementation(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),(IMP)as_standard);
    struct stat info;
    NSString *path=[as_root stringByAppendingPathComponent:@"frontend.plist"];
    if(lstat(path.fileSystemRepresentation,&info)==0&&!S_ISREG(info.st_mode))_exit(73);
    NSData *saved=[NSData dataWithContentsOfFile:[as_root stringByAppendingPathComponent:@"frontend.plist"]];
    as_preferences=saved?[[NSPropertyListSerialization propertyListWithData:saved options:NSPropertyListMutableContainers format:NULL error:nil] mutableCopy]:[NSMutableDictionary dictionary];
    if(![as_preferences isKindOfClass:NSMutableDictionary.class])_exit(73);
    NSError *error=nil;
    NSData *bookmark=[[NSURL fileURLWithPath:as_user isDirectory:YES] bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    if(!bookmark){NSLog(@"Broomm Astris: private data bookmark failed");_exit(73);}
    as_preferences[@"RyujinxBaseDirBookmark"]=bookmark;
    as_preferences[@"UseDefaultRyujinxDir"]=@NO;
    [as_defaults setVolatileDomain:as_preferences forName:NSArgumentDomain];
}

extern void ryujinx_update_options(const char *);
extern void ryujinx_init(void);
extern void ryujinx_set_first_frame_callback(void (*)(void));
extern void ryujinx_stop_emulation(void);
extern int ryujinx_connect_controller(const char *,const char *);
extern void ryujinx_disconnect_controller(int);
extern void ryujinx_set_controller_button_pressed(int,int,bool);
extern void ryujinx_set_controller_stick_axis(int,int,float,float);
extern void ryujinx_set_controller_motion_axis(int,float,float,float,float,float,float);

static void as_apply_options(void) {
    @synchronized(as_defaults) {
    if(!as_options)return;
    NSMutableDictionary *options=[as_options mutableCopy];
    options[@"base_data_dir"]=as_user;
    if(as_session&&as_initialized) {
        NSData *data=[NSData dataWithContentsOfFile:[as_root stringByAppendingPathComponent:@"controller-config.json"]];
        NSArray *template=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if(template.count!=4)_exit(73);
        NSMutableArray *players=[NSMutableArray array];
        for(int p=0;p<4;p++) {
            NSMutableDictionary *config=[template[p] mutableCopy];
            config[@"backend"]=(as_ports&(1u<<p))?@"Gamepad":@"Invalid";
            [players addObject:config];
        }
        options[@"player_input_config"]=players;
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:options options:0 error:nil];
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    ((void(*)(const char *))as_native(0x96116c))(text.UTF8String);
    }
}
static void as_update_options(const char *text) {
    @synchronized(as_defaults) {
    if(!text||strnlen(text,1024*1024)>=1024*1024)_exit(73);
    NSData *data=[NSData dataWithBytes:text length:strlen(text)];
    as_options=[[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    if(![as_options isKindOfClass:NSMutableDictionary.class])_exit(73);
    if(as_initialized)as_apply_options();
    else ((void(*)(const char *))as_native(0x96116c))(text);
    }
}
static void as_first_frame(void) {atomic_store(&as_ready,true);if(as_first_callback)as_first_callback();}
static void as_set_first(void (*callback)(void)) {
    as_initialized=YES;
    as_first_callback=callback;
    ((void(*)(void(*)(void)))as_native(0x961930))(as_first_frame);
}
static void as_stop(void) {
    ((void(*)(void))as_native(0x958608))();
    atomic_store(&as_ended,true);
}
static int as_connect(const char *id,const char *name) {
    return as_session?-1:((int(*)(const char *,const char *))as_native(0x9621a0))(id,name);
}
static void as_disconnect(int id) {if(!as_session)((void(*)(int))as_native(0x96224c))(id);}
static void as_button(int id,int button,bool down) {if(!as_session)((void(*)(int,int,bool))as_native(0x9622d8))(id,button,down);}
static void as_stick(int id,int stick,float x,float y) {if(!as_session)((void(*)(int,int,float,float))as_native(0x962370))(id,stick,x,y);}
static void as_motion(int id,float ax,float ay,float az,float gx,float gy,float gz) {if(!as_session)((void(*)(int,float,float,float,float,float,float))as_native(0x9623fc))(id,ax,ay,az,gx,gy,gz);}
#define AS_INTERPOSE(replacement,original) \
 __attribute__((used)) static struct {const void *r,*o;} as_hook_##original \
 __attribute__((section("__DATA,__interpose")))={(void *)replacement,(void *)original}
AS_INTERPOSE(as_update_options,ryujinx_update_options);
AS_INTERPOSE(as_set_first,ryujinx_set_first_frame_callback);
AS_INTERPOSE(as_stop,ryujinx_stop_emulation);
AS_INTERPOSE(as_connect,ryujinx_connect_controller);
AS_INTERPOSE(as_disconnect,ryujinx_disconnect_controller);
AS_INTERPOSE(as_button,ryujinx_set_controller_button_pressed);
AS_INTERPOSE(as_stick,ryujinx_set_controller_stick_axis);
AS_INTERPOSE(as_motion,ryujinx_set_controller_motion_axis);

static void as_request_menu(NSString *kind,uint32_t device) {
    as_gate=YES;as_wanted=YES;as_pending=NO;as_request=kind;as_device=device;as_serial++;
}
static int as_pause_state(void) {
    uintptr_t api=*(uintptr_t *)as_native(0x14a1398);
    uintptr_t context=api?*(uintptr_t *)(api+0xd0):0;
    uintptr_t device=context?*(uintptr_t *)(context+0x30):0;
    return device?*(uint8_t *)(device+0x11a):-1;
}
static NSArray *as_vector(double x,double y,double z) {
    return @[@(isfinite(x)?x:0),@(isfinite(y)?y:0),@(isfinite(z)?z:0)];
}
static NSDictionary *as_sample_controller(GCController *controller,uint32_t identity) {
    GCExtendedGamepad *pad=controller.extendedGamepad;
    GCControllerButtonInput *buttons[]={pad.buttonA,pad.buttonB,pad.buttonX,pad.buttonY,pad.buttonOptions,pad.buttonHome,pad.buttonMenu,pad.leftThumbstickButton,pad.rightThumbstickButton,pad.leftShoulder,pad.rightShoulder,pad.dpad.up,pad.dpad.down,pad.dpad.left,pad.dpad.right};
    uint32_t bits=0;for(int b=0;b<15;b++)if(buttons[b].isPressed)bits|=1u<<b;
    GCMotion *motion=controller.motion;
    if(motion.hasRotationRate)motion.sensorsActive=YES;
    GCAcceleration acceleration=motion.acceleration;
    GCRotationRate rotation=motion.rotationRate;
    NSString *name=controller.vendorName?:@"Gamepad";
    NSString *kind=controller.productCategory.lowercaseString;
    int family=[kind containsString:@"xbox"]?1:([kind containsString:@"dual"]||[kind containsString:@"playstation"])?2:([kind containsString:@"switch"]||[kind containsString:@"joy"])?3:0;
    return @{@"id":@(identity),@"name":name,@"buttons":@(bits),@"x":@((int)(pad.leftThumbstick.xAxis.value*32767)),@"y":@((int)(-pad.leftThumbstick.yAxis.value*32767)),@"rx":@((int)(pad.rightThumbstick.xAxis.value*32767)),@"ry":@((int)(-pad.rightThumbstick.yAxis.value*32767)),@"lt":@((int)(pad.leftTrigger.value*32767)),@"rt":@((int)(pad.rightTrigger.value*32767)),@"family":@(family),@"sensors":@(motion.hasRotationRate?3:0),@"sensorReady":@(motion.hasRotationRate?3:0),@"accel":as_vector(acceleration.x,acceleration.y,acceleration.z),@"gyro":as_vector(rotation.x,rotation.y,rotation.z)};
}
static void as_read_command(NSDictionary<NSNumber *,NSDictionary *> *sources) {
    const char *path=getenv("BROOMM_SESSION_COMMAND");
    if(!path){as_request_menu(@"bridge-error",UINT32_MAX);return;}
    FILE *file=fopen(path,"r");if(!file)return;
    unsigned long long revision;unsigned int routes[4];int active,pause,swaps[4],quit,modes[4],gyro[4];
    int n=fscanf(file,"%llu %d %d %u %u %u %u %d %d %d %d %d %d %d %d %d %d %d %d %d",&revision,&active,&pause,&routes[0],&routes[1],&routes[2],&routes[3],&swaps[0],&swaps[1],&swaps[2],&swaps[3],&quit,&modes[0],&modes[1],&modes[2],&modes[3],&gyro[0],&gyro[1],&gyro[2],&gyro[3]);fclose(file);
    if(n!=20||revision<=as_revision||(active!=0&&active!=1)||(pause!=0&&pause!=1)||(quit!=0&&quit!=1))return;
    for(int p=0;p<4;p++) {
        if((swaps[p]!=0&&swaps[p]!=1)||(gyro[p]!=0&&gyro[p]!=1)||modes[p]<0||modes[p]>3)return;
        for(int q=0;q<p;q++)if(routes[p]!=UINT32_MAX&&routes[p]==routes[q])return;
    }
    BOOL valid=YES;for(int p=0;p<4;p++)if(routes[p]!=UINT32_MAX&&!sources[@(routes[p])])valid=NO;
    memcpy(as_routes,routes,sizeof(routes));memcpy(as_swaps,swaps,sizeof(swaps));memcpy(as_gyro,gyro,sizeof(gyro));as_revision=revision;
    as_pending=active&&valid&&as_gate;as_gate=!active||!valid||as_pending;as_wanted=pause||!valid||as_pending;
    if(!valid)as_request_menu(@"disconnect",UINT32_MAX);
    if(quit) {
        as_gate=YES;as_wanted=YES;
        if(atomic_load(&as_ready)&&!atomic_load(&as_ended))as_stop();
        [NSApp terminate:nil];
    }
}
static void as_tick(void) {
    static NSMutableDictionary<NSNumber *,NSNumber *> *held;
    static pid_t owner;
    static uint64_t seconds,microseconds;
    struct proc_bsdinfo launcher;
    if(!held){
        held=[NSMutableDictionary dictionary];owner=(pid_t)strtol(getenv("BROOMM_LAUNCHER_PID")?:"0",NULL,10);
        if(owner<=1||proc_pidinfo(owner,PROC_PIDTBSDINFO,0,&launcher,sizeof(launcher))!=sizeof(launcher))_exit(73);
        seconds=launcher.pbi_start_tvsec;microseconds=launcher.pbi_start_tvusec;
    }
    if((proc_pidinfo(owner,PROC_PIDTBSDINFO,0,&launcher,sizeof(launcher))!=sizeof(launcher)||
        launcher.pbi_start_tvsec!=seconds||launcher.pbi_start_tvusec!=microseconds)&&!as_gate)
        as_request_menu(@"launcher-exit",UINT32_MAX);
    GCController.shouldMonitorBackgroundEvents=YES;
    NSArray<GCController *> *current=GCController.controllers;
    for(NSInteger i=as_controllers.count-1;i>=0;i--)if(![current containsObject:as_controllers[i]]) {
        NSNumber *lost=as_ids[i];
        [held removeObjectForKey:lost];[as_controllers removeObjectAtIndex:i];[as_ids removeObjectAtIndex:i];
    }
    for(GCController *controller in current)if(controller.extendedGamepad&&![as_controllers containsObject:controller]&&as_controllers.count<32) {
        [as_controllers addObject:controller];[as_ids addObject:@(as_next_id++)];
    }
    NSMutableDictionary *sources=[NSMutableDictionary dictionary];NSMutableArray *devices=[NSMutableArray array];
    for(NSUInteger i=0;i<as_controllers.count;i++) {
        NSDictionary *source=as_sample_controller(as_controllers[i],as_ids[i].unsignedIntValue);sources[as_ids[i]]=source;[devices addObject:source];
    }
    if(getenv("BROOMM_SESSION_TEST")) {
        unsigned int bits=0,missing=0,count=3;
        FILE *input=fopen(getenv("BROOMM_TEST_INPUT")?:"","r");
        if(input){(void)fscanf(input,"%u %u %u",&bits,&missing,&count);fclose(input);}
        for(unsigned int i=0;i<MIN(count,4);i++)if(!(missing&(1u<<i))) {
            NSNumber *identity=@(0x70000001u+i);
            NSDictionary *source=@{@"id":identity,@"name":@"Broomm test source",@"buttons":@(bits),@"x":@0,@"y":@0,@"rx":@0,@"ry":@0,@"lt":@0,@"rt":@0,@"family":@1,@"sensors":@0,@"sensorReady":@0,@"accel":as_vector(0,0,0),@"gyro":as_vector(0,0,0)};
            sources[identity]=source;[devices addObject:source];
        }
    }
    for(int p=0;p<4;p++)if((as_ports&(1u<<p))&&as_routes[p]!=UINT32_MAX&&!sources[@(as_routes[p])])as_request_menu(@"disconnect",as_routes[p]);
    as_read_command(sources);
    uint32_t ports=0;BOOL released=YES;
    for(int p=0;p<4;p++)if(sources[@(as_routes[p])]) {
        ports|=1u<<p;NSDictionary *source=sources[@(as_routes[p])];
        if([source[@"buttons"] unsignedIntValue]||[source[@"rt"] intValue]>8192)released=NO;
        int bits=[source[@"buttons"] unsignedIntValue];BOOL chord=(bits&(1u<<4))&&(bits&(1u<<8));
        BOOL gyro=(bits&(1u<<7))&&[source[@"rt"] intValue]>=16384;
        int old=[held[@(as_routes[p])] intValue];
        if(!as_gate&&chord&&!(old&1))as_request_menu(@"menu",as_routes[p]);
        if(!as_gate&&gyro&&!(old&2))as_request_menu(@"gyro",as_routes[p]);
        held[@(as_routes[p])]=@((chord?1:0)|(gyro?2:0));
    }
    if(as_initialized) {
        for(int p=0;p<4;p++)if((ports&(1u<<p))&&as_handles[p]<0) {
            NSString *id=[NSString stringWithFormat:@"broomm-%d",p];
            as_handles[p]=((int(*)(const char *,const char *))as_native(0x9621a0))(id.UTF8String,"Broomm");
        }
        // Keep virtual source identities alive for this process. Native input
        // readers retain them; unpairing disables the player configuration.
        if(as_ports!=ports){as_ports=ports;as_apply_options();}
    }
    if(as_pending&&released){as_pending=NO;as_gate=NO;as_wanted=NO;}
    if(atomic_load(&as_ended))as_request=@"game-ended";
    if(atomic_load(&as_ready)&&!atomic_load(&as_ended)) {
        // Read the same Device.IsPaused byte written by the synchronous pinned
        // backend setter, resolving the GC root afresh on the owning queue.
        as_paused=as_pause_state();
        if(as_paused>=0&&as_paused!=(int)as_wanted) {
            ((void(*)(bool))as_native(0x958540))(as_wanted);
            as_paused=as_pause_state();
        }
        // The exported frontend API uses the same first 15 button indices
        // as Broomm; the backend maps these to GamepadButtonInputId values.
        const int buttonIds[]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14};
        for(int p=0;p<4;p++)if(as_handles[p]>=0) {
            NSDictionary *source=sources[@(as_routes[p])];BOOL live=source&&!as_gate&&as_paused==0;
            uint32_t bits=live?[source[@"buttons"] unsignedIntValue]:0;
            for(int b=0;b<15;b++) {
                int mapped=as_swaps[p]&&b<4?b^1:b;
                ((void(*)(int,int,bool))as_native(0x9622d8))(as_handles[p],buttonIds[b],(bits&(1u<<mapped))!=0);
            }
            for(int stick=0;stick<2;stick++)((void(*)(int,int,float,float))as_native(0x962370))(as_handles[p],stick,live?[source[stick?@"rx":@"x"] floatValue]/32767:0,live?-[source[stick?@"ry":@"y"] floatValue]/32767:0);
            ((void(*)(int,int,bool))as_native(0x9622d8))(as_handles[p],15,live&&[source[@"lt"] intValue]>=16384);
            ((void(*)(int,int,bool))as_native(0x9622d8))(as_handles[p],16,live&&[source[@"rt"] intValue]>=16384);
            NSArray *a=source[@"accel"],*g=source[@"gyro"];BOOL motion=live&&as_gyro[p]&&[source[@"sensorReady"] intValue]==3;
            ((void(*)(int,float,float,float,float,float,float))as_native(0x9623fc))(as_handles[p],motion?[a[0] floatValue]:0,motion?[a[1] floatValue]:0,motion?[a[2] floatValue]:0,motion?[g[0] floatValue]*180/M_PI:0,motion?[g[1] floatValue]*180/M_PI:0,motion?[g[2] floatValue]*180/M_PI:0);
        }
    }
    NSWindow *window=NSApp.keyWindow?:NSApp.mainWindow;NSRect frame=window.frame;
    if(window)frame.origin.y=NSScreen.screens.firstObject.frame.size.height-frame.origin.y-frame.size.height;
    uint64_t native_buttons=0;
    if(getenv("BROOMM_SESSION_TEST")&&as_handles[0]>=0) {
        uintptr_t slot=*(uintptr_t *)as_native(0x14a0a28);
        uintptr_t driver=slot?*(uintptr_t *)(slot+8):0;
        uintptr_t list=driver?*(uintptr_t *)(driver+0x10):0;
        uintptr_t pad=list&&as_handles[0]<*(int *)(list+8)?*(uintptr_t *)(list+0x10+as_handles[0]*8):0;
        uintptr_t buttons=pad?*(uintptr_t *)(pad+0x10):0;
        if(buttons)for(int b=0;b<MIN(*(int *)(buttons+8),64);b++)if(*(uint8_t *)(buttons+0x10+b))native_buttons|=1ull<<b;
    }
    NSMutableDictionary *status=[@{@"protocol":@4,@"pid":@(getpid()),@"sample":@(++as_sample),@"ack":@(as_revision),@"requestSerial":@(as_serial),@"request":as_request,@"requestDevice":as_device==UINT32_MAX?NSNull.null:@(as_device),@"blocked":@(as_gate),@"paused":@(as_paused),@"window":@[@(frame.origin.x),@(frame.origin.y),@(frame.size.width),@(frame.size.height)],@"devices":devices,@"connectedPorts":@(as_ports),@"consolePorts":@(-1),@"switchButtons":@(native_buttons),@"appActive":@(NSApp.isActive),@"inputReady":@((BOOL)(as_initialized&&atomic_load(&as_ready))),@"gyroEnabled":@[@(as_gyro[0]),@(as_gyro[1]),@(as_gyro[2]),@(as_gyro[3])]} mutableCopy];
    if(getenv("BROOMM_SESSION_TEST")) {
        NSMutableArray *ids=[NSMutableArray array];for(NSDictionary *source in devices)if([source[@"id"] unsignedIntValue]>=0x70000001u)[ids addObject:source[@"id"]];
        status[@"testSourceIds"]=ids;
    }
    NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:&error];
    if(!data||![data writeToFile:@(getenv("BROOMM_SESSION_STATUS")) options:NSDataWritingAtomic error:&error])NSLog(@"Broomm Astris: controller status could not be published");
}

static void as_normal_exit(void) {
    if(!as_session&&!getenv("BROOMM_ASTRIS_INSPECT"))return;
    @autoreleasepool {
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"pid":@(getpid()),@"normal":@((BOOL)(as_inspected||(atomic_load(&as_ready)&&atomic_load(&as_ended))))} options:0 error:nil];
        (void)[data writeToFile:[as_root stringByAppendingPathComponent:@"astris-exit.json"] options:NSDataWritingAtomic error:nil];
    }
}
// Native JSON conversion only. Dart validates the requested files, package
// family and publication. This process can write solely into its private stage.
static void as_inspect(void) {
    NSData *input=[NSData dataWithContentsOfFile:@(getenv("BROOMM_ASTRIS_INSPECT"))];
    if(input.length>1024*1024)_exit(74);
    NSArray *paths=input?[NSJSONSerialization JSONObjectWithData:input options:0 error:nil]:nil;
    if(![paths isKindOfClass:NSArray.class]||paths.count>512)_exit(74);
    NSMutableArray *results=[NSMutableArray array];
    for(NSString *path in paths) {
        if(![path isKindOfClass:NSString.class]||path.length>4095||strlen(path.UTF8String)!=[path lengthOfBytesUsingEncoding:NSUTF8StringEncoding])_exit(74);
        size_t offset=[path.pathExtension.lowercaseString isEqualToString:@"xci"]?0x95cae4:0x95c9d8;
        char *text=((char *(*)(const char *))as_native(offset))(path.fileSystemRepresentation);
        if(text&&strnlen(text,65536)>=65536)_exit(74);
        NSString *title=text?[[NSString alloc] initWithUTF8String:text]:nil;
        if(text)((void(*)(void *))as_native(0x95e050))(text);
        [results addObject:@{@"path":path,@"title":title?:NSNull.null}];
    }
    NSData *output=[NSJSONSerialization dataWithJSONObject:results options:0 error:nil];
    if(![output writeToFile:[as_root stringByAppendingPathComponent:@"astris-inspection.json"] options:NSDataWritingAtomic error:nil])_exit(74);
    as_inspected=YES;[NSApp terminate:nil];
}
__attribute__((constructor)) static void as_startup(void) {
    const char *root=getenv("BROOMM_ASTRIS_ROOT"),*user=getenv("BROOMM_ASTRIS_USER");
    if(!root||!user)_exit(73);
    acquire_session_writer();as_root=@(root);as_user=@(user);as_session=getenv("BROOMM_SESSION")!=NULL;
    if(as_session||getenv("BROOMM_ASTRIS_INSPECT")) {
        const char *token=getenv("BROOMM_ASTRIS_TOKEN");
        NSString *path=[as_root stringByAppendingPathComponent:@"astris-launch-ticket"];
        int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
        char received[65]={0};struct stat info;
        BOOL admitted=token&&strlen(token)==64&&fd>=0&&fstat(fd,&info)==0&&S_ISREG(info.st_mode)&&read(fd,received,65)==64&&strcmp(token,received)==0;
        if(fd>=0)close(fd);
        struct proc_bsdinfo parent;
        pid_t owner=(pid_t)strtol(getenv("BROOMM_LAUNCHER_PID")?:"0",NULL,10);
        if(!admitted||owner<=1||proc_pidinfo(owner,PROC_PIDTBSDINFO,0,&parent,sizeof(parent))!=sizeof(parent)||
           parent.pbi_start_tvsec!=strtoull(getenv("BROOMM_LAUNCHER_SECONDS")?:"",NULL,10)||
           parent.pbi_start_tvusec!=strtoull(getenv("BROOMM_LAUNCHER_MICROSECONDS")?:"",NULL,10))_exit(73);
    }
    as_private_urls();
    as_private_preferences();
    if(as_session||getenv("BROOMM_ASTRIS_INSPECT")) {
        atexit(as_normal_exit);
        as_controllers=[NSMutableArray array];as_ids=[NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            (void)note;
            if(getenv("BROOMM_ASTRIS_INSPECT")) {
                __block int ticks=0;
                [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer){
                    if(as_initialized){[timer invalidate];as_inspect();}
                    else if(++ticks>=100)_exit(74);
                }];
            } else [NSTimer scheduledTimerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer *timer){(void)timer;as_tick();}];
        }];
    }
}
