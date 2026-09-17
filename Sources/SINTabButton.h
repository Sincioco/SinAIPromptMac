#import <Cocoa/Cocoa.h>
@interface SINTabButton : NSButton <NSDraggingSource,NSDraggingDestination>
@property(nonatomic,copy) void (^moveDocument)(NSString *source,NSString *target);
@property(nonatomic,copy) void (^closeDocument)(NSString *identifier);
@end
