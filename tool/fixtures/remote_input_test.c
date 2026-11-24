#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#define BROOMM_SDL_MAJOR 2
static bool attached;
static int buttons[21],axes[6],detach_count;
static int attach(int type,int a,int b,int h){assert(type==1&&a==6&&b==21&&h==1);attached=true;return 0;}
static void *open_joystick(int index){assert(index==0);return &attached;}
static uint32_t joystick_id(void *joystick){assert(joystick==&attached);return 7;}
static void close_joystick(void *joystick){assert(joystick==&attached);}
static int detach(int index){assert(index==0);attached=false;detach_count++;return 0;}
static int count(void){return attached?1:0;}
static int instance(int index){assert(index==0);return 7;}
static int button(void *joystick,int b,uint8_t value){assert(joystick==&attached);buttons[b]=value;return 0;}
static int axis(void *joystick,int a,int16_t value){assert(joystick==&attached);axes[a]=value;return 0;}
static void update(void){}
static void *symbol(const char *name){
#define API(n,f) if(!strcmp(name,n))return (void *)f
 API("SDL_JoystickAttachVirtual",attach);API("SDL_JoystickOpen",open_joystick);
 API("SDL_JoystickClose",close_joystick);API("SDL_JoystickDetachVirtual",detach);
 API("SDL_NumJoysticks",count);API("SDL_JoystickGetDeviceInstanceID",instance);
 API("SDL_JoystickSetVirtualButton",button);API("SDL_JoystickSetVirtualAxis",axis);API("SDL_JoystickUpdate",update);
 abort();
}
#include "../../native/remote_input.inc"
static void send_report(int fd,const char *path,const char *text){
 struct sockaddr_un address={0};address.sun_family=AF_UNIX;strcpy(address.sun_path,path);
 assert(sendto(fd,text,strlen(text),0,(struct sockaddr *)&address,sizeof(address))==(ssize_t)strlen(text));
}
int main(void){
 char dir[]="/tmp/brm-input-test-XXXXXX";assert(mkdtemp(dir));
 char path[104];snprintf(path,sizeof(path),"%s/pad",dir);assert(setenv("BROOMM_REMOTE_SOCKET",path,1)==0);
 remote_tick(0);assert(remote_fd>=0);int client=socket(AF_UNIX,SOCK_DGRAM,0);assert(client>=0);
 send_report(client,path,"1 513 12000 -10000 100 -100 0 32767");remote_tick(1);
 assert(attached&&remote_id==7&&buttons[0]&&buttons[9]&&axes[0]==12000&&axes[1]==-10000&&axes[4]==-32768&&axes[5]==32766);
 send_report(client,path,"1 0 0 0 0 0 0 0 trailing");remote_tick(1.2);assert(buttons[0]);
 send_report(client,path,"1 0 0 0 0 0 -1 0");remote_tick(1.3);assert(attached);
 remote_tick(1.36);assert(!attached&&detach_count==1);
 send_report(client,path,"1 0 0 0 0 0 0 0");remote_tick(2);assert(attached&&!buttons[0]);
 send_report(client,path,"0 0 0 0 0 0 0 0");remote_tick(2.1);assert(!attached&&detach_count==2);
 remote_close();assert(access(path,F_OK)!=0);close(client);assert(rmdir(dir)==0);
 puts("Remote input attach, ranges, malformed packets, expiry and reconnect passed.");
 return 0;
}
