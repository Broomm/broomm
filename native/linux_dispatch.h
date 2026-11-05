#ifndef BROOMM_LINUX_DISPATCH_H
#define BROOMM_LINUX_DISPATCH_H
// Reviewed x64 SDL stubs use either JMP [RIP+disp32] or
// MOV RAX,[RIP+disp32]; JMP RAX. Never scan past a terminal jump into the
// neighbouring export: it may have a completely different return ABI.
static inline void **x64_dispatch_slot(void *function) {
 if(!function)return NULL;
 const uint8_t *p=function;
 for(int i=0;i<40;++i) {
  if(p[i]==0xff&&p[i+1]==0x25){int32_t offset;memcpy(&offset,p+i+2,4);return (void **)(p+i+6+offset);}
  if(p[i]==0x48&&p[i+1]==0x8b&&p[i+2]==0x05&&p[i+7]==0xff&&p[i+8]==0xe0){int32_t offset;memcpy(&offset,p+i+3,4);return (void **)(p+i+7+offset);}
  if(p[i]==0xc3||(p[i]==0xff&&(p[i+1]&0xf8)==0xe0))break;
 }
 return NULL;
}

// Reviewed ARM64 packages use a direct ADRP/LDR/BR tail jump (RPCS3),
// a MOV-to-X16 variant (Dolphin/DuckStation/ARMSX2/Armada), or a balanced
// frame prologue around ADRP (PPSSPP). Match from the export entry only;
// never scan into the next function or accept inconsistent registers.
static inline void **arm64_dispatch_slot(void *function) {
 if(!function)return NULL;
 uint32_t code[6];memcpy(code,function,sizeof(code));
 int address=0,load=1,branch=2;
 if(code[0]==0xa9bf7bfdu) {
  if(code[2]!=0x910003fdu||code[3]!=0xa8c17bfdu)return NULL;
  address=1;load=4;branch=5;
 }
 const uint32_t base=code[address]&31,target=code[load]&31;
 if((code[address]&0x9f000000u)!=0x90000000u ||
    (code[load]&0xffc00000u)!=0xf9400000u ||
    ((code[load]>>5)&31)!=base ||base==31||target==31 ||
    (address==1&&(base==29||base==30)))return NULL;
 if(code[branch]!=(0xd61f0000u|(target<<5))) {
  if(address!=0||code[2]!=(0xaa0003f0u|(target<<16))||code[3]!=0xd61f0200u)return NULL;
 }
 uint32_t imm=((code[address]>>29)&3)|(((code[address]>>5)&0x7ffffu)<<2);
 int64_t pages=(int64_t)imm-((imm&0x100000u)?0x200000:0);
 uintptr_t page=((uintptr_t)function+address*4)&~(uintptr_t)0xfff;
 return (void **)(page+pages*4096+((code[load]>>10)&0xfffu)*8);
}

static void **dispatch_slot(void *function) {
#if defined(__aarch64__)
 return arm64_dispatch_slot(function);
#else
 return x64_dispatch_slot(function);
#endif
}
#endif
