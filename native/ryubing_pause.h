#ifndef BROOMM_RYUBING_PAUSE_H
#define BROOMM_RYUBING_PAUSE_H

#include <stdint.h>
#include "pause_transition.h"

// Ryubing polls a toggle hotkey. A delivered key can be missed during shader
// loading or a fullscreen transition. Only retry a still-unconfirmed Pause.
#define RYUBING_PAUSE_RETRY_MS 3000
#define RYUBING_PAUSE_DEADLINE_MS 180000

struct RyubingPause {
    struct PauseTransition transition;
    uint64_t started_ms, last_delivery_ms;
    bool timed_out;
};
#define RYUBING_PAUSE_INIT {PAUSE_TRANSITION_INIT, 0, 0, false}

static inline int ryubing_pause_command(struct RyubingPause *control,
        int wanted, int actual, uint64_t release, uint64_t now_ms) {
    if (!wanted || actual == 1) {
        control->started_ms = control->last_delivery_ms = 0;
        control->timed_out = false;
    } else if (actual == 0) {
        if (!control->started_ms) control->started_ms = now_ms;
        if (now_ms - control->started_ms >= RYUBING_PAUSE_DEADLINE_MS) {
            control->timed_out = true;
            return -1;
        }
        if (control->last_delivery_ms) {
            if (now_ms - control->last_delivery_ms < RYUBING_PAUSE_RETRY_MS)
                return -1;
            pause_transition_defer(&control->transition);
        }
    }
    return pause_transition(&control->transition, wanted, actual, release);
}

#endif
