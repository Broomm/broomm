#ifndef BROOMM_LINUX_WINDOW_HANDOFF_H_
#define BROOMM_LINUX_WINDOW_HANDOFF_H_

#include <stdbool.h>
#include <unistd.h>

// The launcher publishes this marker after its Gamescope window is mapped.
// An unblocked game and orphan recovery always keep the emulator visible.
static inline bool broomm_hide_game_window(bool blocked, bool orphaned,
                                           const char *mapped_launcher) {
    return blocked && !orphaned &&
           (!mapped_launcher || access(mapped_launcher, F_OK) == 0);
}

#endif
