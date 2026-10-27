#import <Cocoa/Cocoa.h>
#include <fcntl.h>
#include <unistd.h>

@interface BroommWriterFixture : NSObject <NSApplicationDelegate>
@property BOOL ignoreQuit;
@end
@implementation BroommWriterFixture
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return self.ignoreQuit ? NSTerminateCancel : NSTerminateNow;
}
@end

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 3) return 2;
    int descriptor = open(argv[1], O_CREAT | O_RDWR, 0600);
    struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET};
    if (descriptor < 0 || fcntl(descriptor, F_SETLK, &lock) != 0) return 3;
    NSApplication *application = NSApplication.sharedApplication;
    [application setActivationPolicy:NSApplicationActivationPolicyProhibited];
    BroommWriterFixture *delegate = [BroommWriterFixture new];
    delegate.ignoreQuit = strcmp(argv[2], "ignore") == 0;
    application.delegate = delegate;
    [application run];
    close(descriptor);
    return 0;
  }
}
