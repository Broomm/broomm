// Private, process-local input for supported macOS SDL2 emulators.
// The launcher owns the LAN connection. This socket accepts only controller state.
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <errno.h>

static int remote_fd=-1;
#if BROOMM_SDL_MAJOR == 2
static void *remote_joystick;
static uint32_t remote_id=UINT32_MAX;
static double remote_received;
#endif

#if BROOMM_SDL_MAJOR == 2
static void remote_detach(void) {
    if(!remote_joystick)return;
    void (*close_joystick)(void *)=symbol("SDL_JoystickClose");
    int (*detach)(int)=symbol("SDL_JoystickDetachVirtual");
    int (*count)(void)=symbol("SDL_NumJoysticks");
    int (*instance)(int)=symbol("SDL_JoystickGetDeviceInstanceID");
    close_joystick(remote_joystick);remote_joystick=NULL;
    for(int i=0;i<count();++i)if((uint32_t)instance(i)==remote_id){detach(i);break;}
    remote_id=UINT32_MAX;
}
#endif
static void remote_close(void) {
    if(remote_fd>=0){close(remote_fd);remote_fd=-1;}
    const char *path=getenv("BROOMM_REMOTE_SOCKET");
    if(path)unlink(path);
}
static void remote_tick(double now) {
#if BROOMM_SDL_MAJOR == 2
    const char *path=getenv("BROOMM_REMOTE_SOCKET");
    if(!path)return;
    if(remote_fd<0) {
        struct sockaddr_un address={0};
        if(strlen(path)>=sizeof(address.sun_path))return;
        address.sun_family=AF_UNIX;strcpy(address.sun_path,path);
        int fd=socket(AF_UNIX,SOCK_DGRAM,0);
        if(fd<0)return;
        if(bind(fd,(struct sockaddr *)&address,sizeof(address))!=0){close(fd);return;}
        if(fcntl(fd,F_SETFL,O_NONBLOCK)<0||fcntl(fd,F_SETFD,FD_CLOEXEC)<0||chmod(path,0600)!=0) {
            close(fd);unlink(path);return;
        }
        remote_fd=fd;
    }
    char input[192];
    for(int packet=0;packet<64;++packet) {
        ssize_t n=recv(remote_fd,input,sizeof(input)-1,0);
        if(n<0)break;
        input[n]=0;
        unsigned int present,buttons;int axes[6],used=0;
        if(sscanf(input,"%u %u %d %d %d %d %d %d %n",&present,&buttons,
            &axes[0],&axes[1],&axes[2],&axes[3],&axes[4],&axes[5],&used)!=8||
            used!=n||present>1||buttons>0x1fffff)continue;
        bool valid=true;
        for(int a=0;a<6;++a)if(axes[a]<(a>=4?0:-32768)||axes[a]>32767)valid=false;
        if(!valid)continue;
        remote_received=now;
        if(!present){remote_detach();continue;}
        if(!remote_joystick) {
            int (*attach)(int,int,int,int)=symbol("SDL_JoystickAttachVirtual");
            void *(*open_joystick)(int)=symbol("SDL_JoystickOpen");
            int index=attach(1,6,21,1);
            if(index<0)continue;
            remote_joystick=open_joystick(index);
            if(!remote_joystick) {
                int (*detach)(int)=symbol("SDL_JoystickDetachVirtual");detach(index);continue;
            }
            remote_id=joystick_id(remote_joystick);
        }
        int (*button)(void *,int,uint8_t)=symbol("SDL_JoystickSetVirtualButton");
        int (*axis)(void *,int,int16_t)=symbol("SDL_JoystickSetVirtualAxis");
        void (*update)(void)=symbol("SDL_JoystickUpdate");
        for(int b=0;b<21;++b)button(remote_joystick,b,(buttons&(1u<<b))!=0);
        for(int a=0;a<6;++a)axis(remote_joystick,a,(int16_t)(a>=4?axes[a]*2-32768:axes[a]));
        update();
    }
    if(remote_joystick&&now-remote_received>0.35)remote_detach();
#else
    (void)now;
#endif
}
