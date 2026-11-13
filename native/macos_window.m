#import <AppKit/AppKit.h>
#include <libproc.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>
#include "macos_window.h"

typedef NS_ENUM(NSInteger, WindowMode) {
    WindowModeNone,
    WindowModeWindowed,
    WindowModeNativeFullscreen,
    WindowModeBorderlessFullscreen,
};

// Window objects and transitions are confined to AppKit's main queue. The
// controller worker reads the acknowledgement as a single atomic snapshot.
static _Atomic uint64_t window_ack;
static __weak NSWindow *game_window;
static WindowMode original_mode;
static uint64_t toggle_revision, activation_revision, hide_revision;
static NSMapTable<NSWindow *, NSNumber *> *transitions;
static pthread_once_t birth_once = PTHREAD_ONCE_INIT;
static uint64_t birth_seconds, birth_microseconds;

void broomm_macos_window_observe(void) {
    if (!getenv("BROOMM_MAC_WINDOW_COMMAND")) return;
    if (transitions) return;
    transitions = NSMapTable.weakToStrongObjectsMapTable;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSWindowWillEnterFullScreenNotification,
                                      NSWindowWillExitFullScreenNotification]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            [transitions setObject:@(NSProcessInfo.processInfo.systemUptime + 4)
                            forKey:note.object];
        }];
    }
    for (NSNotificationName name in @[NSWindowDidEnterFullScreenNotification,
                                      NSWindowDidExitFullScreenNotification,
                                      NSWindowWillCloseNotification]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            [transitions removeObjectForKey:note.object];
            if ([note.name isEqualToString:NSWindowWillCloseNotification] &&
                note.object == game_window) game_window = nil;
        }];
    }
}

static bool transitioning(NSWindow *window) {
    return window && [transitions objectForKey:window].doubleValue >
        NSProcessInfo.processInfo.systemUptime;
}

static WindowMode window_mode(NSWindow *window) {
    if (window.styleMask & NSWindowStyleMaskFullScreen) return WindowModeNativeFullscreen;
    if (window.styleMask & NSWindowStyleMaskTitled) return WindowModeWindowed;
    NSScreen *screen = window.screen;
    if (!screen) return WindowModeWindowed;
    NSRect frame = window.frame, display = screen.frame;
    // Borderless fullscreen has no Space to leave. Ignore maximized titled
    // windows, work-area-sized windows and floating panels.
    const CGFloat tolerance = 1.0;
    if (fabs(NSMinX(frame) - NSMinX(display)) <= tolerance &&
        fabs(NSMinY(frame) - NSMinY(display)) <= tolerance &&
        fabs(NSMaxX(frame) - NSMaxX(display)) <= tolerance &&
        fabs(NSMaxY(frame) - NSMaxY(display)) <= tolerance) return WindowModeBorderlessFullscreen;
    return WindowModeWindowed;
}

static bool candidate(NSWindow *window) {
    return window && ![window isKindOfClass:NSPanel.class] && !window.parentWindow &&
        (window.isVisible || window.isMiniaturized || transitioning(window));
}

void *broomm_macos_ryubing_window(int *paused) {
    NSWindow *game = nil;
    // The game title is still readable while the emulator is hidden. Prefer
    // the active game window during native fullscreen transitions.
    for (NSWindow *window in NSApp.windows) {
        NSString *title = window.title;
        if (![title containsString:@"(64-bit)"] && ![title containsString:@"(32-bit)"] &&
            ![title containsString:@"Paused"]) continue;
        if (window.isKeyWindow) {
            game = window;
            break;
        }
        if (!game || (!game.isVisible && window.isVisible)) game = window;
    }
    if (paused) *paused = game ? (int)[game.title containsString:@"Paused"] : -1;
    return (__bridge void *)game;
}

bool broomm_macos_window_accepts_keys(void *target) {
    NSWindow *window = (__bridge NSWindow *)target;
    return window.isVisible && window.isKeyWindow && window.isOnActiveSpace &&
        NSApp.isActive && !transitioning(window);
}

