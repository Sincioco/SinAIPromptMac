#import <Cocoa/Cocoa.h>
#import "SINAppDelegate.h"
int main(int argc,const char *argv[]) {
    @autoreleasepool { NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyRegular];SINAppDelegate *delegate=SINAppDelegate.new;app.delegate=delegate;[app run]; }return 0;
}
