#include <objc/message.h>
#include <objc/runtime.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    id (*call)(id,SEL)=(void *)objc_msgSend;
    id (*arg)(id,SEL,id)=(void *)objc_msgSend;
    id (*string)(id,SEL,const char *)=(void *)objc_msgSend;
    id pool=call(call((id)objc_getClass("NSAutoreleasePool"),sel_registerName("alloc")),sel_registerName("init"));
    id defaults=call((id)objc_getClass("NSUserDefaults"),sel_registerName("standardUserDefaults"));
    id domain=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"NSArgumentDomain");
    id path=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"UserPreferredMemoryStickDirectoryPath");
    const char *initial=((const char *(*)(id,SEL))objc_msgSend)(arg(defaults,sel_registerName("stringForKey:"),path),sel_registerName("UTF8String"));
    if(!initial||strcmp(initial,getenv("BROOMM_PSP_MEMSTICK")))return 2;
    const char *name=getenv("BROOMM_DEFAULTS_PROBE_KEY");
    id key=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),name);
    id value=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"Broomm fixture value");
    ((void(*)(id,SEL,id,id))objc_msgSend)(defaults,sel_registerName("setObject:forKey:"),value,key);
    id values=arg(defaults,sel_registerName("volatileDomainForName:"),domain);
    id readback=arg(values,sel_registerName("objectForKey:"),key);
    if(!readback||!((bool(*)(id,SEL,id))objc_msgSend)(readback,sel_registerName("isEqual:"),value))return 3;
    ((void(*)(id,SEL,id,id))objc_msgSend)(defaults,sel_registerName("setObject:forKey:"),(id)0,key);
    values=arg(defaults,sel_registerName("volatileDomainForName:"),domain);
    if(arg(values,sel_registerName("objectForKey:"),key))return 4;
    puts("private volatile preferences verified");
    call(pool,sel_registerName("drain"));
    return 0;
}
