#import <AppKit/AppKit.h>
#include <stdatomic.h>
#include <pthread.h>

void broomm_cemu_window_initialize(void) {}
static _Atomic bool game_ready;
bool broomm_cemu_window_ready(void) { return atomic_load(&game_ready); }
static pthread_mutex_t geometry_lock=PTHREAD_MUTEX_INITIALIZER;
static double crop[5];
bool broomm_cemu_window_geometry(double out[5]) {
  pthread_mutex_lock(&geometry_lock);for(int i=0;i<5;++i)out[i]=crop[i];pthread_mutex_unlock(&geometry_lock);return out[0]>0;
}

void broomm_cemu_window_tick(bool playing, bool quit, uint64_t request) {
  static _Atomic bool pending;
  if (atomic_exchange(&pending,true)) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    static NSArray<NSString *> *titles;
    if (!titles) {
      const char *value=getenv("BROOMM_CEMU_PAD_TITLES");
      NSString *text=value ? [NSString stringWithUTF8String:value] : @"GamePad View";
      titles=[text componentsSeparatedByString:@"|"];
    }
    atomic_store(&game_ready,false);
    pthread_mutex_lock(&geometry_lock);crop[0]=0;pthread_mutex_unlock(&geometry_lock);
    NSWindow *main = nil, *pad = nil;
    for (NSWindow *window in NSApp.windows) {
      BOOL secondary=[titles containsObject:window.title];
      for(NSString *title in titles) if([window.title hasPrefix:[title stringByAppendingString:@" - FPS:"]])secondary=YES;
      if (secondary) { if (pad) { atomic_store(&pending,false); return; } pad=window; }
      else if ([window.title hasPrefix:@"Cemu"] && !window.parentWindow && [window canBecomeMainWindow]) {
        if (main) { atomic_store(&pending,false); return; } main=window;
      }
    }
    atomic_store(&game_ready,main&&[main.title containsString:@" - FPS:"]);
    if(pad) {
      NSRect frame=pad.frame,content=[pad contentRectForFrameRect:frame];
      double width=fmin(content.size.width,content.size.height*16.0/9.0),height=width*9.0/16.0;
      pthread_mutex_lock(&geometry_lock);
      crop[0]=(double)pad.windowNumber;
      crop[1]=NSMinX(content)-NSMinX(frame)+(content.size.width-width)/2;
      crop[2]=NSMaxY(frame)-NSMaxY(content)+(content.size.height-height)/2;
      crop[3]=width;crop[4]=height;
      pthread_mutex_unlock(&geometry_lock);
    }else{pthread_mutex_lock(&geometry_lock);crop[0]=0;pthread_mutex_unlock(&geometry_lock);}
    static uint64_t closed_revision=UINT64_MAX;
    if (main && quit && request!=closed_revision) {closed_revision=request;[main performClose:nil];}
    if (main && pad && getenv("BROOMM_REMOTE_SCREEN")) {
      static NSHashTable<NSWindow *> *sized;
      if (!sized) sized=NSHashTable.weakObjectsHashTable;
      for (NSWindow *window in @[pad,main]) if (![sized containsObject:window] && !(window.styleMask & NSWindowStyleMaskFullScreen)) {
        NSScreen *screen=window.screen ?: NSScreen.mainScreen;
        if (screen) { [window setFrame:screen.visibleFrame display:YES]; [sized addObject:window]; }
      }
      static bool ordered;
      if (!playing) ordered=false;
      if (playing && (!ordered || pad.isKeyWindow) && !NSApp.isHidden) {
        [pad orderWindow:NSWindowBelow relativeTo:main.windowNumber];
        [main makeKeyAndOrderFront:nil];
        ordered=true;
      }
    }
    atomic_store(&pending,false);
  });
}
