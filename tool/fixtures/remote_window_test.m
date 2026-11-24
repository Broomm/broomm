#import <AppKit/AppKit.h>
#include <assert.h>
#include "../../native/macos_window.h"

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSMutableArray<NSWindow *> *windows=NSMutableArray.new;
        for(NSString *title in @[@"melonDS [w1]",@"melonDS [w2]",@"Settings"]) {
            NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,512,384)
                styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable
                backing:NSBackingStoreBuffered defer:NO];
            window.title=title;window.releasedWhenClosed=NO;[windows addObject:window];
            [window orderFront:nil];
        }
        NSRect original=windows[0].frame,settings=windows[2].frame;
        broomm_macos_remote_tick(false);
        assert(NSEqualRects(original,windows[0].frame)); // Ordinary launch unchanged.
        setenv("BROOMM_REMOTE_SCREEN","1",1);
        broomm_macos_remote_tick(false);
        for(NSWindow *window in @[windows[0],windows[1]]) {
            assert(NSEqualRects(window.frame,window.screen.visibleFrame));
            assert(!(window.styleMask&NSWindowStyleMaskFullScreen));
        }
        assert(NSEqualRects(settings,windows[2].frame));
        struct MacWindowStatus status=broomm_macos_window_status();
        assert(status.remote_window==(uint32_t)windows[1].windowNumber);
        assert(status.remote_crop[2]>512&&fabs(status.remote_crop[2]/status.remote_crop[3]-4.0/3.0)<0.001);
        [windows[1] setFrame:NSMakeRect(100,100,600,600) display:YES];
        broomm_macos_remote_tick(false);
        status=broomm_macos_window_status();
        assert(status.remote_crop[2]==600&&status.remote_crop[3]==450);
        assert(windows[1].frame.size.width==600); // User resize is not overridden.
        // Stacking the owned windows must not require activating this process.
        broomm_macos_remote_tick(true);
        NSArray<NSWindow *> *ordered=NSApp.orderedWindows;
        assert([ordered indexOfObject:windows[0]]<[ordered indexOfObject:windows[1]]);
        for(NSWindow *window in windows)[window close];
        puts("Remote window maximize, crop, resizing, unrelated windows and primary order passed.");
    }
    return 0;
}
