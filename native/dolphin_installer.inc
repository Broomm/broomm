// Narrow interop with the hash-pinned Dolphin 2609 native WAD importer.
// Dart validates the WAD, chooses private staging and validates the result.
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>

static unsigned wad_waits;
static void import_dolphin_wad(void *unused) {
    (void)unused;
#if defined(__aarch64__)
    const char *path=getenv("BROOMM_DOLPHIN_WAD");
    if (!path || writer_fd < 0) _exit(78);
    id app=((id(*)(id,SEL))objc_msgSend)((id)objc_getClass("NSApplication"),sel_registerName("sharedApplication"));
    id windows=((id(*)(id,SEL))objc_msgSend)(app,sel_registerName("windows"));
    unsigned long count=((unsigned long(*)(id,SEL))objc_msgSend)(windows,sel_registerName("count"));
    int ready=0;
    for(unsigned long i=0;i<count && i<64;i++) {
        id window=((id(*)(id,SEL,unsigned long))objc_msgSend)(windows,sel_registerName("objectAtIndex:"),i);
        id title=((id(*)(id,SEL))objc_msgSend)(window,sel_registerName("title"));
        const char *value=((const char *(*)(id,SEL))objc_msgSend)(title,sel_registerName("UTF8String"));
        if(value && strstr(value,"Dolphin")) ready=1;
    }
    // An inactive inspector has no mainWindow. Its constructed Qt main
    // window still establishes that UICommon::Init and native paths are ready.
    if (!ready) {
        if (++wad_waits > 150) _exit(79);
        dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,100*1000*1000),dispatch_get_main_queue(),NULL,import_dolphin_wad);
        return;
    }
    uintptr_t address=0;
    for(uint32_t i=0;i<_dyld_image_count();i++) {
        const struct mach_header *header=_dyld_get_image_header(i);
        if(header && header->filetype==MH_EXECUTE) {
            address=(uintptr_t)_dyld_get_image_vmaddr_slide(i)+UINT64_C(0x1003d4fb0);
            break;
        }
    }
    if(!address) _exit(80);
    // Exact ARM64 prologue, alongside Dart's full executable SHA-256 guard.
    const uint32_t expected[]={0xa9bd6ffc,0xa9014ff4,0xa9027bfd,0xd11743ff};
    if (memcmp((void *)address,expected,sizeof(expected))!=0) {
        const uint32_t *actual=(const uint32_t *)address;
        fprintf(stderr,"BROOMM_DOLPHIN_ABI_MISMATCH %08x %08x %08x %08x\n",actual[0],actual[1],actual[2],actual[3]);
        _exit(80);
    }
    // Darwin libc++ alternate long-string layout, const-ref input. Dolphin
    // neither owns nor mutates this temporary value. No C++ runtime is added.
    struct { const char *data; size_t size,capacity; } text={path,strlen(path),strlen(path)|(SIZE_MAX/2+1)};
    int result=((_Bool(*)(const void *))address)(&text);
    static const char ok[]="BROOMM_DOLPHIN_WAD_V1_OK\n";
    if(result) (void)write(STDOUT_FILENO,ok,sizeof(ok)-1);
    // Native ImportTitleDone completed synchronously. This process has no
    // game/save writer; do not execute a newly installed channel or system UI.
    _exit(result?0:81);
#else
    fputs("BROOMM_DOLPHIN_UNSUPPORTED_ARCH\n",stderr);
    _exit(80);
#endif
}
__attribute__((constructor)) static void schedule_dolphin_wad(void) {
    if (getenv("BROOMM_DOLPHIN_WAD")) {
        if(writer_fd<0) _exit(78);
        dispatch_async_f(dispatch_get_main_queue(),NULL,import_dolphin_wad);
    }
}
