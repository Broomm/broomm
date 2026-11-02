// Original read-only libretro ABI/version probe. Never loads a game or save.
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
struct Info {const char *name,*version,*extensions;bool fullpath,extract;};
static void text(const char *s){putchar('"');if(s)for(const unsigned char *p=(const void *)s;*p;p++){if(*p=='"'||*p=='\\')putchar('\\');if(*p<32)printf("\\u%04x",*p);else putchar(*p);}putchar('"');}
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 1;}
    unsigned (*version)(void);void (*info)(struct Info *);
    *(void **)(&version)=dlsym(library,"retro_api_version");*(void **)(&info)=dlsym(library,"retro_get_system_info");
    if(!version||!info||version()!=1)return 1;
    struct Info value={0};info(&value);
    fputs("{\"name\":",stdout);text(value.name);fputs(",\"version\":",stdout);text(value.version);
    fputs(",\"extensions\":",stdout);text(value.extensions);puts("}");
    dlclose(library);return 0;
}
