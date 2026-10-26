#define _DARWIN_C_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
static void handled_abort(int signal_number) {
    (void)signal_number;
    static const char message[]="original abort reached SIGABRT handler\n";
    (void)write(STDERR_FILENO,message,sizeof(message)-1);
    _exit(87);
}
int main(int argc,char **argv) {
    if(getenv("BROOMM_FIXTURE_HANDLE_ABORT")) signal(SIGABRT,handled_abort);
    puts("ready");fflush(stdout);
    if(argc==2) {for(int i=0;i<3000 && access(argv[1],F_OK)!=0;i++)usleep(10000);}
    else (void)getchar();
    if(getenv("BROOMM_FIXTURE_ABORT")) abort();
    return 0;
}
