// Disposable Launch Services fixture. No emulator or owner data is accessed.
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <unistd.h>

int main(void) {
    @autoreleasepool {
        NSString *root=@(getenv("BROOMM_ASTRIS_ROOT"));
        int fd=open(getenv("BROOMM_WRITER_LOCK"),O_RDWR|O_NOFOLLOW|O_CLOEXEC);
        struct flock lock={.l_type=F_WRLCK,.l_whence=SEEK_SET,.l_start=0,.l_len=0};
        if(fd<0||fcntl(fd,F_SETLK,&lock)!=0)return 78;
        printf("native fixture output\n");fflush(stdout);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        __block int ticks=0;
        [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:YES block:^(NSTimer *timer){
            (void)timer;
            if([NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"finish"]]) {
                if(getenv("BROOMM_FIXTURE_CRASH"))_exit(7);
                NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"pid":@(getpid()),@"normal":@YES} options:0 error:nil];
                (void)[data writeToFile:[root stringByAppendingPathComponent:@"astris-exit.json"] options:NSDataWritingAtomic error:nil];
                [NSApp terminate:nil];
            }
            if(++ticks>=3000)_exit(8);
        }];
        [NSApp run];
    }
    return 0;
}
