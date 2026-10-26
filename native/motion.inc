// SDL sensor ABI adapter, using the emulator's runtime. SI units and SDL's
// right-handed controller coordinate frame pass through unchanged. A stable
// logical port advertises accel/gyro so consumers can initialize before pairing.
// Physical capability/readiness are separate and never inferred from pad names.
#if BROOMM_SDL_MAJOR == 3
typedef bool SensorBool;
typedef bool SensorResult;
#define SENSOR_OK true
#define SENSOR_ERROR false
#define HAS_SENSOR "SDL_GamepadHasSensor"
#define SENSOR_ENABLED "SDL_GamepadSensorEnabled"
#define ENABLE_SENSOR "SDL_SetGamepadSensorEnabled"
#define SENSOR_DATA "SDL_GetGamepadSensorData"
#define SENSOR_RATE "SDL_GetGamepadSensorDataRate"
#else
typedef int SensorBool;
typedef int SensorResult;
#define SENSOR_OK 0
#define SENSOR_ERROR -1
#define HAS_SENSOR "SDL_GameControllerHasSensor"
#define SENSOR_ENABLED "SDL_GameControllerIsSensorEnabled"
#define ENABLE_SENSOR "SDL_GameControllerSetSensorEnabled"
#define SENSOR_DATA "SDL_GameControllerGetSensorData"
#define SENSOR_RATE "SDL_GameControllerGetSensorDataRate"
#endif
static SensorBool (*native_has_sensor)(void *,int),(*native_sensor_enabled)(void *,int);
static SensorResult (*native_enable_sensor)(void *,int,SensorBool);
static SensorResult (*native_sensor_data)(void *,int,float *,int);
static float (*native_sensor_rate)(void *,int);
#if BROOMM_SDL_MAJOR == 3
static bool (*motion_push)(void *);
static uint64_t (*motion_ticks)(void);
#else
static int (*motion_push)(void *);
static uint32_t (*motion_ticks)(void);
#endif
#if BROOMM_SDL_MAJOR == 2
static int (*native_sensor_timestamp)(void *,int,uint64_t *,float *,int);
#endif
static _Atomic unsigned int motion_enabled[4];
static _Atomic uint64_t motion_reads[4][2],motion_events;
static _Atomic uint64_t motion_delivered[4][2];
// Never call SDL, log, push an event, or take another lock while holding this.
static pthread_mutex_t motion_lock=PTHREAD_MUTEX_INITIALIZER;
static float routed_motion[4][2][3],consumed_motion[4][2][3],delivered_motion[4][2][3];
static uint64_t routed_motion_time;
static int test_motion_support[2],test_motion_ready[2];
static float test_motion_data[2][2][3];

