#include <pthread.h>

struct RemoteTouch {bool pressed;int x,y;};
static pthread_mutex_t remote_touch_lock=PTHREAD_MUTEX_INITIALIZER;
static struct RemoteTouch remote_touches[32],remote_touch_applied;
static unsigned remote_touch_head,remote_touch_count;
static double remote_touch_received;
static double remote_touch_pressed_at;
static bool remote_touch_live;
#if BROOMM_SDL_MAJOR == 2
static void remote_touch_enqueue(bool pressed,int x,int y,double now) {
    pthread_mutex_lock(&remote_touch_lock);
    remote_touch_received=now;remote_touch_live=true;
    struct RemoteTouch event={pressed,x,y};
    unsigned tail=(remote_touch_head+remote_touch_count)%32;
    // Coalesce moves/heartbeats, retaining press and release edges.
    if(remote_touch_count&&remote_touches[(tail+31)%32].pressed==pressed)
        remote_touches[(tail+31)%32]=event;
    else if(remote_touch_count<32) {
        remote_touches[tail]=event;remote_touch_count++;
    } else {
        remote_touch_head=0;remote_touch_count=1;
        remote_touches[0]=(struct RemoteTouch){0};
    }
    pthread_mutex_unlock(&remote_touch_lock);
}
#endif
static void remote_touch_expire(double now) {
    pthread_mutex_lock(&remote_touch_lock);
    if(remote_touch_live&&now-remote_touch_received>0.35) {
        remote_touch_live=false;remote_touch_head=0;remote_touch_count=1;
        remote_touches[0]=(struct RemoteTouch){0};
    }
    pthread_mutex_unlock(&remote_touch_lock);
}
// Called only on the frontend main queue; callback uses its native touch fields.
static void remote_touch_poll(bool blocked,double now,void (*apply)(bool,int,int)) {
    pthread_mutex_lock(&remote_touch_lock);
    struct RemoteTouch event={0};bool deliver=false;
    if(blocked) {
        remote_touch_head=remote_touch_count=0;
        deliver=remote_touch_applied.pressed;
    } else if(remote_touch_count) {
        event=remote_touches[remote_touch_head];
        // A batched quick tap must span a DS input frame before release.
        if(event.pressed||!remote_touch_applied.pressed||now-remote_touch_pressed_at>=0.020) {
            remote_touch_head=(remote_touch_head+1)%32;remote_touch_count--;deliver=true;
        }
    }
    pthread_mutex_unlock(&remote_touch_lock);
    if(deliver) {
        if(event.pressed&&!remote_touch_applied.pressed)remote_touch_pressed_at=now;
        apply(event.pressed,event.x,event.y);remote_touch_applied=event;
    }
}
