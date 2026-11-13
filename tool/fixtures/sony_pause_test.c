#include <stdio.h>
#include <stdlib.h>
#include "../../native/pause_transition.h"
#include "../../native/ryubing_pause.h"

static void expect(int got,int wanted,const char *context) {
    if(got!=wanted){fprintf(stderr,"%s: expected %d, got %d\n",context,wanted,got);exit(1);}
}

int main(void) {
    struct PauseTransition control=PAUSE_TRANSITION_INIT;
    expect(pause_transition(&control,1,1,0),-1,"initial pause already acknowledged");
    expect(pause_transition(&control,0,1,1),0,"explicit initial play resumes");
    expect(pause_transition(&control,0,0,1),-1,"initial resume acknowledged");
    for(int i=0;i<40;i++)expect(pause_transition(&control,0,1,1),-1,"native pause survives active gameplay and routing polls");
    expect(pause_transition(&control,0,0,1),-1,"native resume needs no bridge write");
    puts("PASS native pause and resume survive steady gameplay");

    expect(pause_transition(&control,1,0,1),1,"Broomm controller gate pauses");
    expect(pause_transition(&control,1,1,1),-1,"gate pause acknowledged");
    expect(pause_transition(&control,1,0,1),1,"gate reasserts pause after native resume");
    expect(pause_transition(&control,1,1,2),-1,"gate cannot consume a release published before the desired-state read");
    expect(pause_transition(&control,0,1,2),0,"explicit gate release resumes");
    expect(pause_transition(&control,0,0,2),-1,"gate resume acknowledged");
    expect(pause_transition(&control,0,1,2),-1,"subsequent native pause remains paused");
    expect(pause_transition(&control,1,1,2),-1,"controller port update can use an already paused CPU");
    expect(pause_transition(&control,0,1,2),-1,"port update that never paused the CPU does not own Resume");
    puts("PASS controller gate keeps pause ownership until explicit release");

    control=(struct PauseTransition)PAUSE_TRANSITION_INIT;
    expect(pause_transition(&control,1,-1,0),-1,"unknown startup does not acknowledge pause");
    expect(pause_transition(&control,1,0,0),1,"pause once native runtime appears");
    for(int i=0;i<40;i++)expect(pause_transition(&control,1,0,0),-1,"pending pause is not flooded");
    expect(pause_transition(&control,0,-1,1),-1,"unknown state cannot consume release");
    expect(pause_transition(&control,0,1,1),0,"release supersedes pending pause");
    for(int i=0;i<40;i++)expect(pause_transition(&control,0,1,1),-1,"pending resume is not flooded");
    expect(pause_transition(&control,0,0,1),-1,"asynchronous resume acknowledged");
    expect(pause_transition(&control,0,1,1),-1,"completed release never resumes a later native pause");
    expect(pause_transition(&control,0,1,2),0,"quick gate and release between UI polls still resumes explicitly");
    pause_transition_defer(&control);
    expect(pause_transition(&control,0,1,2),0,"undelivered resume remains pending until ports/focus are ready");
    expect(pause_transition(&control,0,0,2),-1,"quick release acknowledged");
    expect(pause_transition(&control,0,1,2),-1,"native pause after quick release remains paused");
    puts("PASS pending and unknown native state retain bounded commands");

    struct RyubingPause ryubing=RYUBING_PAUSE_INIT;
    expect(ryubing_pause_command(&ryubing,1,0,0,1000),1,"startup requests pause");
    ryubing.last_delivery_ms=1000;
    expect(ryubing_pause_command(&ryubing,1,0,0,3999),-1,"wait for the hotkey to take effect");
    expect(ryubing_pause_command(&ryubing,1,-1,0,4000),-1,"unknown native state cannot retry a toggle");
    expect(ryubing_pause_command(&ryubing,1,0,0,4001),1,"confirmed running after a lost hotkey retries pause");
    ryubing.last_delivery_ms=4001;
    expect(ryubing_pause_command(&ryubing,1,1,0,8000),-1,"late acknowledgement stops the pause retry");
    expect(ryubing_pause_command(&ryubing,0,1,1,8001),0,"explicit play requests resume");
    expect(ryubing_pause_command(&ryubing,0,1,1,12000),-1,"resume toggle is never repeated");
    expect(ryubing_pause_command(&ryubing,0,0,1,12001),-1,"resume acknowledged");
    expect(ryubing_pause_command(&ryubing,0,1,1,12002),-1,"independent gameplay pause is preserved");
    puts("PASS Ryubing retries a missed pause only while the game is running");

    ryubing=(struct RyubingPause)RYUBING_PAUSE_INIT;
    expect(ryubing_pause_command(&ryubing,1,0,0,1000),1,"begin bounded Ryubing pause");
    ryubing.last_delivery_ms=1000;
    expect(ryubing_pause_command(&ryubing,1,0,0,181000),-1,"retry deadline stops hotkey delivery");
    expect(ryubing.timed_out,true,"publish pause timeout");
    expect(ryubing_pause_command(&ryubing,1,1,0,182000),-1,"manual pause recovers after timeout");
    expect(ryubing.timed_out,false,"confirmed pause clears timeout");
    puts("PASS Ryubing pause timeout is bounded and can recover");
    return 0;
}
