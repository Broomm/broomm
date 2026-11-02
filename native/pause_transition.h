#ifndef BROOMM_PAUSE_TRANSITION_H
#define BROOMM_PAUSE_TRANSITION_H
#include <stdbool.h>

struct PauseTransition {
    int previous_wanted, requested;
    bool resume_pending;
    unsigned long long seen_release;
};
#define PAUSE_TRANSITION_INIT {1, -1, false, 0}

// The caller could not deliver the proposed command (for example, a window
// still needs focus or controller sockets are not ready). Keep it pending.
static inline void pause_transition_defer(struct PauseTransition *control) {
    control->requested=-1;
}

// A Broomm gate owns Pause until released. Resume belongs only to that release,
// not to steady-state gameplay polling: the emulator can pause independently.
// Return -1 to observe only, or the native pause value to request once.
static inline int pause_transition(struct PauseTransition *control, int wanted, int actual,
        unsigned long long release_serial) {
    if(actual!=0&&actual!=1)return -1;
    if(wanted!=control->previous_wanted) {
        control->previous_wanted=wanted;
        control->requested=-1;
        if(wanted)control->resume_pending=false;
    }
    if(!wanted&&release_serial!=control->seen_release) {
        control->seen_release=release_serial;
        control->resume_pending=true;
        control->requested=-1;
    }
    if(actual==wanted) {
        control->requested=-1;
        if(!wanted)control->resume_pending=false;
        return -1;
    }
    if((!wanted&&!control->resume_pending)||control->requested==wanted)return -1;
    control->requested=wanted;
    return wanted;
}
#endif
