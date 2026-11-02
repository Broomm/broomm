#ifndef BROOMM_LINUX_DISPATCH_H
#define BROOMM_LINUX_DISPATCH_H
// Reviewed x64 SDL stubs use either JMP [RIP+disp32] or
// MOV RAX,[RIP+disp32]; JMP RAX. Never scan past a terminal jump into the
// neighbouring export: it may have a completely different return ABI.
static void **dispatch_slot(void *function) {
 if(!function)return NULL;
 const uint8_t *p=function;
 for(int i=0;i<40;++i) {
  if(p[i]==0xff&&p[i+1]==0x25){int32_t offset;memcpy(&offset,p+i+2,4);return (void **)(p+i+6+offset);}
  if(p[i]==0x48&&p[i+1]==0x8b&&p[i+2]==0x05&&p[i+7]==0xff&&p[i+8]==0xe0){int32_t offset;memcpy(&offset,p+i+3,4);return (void **)(p+i+7+offset);}
  if(p[i]==0xc3||(p[i]==0xff&&(p[i+1]&0xf8)==0xe0))break;
 }
 return NULL;
}
#endif