static NSWindow *find_window(NSWindow *preferred) {
    // Prefer the bridge's game window. When a separate library window is
    // present, identify a unique fullscreen game window owned by this process.
    if (candidate(preferred) &&
        (transitioning(preferred) || window_mode(preferred) != WindowModeWindowed)) return preferred;
    NSWindow *fullscreen = nil;
    for (NSWindow *window in NSApp.windows) {
        if (!candidate(window) || (!transitioning(window) && window_mode(window) == WindowModeWindowed))
            continue;
        if (fullscreen) return nil;
        fullscreen = window;
    }
    return fullscreen ?: (candidate(preferred) ? preferred : nil);
}

void broomm_macos_window_tick(void *preferred, pid_t launcher, bool hide_windowed) {
    const char *path = getenv("BROOMM_MAC_WINDOW_COMMAND");
    if (!path || launcher <= 1) return;
    FILE *file = fopen(path, "r");
    if (!file) return;
    int target, menu;
    unsigned long long revision;
    int count = fscanf(file, "%d %llu %d", &target, &revision, &menu);
    fclose(file);
    if (count != 3 || target != getpid() || (menu != 0 && menu != 1) ||
        revision > UINT64_MAX / 2 || revision <= (atomic_load(&window_ack) >> 1)) return;
    NSWindow *window = game_window;
    // Some frontends recreate their native window when leaving a Space. The
    // app's hidden state remains observable even if the original Cocoa
    // object has closed. Find the replacement after the app is shown again.
    if (menu && original_mode != WindowModeNone && NSApp.isHidden) {
        atomic_store(&window_ack, (revision << 1) | 1);
        return;
    }
    if (menu && original_mode == WindowModeNone) {
        window = find_window((__bridge NSWindow *)preferred);
        if (!window || transitioning(window)) return;
        WindowMode mode = window_mode(window);
        if (mode == WindowModeWindowed && !hide_windowed) {
            atomic_store(&window_ack, revision << 1);
            return;
        }
        game_window = window;
        original_mode = mode;
    } else if (!menu && original_mode == WindowModeNone) {
        atomic_store(&window_ack, revision << 1);
        return;
    }
    if (!menu && (NSApp.isHidden || !NSApp.isActive)) {
        if (activation_revision != revision) {
            activation_revision = revision;
            if (NSApp.isHidden) [NSApp unhideWithoutActivation];
            if (@available(macOS 14.0, *)) [NSApp activate];
            else [NSApp activateIgnoringOtherApps:YES];
        }
        return;
    }

    if (!candidate(window)) {
        window = find_window((__bridge NSWindow *)preferred);
        if (window) game_window = window;
    }
    if (!window || transitioning(window)) return;
    if (!menu && window.isMiniaturized) {
        [window deminiaturize:nil];
        return;
    }

    if (original_mode == WindowModeNativeFullscreen &&
        ((window.styleMask & NSWindowStyleMaskFullScreen) != 0) == (bool)menu) {
        if (toggle_revision != revision) {
            toggle_revision = revision;
            [window toggleFullScreen:nil];
        }
        return;
    }

    if (menu) {
        if (hide_revision != revision) {
            hide_revision = revision;
            if (@available(macOS 14.0, *)) {
                NSRunningApplication *owner =
                    [NSRunningApplication runningApplicationWithProcessIdentifier:launcher];
                if (owner) [NSApp yieldActivationToApplication:owner];
            }
            [NSApp hide:nil];
        }
        return;
    }

    if (!window.isVisible || !window.isOnActiveSpace || window_mode(window) != original_mode)
        return;
    game_window = nil;
    original_mode = WindowModeNone;
    atomic_store(&window_ack, revision << 1);
}

static void read_birth(void) {
    struct proc_bsdinfo info = {0};
    if (getenv("BROOMM_MAC_WINDOW_COMMAND") &&
        proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info)) {
        birth_seconds = info.pbi_start_tvsec;
        birth_microseconds = info.pbi_start_tvusec;
    }
}

struct MacWindowStatus broomm_macos_window_status(void) {
    pthread_once(&birth_once, read_birth);
    uint64_t ack = atomic_load(&window_ack);
    return (struct MacWindowStatus){ack >> 1, (ack & 1) != 0,
        birth_seconds, birth_microseconds};
}
