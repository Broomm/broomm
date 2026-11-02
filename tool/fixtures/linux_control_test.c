// Exercise the production native protocol boundary without an emulator or keys.
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include "../../native/pause_transition.h"
static _Atomic bool session_finishing,session_worker_stopped=true,session_quit;
static _Atomic int session_wanted=1;
static int session_pause_command(struct PauseTransition *state,int wanted,int actual){return pause_transition(state,wanted,actual,0);}
static void record(const char *format,...){(void)format;}
#include "../../native/linux_control.inc"
#include "../../native/linux_dispatch.h"
static void linux_sdk_window_tick(void){}
static void connection(int sockets[2]) {assert(!socketpair(AF_UNIX,SOCK_STREAM,0,sockets));control_fd=sockets[0];control_begin();}
static void done(int sockets[2]){close(sockets[0]);close(sockets[1]);control_fd=-1;}
int main(void) {
 _Alignas(8) uint8_t stub[128]={0};int32_t distance=64-6;
 stub[0]=0xff;stub[1]=0x25;memcpy(stub+2,&distance,4);
 assert(dispatch_slot(stub)==(void **)(stub+64));
 memset(stub,0,sizeof(stub));distance=64-7;
 stub[0]=0x48;stub[1]=0x8b;stub[2]=0x05;memcpy(stub+3,&distance,4);stub[7]=0xff;stub[8]=0xe0;
 stub[16]=0xff;stub[17]=0x25; // A neighbouring export must never win.
 assert(dispatch_slot(stub)==(void **)(stub+64));
 stub[0]=0xff;stub[1]=0xe0;assert(dispatch_slot(stub)==NULL);
 puts("PASS SDL dispatch resolves both native stub ABIs without patching a neighbouring export");
 char value[64];
 assert(json_field("{\"game\":{\"ticket\":7},\"ticket\":4}","ticket",value,sizeof(value))&&!strcmp(value,"4"));
 assert(!json_field("{\"game\":{\"ticket\":7}}","ticket",value,sizeof(value)));
 assert(!json_field("{\"ticket\":4,\"ticket\":5}","ticket",value,sizeof(value)));
 assert(!json_field("{\"ticket\":false} garbage","ticket",value,sizeof(value)));
 assert(!json_field("{\"ticket\":\"long\",\"ticket\":2}","ticket",value,3));
 unsigned char digest[20];char encoded[29];const char *input="dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
 handshake_sha1((void *)input,strlen(input),digest);base64(digest,20,encoded);assert(!strcmp(encoded,"s3pPLMBiTxaQ9kYGzzhZRbK+xOo="));
 puts("PASS SDK root acknowledgements reject nested, duplicate and malformed data; RFC handshake vector");
 int sockets[2];char text[32769];connection(sockets);
 const unsigned char frames[]={0x01,2,'o','k',0x80,1,'!'};assert(write(sockets[1],frames,sizeof(frames))==sizeof(frames));assert(ws_read(text)&&!strcmp(text,"ok!"));done(sockets);
 connection(sockets);const unsigned char oversized[]={0x81,127};assert(write(sockets[1],oversized,2)==2);assert(!ws_read(text));done(sockets);
 connection(sockets);const char reply[]="$T02#b6";assert(write(sockets[1],reply,sizeof(reply)-1)==sizeof(reply)-1);assert(rsp_read(text)&&!strcmp(text,"T02"));done(sockets);
 connection(sockets);const char invalid[]="$T02#00";assert(write(sockets[1],invalid,sizeof(invalid)-1)==sizeof(invalid)-1);assert(!rsp_read(text));done(sockets);
 connection(sockets);control_deadline=control_now()-1;assert(!control_io(value,1,false));done(sockets);
 puts("PASS SDK framing/checksums reject oversized or invalid messages and expired operation deadlines");
 atomic_store(&control_port,45678);assert(control_connect()==-1); // Never connect to an unowned endpoint.
 atomic_store(&control_port,0);start_control();assert(atomic_load(&control_finished));
 puts("PASS native control refuses an endpoint without a same-process listener");
 return 0;
}
