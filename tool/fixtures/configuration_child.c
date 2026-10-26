// Native lifecycle fixture only; not bundled in the application.
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
int main(int argc, char **argv) {
    if(argc!=3||strcmp(argv[1],"-u")||getenv("BROOMM_SESSION")||!getenv("BROOMM_INSTALLER_WRITER_LOCK"))return 70;
    if(open(argv[2],O_CREAT|O_WRONLY,0600)>=0)return 71;
    char path[4096];snprintf(path,sizeof(path),"%s/private-settings",getenv("HOME"));
    FILE *out=fopen(path,"w");if(!out)return 72;
    fputs("configured in private HOME",out);fclose(out);
    snprintf(path,sizeof(path),"%s/release",getenv("HOME"));
    for(int i=0;i<200;i++) {if(access(path,F_OK)==0)return 0;usleep(100000);}
    return 73;
}
