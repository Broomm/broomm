// Calls the selected emulator's built-in debugger API from inside that process.
// The connection survives Broomm exiting, so a debugger detach cannot resume an
// orphaned game. No guest memory/register access or external debugger is used.
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/random.h>
#include <dirent.h>
static _Atomic int control_port,control_paused=-1;
static _Atomic bool control_failed,control_finished=true;
static int control_fd=-1;
static double control_deadline;
static double control_now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static void control_begin(void){control_deadline=control_now()+2.0;}
static void linux_sdk_window_tick(void);
int bind(int fd,const struct sockaddr *address,socklen_t length) {
 int (*next)(int,const struct sockaddr *,socklen_t)=dlsym(RTLD_NEXT,"bind");
 int port=atomic_load(&control_port);
 if(port&&address&&address->sa_family==AF_INET&&length>=sizeof(struct sockaddr_in)) {
  struct sockaddr_in local=*(const struct sockaddr_in *)address;
  if(ntohs(local.sin_port)==port||local.sin_addr.s_addr==htonl(INADDR_ANY)){local.sin_addr.s_addr=htonl(INADDR_LOOPBACK);return next(fd,(void *)&local,sizeof(local));}
 } else if(port&&address&&address->sa_family==AF_INET6&&length>=sizeof(struct sockaddr_in6)) {
  struct sockaddr_in6 local=*(const struct sockaddr_in6 *)address;
  if(ntohs(local.sin6_port)==port||IN6_IS_ADDR_UNSPECIFIED(&local.sin6_addr)){local.sin6_addr=in6addr_loopback;return next(fd,(void *)&local,sizeof(local));}
 }
 return next(fd,address,length);
}
int getaddrinfo(const char *node,const char *service,const struct addrinfo *hints,struct addrinfo **out) {
 int (*next)(const char *,const char *,const struct addrinfo *,struct addrinfo **)=dlsym(RTLD_NEXT,"getaddrinfo");
 // PPSSPP's debugger otherwise advertises the local server to its discovery
 // service. This opt-in private endpoint is never a remote/discoverable server.
 if(atomic_load(&control_port)&&node&&!strcmp(node,"report.ppsspp.org"))return EAI_NONAME;
 return next(node,service,hints,out);
}
static int own_listener(int port) {
 DIR *directory=opendir("/proc/self/fd");if(!directory)return false;
 struct dirent *item;int found=0;
 while((item=readdir(directory))) {
  char *end;long fd=strtol(item->d_name,&end,10);if(*end||fd<0||fd>INT32_MAX)continue;
  int listening=0;socklen_t size=sizeof(listening);
  if(getsockopt((int)fd,SOL_SOCKET,SO_ACCEPTCONN,&listening,&size)||!listening)continue;
  struct sockaddr_storage a;socklen_t length=sizeof(a);if(getsockname((int)fd,(void *)&a,&length))continue;
  if(a.ss_family==AF_INET){struct sockaddr_in *ip=(void *)&a;if(ntohs(ip->sin_port)==port&&ntohl(ip->sin_addr.s_addr)==INADDR_LOOPBACK)found=AF_INET;}
  if(a.ss_family==AF_INET6){struct sockaddr_in6 *ip=(void *)&a;if(ntohs(ip->sin6_port)==port&&IN6_IS_ADDR_LOOPBACK(&ip->sin6_addr)&&!found)found=AF_INET6;}
 }
 closedir(directory);return found;
}
static bool control_io(void *bytes,size_t size,bool write_data) {
 unsigned char *p=bytes;
 while(size&&!atomic_load(&session_finishing)) {
  if(control_now()>=control_deadline)return false;
  ssize_t n=write_data?send(control_fd,p,size,MSG_NOSIGNAL):recv(control_fd,p,size,0);
  if(n<0&&errno==EINTR)continue;if(n<=0)return false;p+=n;size-=(size_t)n;
 }
 return size==0;
}
static int control_connect(void) {
 int port=atomic_load(&control_port),family=own_listener(port);if(!family)return -1;
 int fd=socket(family,SOCK_STREAM|SOCK_CLOEXEC,0);if(fd<0)return -1;
 struct timeval timeout={.tv_sec=0,.tv_usec=700000};
 setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
 struct sockaddr_in target={.sin_family=AF_INET,.sin_port=htons((uint16_t)port),.sin_addr={.s_addr=htonl(INADDR_LOOPBACK)}};
 struct sockaddr_in6 target6={.sin6_family=AF_INET6,.sin6_port=htons((uint16_t)port),.sin6_addr=IN6ADDR_LOOPBACK_INIT};
 if(connect(fd,family==AF_INET?(void *)&target:(void *)&target6,family==AF_INET?sizeof(target):sizeof(target6))){close(fd);return -1;}return fd;
}
static bool rsp_send(const char *text) {
 char packet[128];unsigned sum=0;for(const unsigned char *p=(const void *)text;*p;++p)sum+=*p;
 int n=snprintf(packet,sizeof(packet),"$%s#%02x",text,sum&255);return n>0&&n<(int)sizeof(packet)&&control_io(packet,(size_t)n,true);
}
static int hex_digit(unsigned char c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:-1;}
static bool rsp_read(char out[256]) {
 unsigned char c;int scan=0;do{if(!control_io(&c,1,false)||++scan>256)return false;}while(c!='$');
 unsigned checksum=0;size_t n=0;
 while(control_io(&c,1,false)&&c!='#'){if(n>=255||c=='}'||c=='*')return false;out[n++]=(char)c;checksum+=c;}
 if(c!='#')return false;out[n]=0;unsigned char tail[2];if(!control_io(tail,2,false))return false;
 int a=hex_digit(tail[0]),b=hex_digit(tail[1]);if(a<0||b<0||(checksum&255)!=(unsigned)(a*16+b))return false;
 char ack='+';return control_io(&ack,1,true);
}
static bool rsp_stop_reply(void){char packet[256];return rsp_read(packet)&&packet[0]=='T'&&strlen(packet)>=3&&hex_digit(packet[1])>=0&&hex_digit(packet[2])>=0;}
// Small SHA-1/base64 implementation for the WebSocket handshake only. It is not
// a content-integrity or credential primitive. All frames are bounded to 32KiB.
static uint32_t rol32(uint32_t x,unsigned n){return x<<n|x>>(32-n);}
static void handshake_sha1(const unsigned char *input,size_t size,unsigned char digest[20]) {
 unsigned char data[128]={0};if(size>119)return;memcpy(data,input,size);data[size]=0x80;
 size_t total=size<56?64:128;uint64_t bits=(uint64_t)size*8;for(int i=0;i<8;++i)data[total-1-(size_t)i]=(unsigned char)(bits>>(i*8));
 uint32_t h[5]={0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0};
 for(size_t offset=0;offset<total;offset+=64){uint32_t w[80];for(int i=0;i<16;++i){const unsigned char *p=data+offset+i*4;w[i]=(uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}for(int i=16;i<80;++i)w[i]=rol32(w[i-3]^w[i-8]^w[i-14]^w[i-16],1);
  uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4];for(int i=0;i<80;++i){uint32_t f=i<20?(b&c)|(~b&d):i<40?b^c^d:i<60?(b&c)|(b&d)|(c&d):b^c^d;uint32_t k=i<20?0x5a827999:i<40?0x6ed9eba1:i<60?0x8f1bbcdc:0xca62c1d6;uint32_t t=rol32(a,5)+f+e+k+w[i];e=d;d=c;c=rol32(b,30);b=a;a=t;}h[0]+=a;h[1]+=b;h[2]+=c;h[3]+=d;h[4]+=e;
 }
 for(int i=0;i<20;++i)digest[i]=(unsigned char)(h[i/4]>>(24-(i%4)*8));
}
static void base64(const unsigned char *bytes,size_t n,char *out) {
 static const char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";size_t k=0;
 for(size_t i=0;i<n;i+=3){uint32_t v=(uint32_t)bytes[i]<<16;if(i+1<n)v|=(uint32_t)bytes[i+1]<<8;if(i+2<n)v|=bytes[i+2];out[k++]=alphabet[v>>18];out[k++]=alphabet[v>>12&63];out[k++]=i+1<n?alphabet[v>>6&63]:'=';out[k++]=i+2<n?alphabet[v&63]:'=';}out[k]=0;
}
static bool ws_handshake(void) {
 unsigned char random[16],digest[20];if(getrandom(random,sizeof(random),0)!=(ssize_t)sizeof(random))return false;
 char key[25],accept[29],hash_input[80],request[512],response[4096];base64(random,sizeof(random),key);
 snprintf(hash_input,sizeof(hash_input),"%s258EAFA5-E914-47DA-95CA-C5AB0DC85B11",key);handshake_sha1((void *)hash_input,strlen(hash_input),digest);base64(digest,sizeof(digest),accept);
 int n=snprintf(request,sizeof(request),"GET /debugger HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Protocol: debugger.ppsspp.org\r\n\r\n",atomic_load(&control_port),key);
 if(n<=0||n>=(int)sizeof(request)||!control_io(request,(size_t)n,true))return false;
 size_t used=0;while(used+1<sizeof(response)){if(!control_io(response+used,1,false))return false;response[++used]=0;if(used>=4&&!strcmp(response+used-4,"\r\n\r\n"))break;}
 if(used+1>=sizeof(response)||strncmp(response,"HTTP/1.1 101 ",13))return false;
 char expected[64];snprintf(expected,sizeof(expected),"Sec-WebSocket-Accept: %s\r\n",accept);
 return strcasestr(response,expected)!=NULL&&strcasestr(response,"Sec-WebSocket-Protocol: debugger.ppsspp.org\r\n")!=NULL;
}
static bool ws_send(int opcode,const char *text,size_t size) {
 if(size>32768)return false;unsigned char header[8],mask[4];if(getrandom(mask,4,0)!=4)return false;
 size_t n=0;header[n++]=(unsigned char)(0x80|opcode);if(size<126)header[n++]=(unsigned char)(0x80|size);else{header[n++]=0xfe;header[n++]=(unsigned char)(size>>8);header[n++]=(unsigned char)size;}memcpy(header+n,mask,4);n+=4;
 unsigned char payload[32768];for(size_t i=0;i<size;++i)payload[i]=(unsigned char)text[i]^mask[i%4];return control_io(header,n,true)&&control_io(payload,size,true);
}
static bool ws_read(char out[32769]) {
 size_t used=0;bool started=false;
 for(int frames=0;frames<32;++frames){unsigned char h[2];if(!control_io(h,2,false)||(h[0]&0x70)||(h[1]&0x80))return false;uint64_t n=h[1]&127;int opcode=h[0]&15;
  if(n==126){unsigned char size[2];if(!control_io(size,2,false))return false;n=(unsigned)size[0]*256+size[1];}else if(n==127)return false;
  if(n>32768||used+n>32768)return false;
  if(opcode>=8){char extra[125];if(n>125||!(h[0]&128)||!control_io(extra,(size_t)n,false))return false;if(opcode==8)return false;if(opcode==9&&!ws_send(10,extra,(size_t)n))return false;if(opcode!=9&&opcode!=10)return false;continue;}
  if((!started&&opcode!=1)||(started&&opcode!=0))return false;started=true;if(!control_io(out+used,(size_t)n,false))return false;used+=(size_t)n;
  if(h[0]&128){out[used]=0;return true;}
 }return false;
}
// Strict structural JSON scanner; field lookup applies only to the root object.
// Quoted/nested game titles can never masquerade as an acknowledgement.
static const char *json_space(const char *p){while(*p==' '||*p=='\t'||*p=='\n'||*p=='\r')++p;return p;}
static const char *json_value(const char *p,int depth) {
 p=json_space(p);if(depth>24)return NULL;
 if(*p=='"'){for(++p;*p;++p){if((unsigned char)*p<32)return NULL;if(*p=='"')return p+1;if(*p=='\\'){++p;if(!*p)return NULL;if(*p=='u'){for(int i=0;i<4;++i)if(hex_digit((unsigned char)*++p)<0)return NULL;}else if(!strchr("\"\\/bfnrt",*p))return NULL;}}return NULL;}
 if(*p=='{'||*p=='['){char closing=*p=='{'?'}':']';bool object=*p=='{';p=json_space(p+1);if(*p==closing)return p+1;for(;;){if(object){if(*p!='"'||!(p=json_value(p,depth+1)))return NULL;p=json_space(p);if(*p++!=':')return NULL;}p=json_value(p,depth+1);if(!p)return NULL;p=json_space(p);if(*p==closing)return p+1;if(*p++!=',')return NULL;p=json_space(p);}}
 for(const char **word=(const char *[]) {"true","false","null",NULL};*word;++word)if(!strncmp(p,*word,strlen(*word)))return p+strlen(*word);
 if(*p=='-')++p;if(*p=='0')++p;else{if(*p<'1'||*p>'9')return NULL;while(*p>='0'&&*p<='9')++p;}
 if(*p=='.'){++p;if(*p<'0'||*p>'9')return NULL;while(*p>='0'&&*p<='9')++p;}
 if(*p=='e'||*p=='E'){++p;if(*p=='+'||*p=='-')++p;if(*p<'0'||*p>'9')return NULL;while(*p>='0'&&*p<='9')++p;}return p;
}
static bool json_field(const char *json,const char *key,char *out,size_t capacity) {
 const char *end=json_value(json,0);if(!end||*json_space(end))return false;
 const char *p=json_space(json);if(*p++!='{')return false;p=json_space(p);bool found=false;
 while(*p!='}') {const char *name=p,*after=json_value(p,1);if(!after)return false;p=json_space(after);if(*p++!=':')return false;p=json_space(p);after=json_value(p,1);if(!after)return false;
  if((size_t)(json_value(name,1)-name)==strlen(key)+2&&!memcmp(name+1,key,strlen(key))){if(found||(size_t)(after-p)>=capacity)return false;memcpy(out,p,(size_t)(after-p));out[after-p]=0;found=true;}
  p=json_space(after);if(*p=='}')break;if(*p++!=',')return false;p=json_space(p);
 }return found;
}
static unsigned long ws_ticket;
static bool ws_command(const char *event,unsigned long ticket) {char text[128];int n=snprintf(text,sizeof(text),"{\"event\":\"%s\",\"ticket\":%lu}",event,ticket);return n>0&&n<(int)sizeof(text)&&ws_send(1,text,(size_t)n);}
static bool ws_query(const char *event,char out[32769],bool *step_seen) {
 unsigned long ticket=++ws_ticket;if(!ws_command(event,ticket))return false;
 for(int i=0;i<64;++i){if(!ws_read(out))return false;char value[64];if(json_field(out,"event",value,sizeof(value))&&!strcmp(value,"\"cpu.stepping\""))*step_seen=true;
  if(json_field(out,"ticket",value,sizeof(value))){char *end;unsigned long answer=strtoul(value,&end,10);if(!*end&&answer==ticket){char expected[96];snprintf(expected,sizeof(expected),"\"%s\"",event);return json_field(out,"event",value,sizeof(value))&&!strcmp(expected,value);}}
 }return false;
}
static bool psp_control_tick(struct PauseTransition *transition,bool *step_seen) {
 char reply[32769],value[4096];if(!ws_query("game.status",reply,step_seen)||!json_field(reply,"game",value,sizeof(value)))return false;
 if(!strcmp(value,"null")){atomic_store(&control_paused,-1);return true;}
 if(!ws_query("cpu.status",reply,step_seen)||!json_field(reply,"stepping",value,sizeof(value)))return false;
 int actual=!strcmp(value,"true")?1:!strcmp(value,"false")?0:-1;if(actual<0)return false;
 int command=session_pause_command(transition,atomic_load(&session_wanted),actual);
 if(command>=0){*step_seen=false;if(!ws_command(command?"cpu.stepping":"cpu.resume",++ws_ticket))return false;}
 // cpu.stepping's asynchronous event is emitted by the core's stepping loop.
 // A requested break alone is never sufficient to publish pairing readiness.
 atomic_store(&control_paused,actual==1&&!*step_seen?-1:actual);return true;
}
static void *control_worker(void *unused) {
 (void)unused;bool psp=getenv("BROOMM_PPSSPP")!=NULL;struct PauseTransition transition=PAUSE_TRANSITION_INIT;
 while(!atomic_load(&session_finishing)) {
  control_fd=control_connect();if(control_fd<0){usleep(100000);continue;}
  control_begin();bool ready=false,step_seen=false;
  if(psp){char reply[32769];ready=ws_handshake()&&ws_query("version",reply,&step_seen);}
  else ready=rsp_send("?")&&rsp_stop_reply();
  if(!psp&&ready)atomic_store(&control_paused,1);
  record("NATIVE_CONTROL connected=%d protocol=%s",ready,psp?"PPSSPP-WebSocket":"Ryubing-GDB");
  while(ready&&!atomic_load(&session_finishing)) {
   control_begin();
   if(psp)ready=psp_control_tick(&transition,&step_seen);
   else {
    int actual=atomic_load(&control_paused),command=session_pause_command(&transition,atomic_load(&session_wanted),actual);
    if(command==1){char interrupt=3;ready=control_io(&interrupt,1,true)&&rsp_stop_reply();if(ready)atomic_store(&control_paused,1);}
    if(command==0){char reply[256];ready=rsp_send("c")&&rsp_send("qAttached")&&rsp_read(reply)&&!strcmp(reply,"1");if(ready)atomic_store(&control_paused,0);}
   }
   if(!psp)linux_sdk_window_tick();
   usleep(50000);
  }
  atomic_store(&control_paused,-1);if(!atomic_load(&session_finishing))atomic_store(&control_failed,true);close(control_fd);control_fd=-1;pause_transition_defer(&transition);
 }
 if(!psp&&atomic_load(&session_quit)){for(int i=0;i<1000&&!atomic_load(&session_worker_stopped);++i)usleep(1000);linux_sdk_window_tick();}
 atomic_store(&control_finished,true);return NULL;
}
static void start_control(void) {
 const char *value=getenv("BROOMM_NATIVE_CONTROL_PORT");if(!value)return;
 char *end;long port=strtol(value,&end,10);if(*end||port<1024||port>65535)_exit(73);
 atomic_store(&control_port,(int)port);atomic_store(&control_finished,false);pthread_t thread;
 if(pthread_create(&thread,NULL,control_worker,NULL))_exit(73);pthread_detach(thread);
}
