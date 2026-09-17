#import <Cocoa/Cocoa.h>
@class SINStore,SINWindowController;
@interface SINAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic,strong) SINStore *store;
@property(nonatomic,strong) NSMutableArray<SINWindowController*> *windows;
@property(nonatomic) BOOL selfTest;
- (void)menuAction:(NSMenuItem *)sender;
@end