static int motion_bit(int type) {return type==1?1:type==2?2:0;}
static uint64_t motion_now(void) {
    struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);
    return (uint64_t)ts.tv_sec*1000000000u+(uint64_t)ts.tv_nsec;
}
static void motion_neutral(int type,float value[3]) {
    value[0]=value[2]=0;value[1]=type==1?9.80665f:0;
}
static SensorBool motion_has(void *handle,int type) {
    if(fixture_index(handle,true)>=0)return motion_bit(type)!=0;
    return native_has_sensor?native_has_sensor(handle,type):0;
}
static SensorBool motion_is_enabled(void *handle,int type) {
    int p=fixture_index(handle,true);
    if(p>=0)return (atomic_load(&motion_enabled[p])&motion_bit(type))!=0;
    return native_sensor_enabled?native_sensor_enabled(handle,type):0;
}
static SensorResult motion_enable(void *handle,int type,SensorBool enable) {
    int p=fixture_index(handle,true),bit=motion_bit(type);
    if(p>=0) {
        if(!bit)return SENSOR_ERROR;
        if(enable)atomic_fetch_or(&motion_enabled[p],(unsigned)bit);
        else atomic_fetch_and(&motion_enabled[p],~(unsigned)bit);
        return SENSOR_OK;
    }
    return native_enable_sensor?native_enable_sensor(handle,type,enable):SENSOR_ERROR;
}
static float motion_rate(void *handle,int type) {
    if(fixture_index(handle,true)>=0)return motion_bit(type)?62.5f:0;
    return native_sensor_rate?native_sensor_rate(handle,type):0;
}
static SensorResult motion_read(void *handle,int type,float *data,int count) {
    int p=fixture_index(handle,true),bit=motion_bit(type);
    if(p<0)return native_sensor_data?native_sensor_data(handle,type,data,count):SENSOR_ERROR;
    if(!bit||!data||count<0||count>3||!(atomic_load(&motion_enabled[p])&bit))return SENSOR_ERROR;
    float value[3];motion_neutral(type,value);
    pthread_mutex_lock(&motion_lock);
    // A disconnect, menu, failed sample or reassignment cannot replay old data.
    if(!atomic_load(&session_gate)&&(type!=2||atomic_load(&gyro_allowed[p]))&&motion_now()-routed_motion_time<100000000u)
        memcpy(value,routed_motion[p][type-1],sizeof(value));
    if(!fixture_call)memcpy(consumed_motion[p][type-1],value,sizeof(value));
    pthread_mutex_unlock(&motion_lock);
    memcpy(data,value,(size_t)count*sizeof(float));
    if(!fixture_call)atomic_fetch_add(&motion_reads[p][type-1],1);
    return SENSOR_OK;
}
#if BROOMM_SDL_MAJOR == 2
static int motion_read_timestamp(void *handle,int type,uint64_t *time,float *data,int count) {
    if(fixture_index(handle,true)<0)return native_sensor_timestamp?native_sensor_timestamp(handle,type,time,data,count):-1;
    int result=motion_read(handle,type,data,count);
    if(result==0&&time)*time=motion_now()/1000;
    return result;
}
#endif
static void install_motion_hooks(void) {
    // These APIs are not intercepted by the bridge. Resolve once rather than
    // searching every loaded image for each sensor event on each port.
    motion_push=symbol("SDL_PushEvent");
#if BROOMM_SDL_MAJOR == 3
    motion_ticks=symbol("SDL_GetTicksNS");
#else
    motion_ticks=symbol("SDL_GetTicks");
#endif
    hook(HAS_SENSOR,motion_has,(void **)&native_has_sensor);
    hook(SENSOR_ENABLED,motion_is_enabled,(void **)&native_sensor_enabled);
    hook(ENABLE_SENSOR,motion_enable,(void **)&native_enable_sensor);
    hook(SENSOR_DATA,motion_read,(void **)&native_sensor_data);
    hook(SENSOR_RATE,motion_rate,(void **)&native_sensor_rate);
#if BROOMM_SDL_MAJOR == 2
    hook("SDL_GameControllerGetSensorDataWithTimestamp",motion_read_timestamp,(void **)&native_sensor_timestamp);
#endif
}
static void motion_close_source(struct Source *source) {
    if(native_enable_sensor)for(int type=1;type<=2;++type)
        if(source->sensor_owned&motion_bit(type))native_enable_sensor(source->handle,type,0);
}
static void motion_sample_source(struct Source *source) {
    source->sensors=native_has_sensor&&native_enable_sensor&&native_sensor_data?0:-1;
    source->sensor_ready=0;source->motion_time=motion_now();
    for(int type=1;type<=2;++type) {
        int bit=motion_bit(type);float *value=source->motion[type-1];motion_neutral(type,value);
        int test=-1;
        if(session_test&&getenv("BROOMM_TEST_MOTION"))
            for(int i=0;i<2;++i)if(source->id==test_ids[i])test=i;
        bool supported=false,ready=false;
        if(test>=0) {
            supported=(test_motion_support[test]&bit)!=0;
            ready=supported&&(test_motion_ready[test]&bit);
            if(ready)memcpy(value,test_motion_data[test][type-1],3*sizeof(float));
        } else if(source->sensors>=0&&native_has_sensor(source->handle,type)) {
            supported=true;
            bool enabled=native_sensor_enabled&&native_sensor_enabled(source->handle,type);
            if(!enabled&&native_enable_sensor(source->handle,type,1)==SENSOR_OK) {
                source->sensor_owned|=bit;enabled=true;
            }
            ready=enabled&&native_sensor_data(source->handle,type,value,3)==SENSOR_OK;
        }
        if(supported)source->sensors|=bit;
        for(int axis=0;axis<3;++axis)if(!isfinite(value[axis]))ready=false;
        if(ready)source->sensor_ready|=bit;else motion_neutral(type,value);
    }
}
static void motion_route_and_emit(bool emit) {
    float values[4][2][3];
    for(int p=0;p<4;++p)for(int type=1;type<=2;++type) {
        motion_neutral(type,values[p][type-1]);
        if(!atomic_load(&session_gate)&&(type!=2||atomic_load(&gyro_allowed[p])))for(int i=0;i<source_count;++i)
            if(routes[p]==sources[i].id&&(sources[i].sensor_ready&motion_bit(type)))
                memcpy(values[p][type-1],sources[i].motion[type-1],3*sizeof(float));
    }
    pthread_mutex_lock(&motion_lock);
    memcpy(routed_motion,values,sizeof(values));routed_motion_time=motion_now();
    pthread_mutex_unlock(&motion_lock);
    if(!emit)return;
    // Cached consumers (Azahar) require sensor events as well as polling APIs.
    for(int p=0;p<4;++p)for(int type=1;type<=2;++type) {
        if(ids[p]==UINT32_MAX||!(atomic_load(&motion_enabled[p])&motion_bit(type)))continue;
        _Alignas(8) unsigned char event[EVENT_SIZE]={0};uint32_t kind=0x659;
        memcpy(event,&kind,4);uint32_t id=ids[p];
#if BROOMM_SDL_MAJOR == 3
        uint64_t now=motion_ticks?motion_ticks():motion_now();
        memcpy(event+8,&now,8);memcpy(event+16,&id,4);memcpy(event+20,&type,4);
        memcpy(event+24,values[p][type-1],12);memcpy(event+40,&now,8);
#else
        uint32_t now=motion_ticks?motion_ticks():0;uint64_t us=motion_now()/1000;
        memcpy(event+4,&now,4);memcpy(event+8,&id,4);memcpy(event+12,&type,4);
        memcpy(event+16,values[p][type-1],12);memcpy(event+32,&us,8);
#endif
        if(motion_push&&motion_push(event)>0)atomic_fetch_add(&motion_events,1);
    }
}
static void motion_write_status(FILE *out) {
    fprintf(out,",\"requestDevice\":%u",request_device);
    fprintf(out,",\"gyroEnabled\":[");
    for(int p=0;p<4;++p)fprintf(out,"%s%d",p?",":"",atomic_load(&gyro_allowed[p]));
    fputc(']',out);
    fprintf(out,",\"motionEvents\":%llu,\"motionReads\":[",(unsigned long long)atomic_load(&motion_events));
    for(int p=0;p<4;++p)fprintf(out,"%s[%llu,%llu]",p?",":"",(unsigned long long)atomic_load(&motion_reads[p][0]),(unsigned long long)atomic_load(&motion_reads[p][1]));
    fprintf(out,"],\"motionDelivered\":[");
    for(int p=0;p<4;++p)fprintf(out,"%s[%llu,%llu]",p?",":"",(unsigned long long)atomic_load(&motion_delivered[p][0]),(unsigned long long)atomic_load(&motion_delivered[p][1]));
    float routed[4][2][3],consumed[4][2][3],delivered[4][2][3];
    pthread_mutex_lock(&motion_lock);memcpy(routed,routed_motion,sizeof(routed));memcpy(consumed,consumed_motion,sizeof(consumed));memcpy(delivered,delivered_motion,sizeof(delivered));pthread_mutex_unlock(&motion_lock);
    const float (*arrays[3])[2][3]={routed,consumed,delivered};
    const char *names[3]={"logicalMotion","consumedMotion","deliveredMotion"};
    for(int which=0;which<3;++which) {
        fprintf(out,"],\"%s\":[",names[which]);
        for(int p=0;p<4;++p)for(int t=0;t<2;++t) {
            if(t==0)fprintf(out,"%s[",p?",":"");
            fprintf(out,"%s[%.6f,%.6f,%.6f]",t?",":"",arrays[which][p][t][0],arrays[which][p][t][1],arrays[which][p][t][2]);
            if(t==1)fputc(']',out);
        }
    }
    fputc(']',out);
}
static void motion_observe_event(const void *event) {
    uint32_t type,id;int sensor;
    memcpy(&type,event,4);if(type!=0x659)return;
    memcpy(&id,(const char *)event+ID_OFFSET,4);
    memcpy(&sensor,(const char *)event+ID_OFFSET+4,4);
    if(!motion_bit(sensor))return;
    for(int p=0;p<4;++p)if(ids[p]!=UINT32_MAX&&ids[p]==id) {
        pthread_mutex_lock(&motion_lock);
        memcpy(delivered_motion[p][sensor-1],(const char *)event+ID_OFFSET+8,12);
        pthread_mutex_unlock(&motion_lock);
        atomic_fetch_add(&motion_delivered[p][sensor-1],1);
    }
}
