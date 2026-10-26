#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc,char **argv) {
    if(argc<2 || strncmp(argv[1],"--installpkg=",13)!=0) return 77;
    const char *input=argv[1]+13;
    char path[PATH_MAX];
    int n=snprintf(path,sizeof(path),"%s/Library/Application Support/rpcs3/RPCS3.log",getenv("HOME"));
    if(n<0 || (size_t)n>=sizeof(path)) return 77;
    FILE *log=fopen(path,"w");
    if(!log) return 77;
    if(!strstr(input,"failed.pkg"))
        fprintf(log,"Successfully installed %s (title_id=BCUS98296).\n",input);
    else fputs("Package installation failed.\n",log);
    if(fclose(log)!=0) return 77;
    fputs("Emulation object is unavailable (process teardown)\n",stderr);
    fflush(stderr);
    if(strstr(input,"forged.pkg")) _exit(86);
    abort();
}
