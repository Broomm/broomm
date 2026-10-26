// PPSSPP macOS consults NSUserDefaults before its HOME fallback. Override only
// this child's volatile argument domain, never the persistent user defaults.
#include <objc/message.h>
#include <objc/runtime.h>
static id psp_defaults,psp_domain,psp_path_key,psp_bookmarks_key;
static void (*psp_original_defaults_write)(id,SEL,id,id);
static void psp_scoped_defaults_write(id object,SEL selector,id value,id key) {
    bool (*equal)(id,SEL,id)=(void *)objc_msgSend;
    if(object==psp_defaults&&key&&
       (equal(key,sel_registerName("isEqual:"),psp_path_key)||equal(key,sel_registerName("isEqual:"),psp_bookmarks_key))) {
        id old=((id(*)(id,SEL,id))objc_msgSend)(object,sel_registerName("volatileDomainForName:"),psp_domain);
        id copy=((id(*)(id,SEL))objc_msgSend)(old,sel_registerName("mutableCopy"));
        if(value)((void(*)(id,SEL,id,id))objc_msgSend)(copy,sel_registerName("setObject:forKey:"),value,key);
        else ((void(*)(id,SEL,id))objc_msgSend)(copy,sel_registerName("removeObjectForKey:"),key);
        ((void(*)(id,SEL,id,id))objc_msgSend)(object,sel_registerName("setVolatileDomain:forName:"),copy,psp_domain);
        ((void(*)(id,SEL))objc_msgSend)(copy,sel_registerName("release"));
        return;
    }
    psp_original_defaults_write(object,selector,value,key);
}
__attribute__((constructor)) static void ppsspp_private_storage(void) {
    const char *path=getenv("BROOMM_PSP_MEMSTICK");
    if(!path)return;
    if(path[0]!='/'){fputs("Invalid private PSP storage.\n",stderr);_exit(78);}
    id (*call)(id,SEL)=(void *)objc_msgSend;
    id (*string)(id,SEL,const char *)=(void *)objc_msgSend;
    id pool=call(call((id)objc_getClass("NSAutoreleasePool"),sel_registerName("alloc")),sel_registerName("init"));
    id defaults=call((id)objc_getClass("NSUserDefaults"),sel_registerName("standardUserDefaults"));
    id domain=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"NSArgumentDomain");
    id old=((id(*)(id,SEL,id))objc_msgSend)(defaults,sel_registerName("volatileDomainForName:"),domain);
    id copy=old?call(old,sel_registerName("mutableCopy")):call((id)objc_getClass("NSMutableDictionary"),sel_registerName("new"));
    id key=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"UserPreferredMemoryStickDirectoryPath");
    id bookmarks=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),"SecureBookmarks");
    id value=string((id)objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),path);
    if(!defaults||!copy||!value){fputs("Private PSP storage could not be selected.\n",stderr);_exit(78);}
    ((void(*)(id,SEL,id,id))objc_msgSend)(copy,sel_registerName("setObject:forKey:"),value,key);
    ((void(*)(id,SEL,id,id))objc_msgSend)(copy,sel_registerName("setObject:forKey:"),call((id)objc_getClass("NSDictionary"),sel_registerName("dictionary")),bookmarks);
    ((void(*)(id,SEL,id,id))objc_msgSend)(defaults,sel_registerName("setVolatileDomain:forName:"),copy,domain);
    // PPSSPP's folder picker also writes these two keys through the preferences
    // daemon, independently of HOME. Confine those writes to this child too.
    psp_defaults=call(defaults,sel_registerName("retain"));
    psp_domain=call(domain,sel_registerName("retain"));
    psp_path_key=call(key,sel_registerName("retain"));
    psp_bookmarks_key=call(bookmarks,sel_registerName("retain"));
    Method write=class_getInstanceMethod(objc_getClass("NSUserDefaults"),sel_registerName("setObject:forKey:"));
    if(!write){fputs("Private PSP preferences unavailable.\n",stderr);_exit(78);}
    psp_original_defaults_write=(void *)method_getImplementation(write);
    method_setImplementation(write,(IMP)psp_scoped_defaults_write);
    call(copy,sel_registerName("release"));call(pool,sel_registerName("drain"));
}
