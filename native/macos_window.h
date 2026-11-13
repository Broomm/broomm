#ifndef BROOMM_MACOS_WINDOW_H
#define BROOMM_MACOS_WINDOW_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

struct MacWindowStatus {
    uint64_t revision;
    bool hidden;
    uint64_t seconds;
    uint64_t microseconds;
};

// The caller holds the input gate and has confirmed pause before ticking.
void broomm_macos_window_observe(void);
void broomm_macos_window_tick(void *window, pid_t launcher, bool hide_windowed);
struct MacWindowStatus broomm_macos_window_status(void);

// Avalonia exposes Ryubing's native pause state in the game window title.
void *broomm_macos_ryubing_window(int *paused);
bool broomm_macos_window_accepts_keys(void *window);

#endif
