#import <Cocoa/Cocoa.h>
@class SINEditor;
NS_ASSUME_NONNULL_BEGIN
@interface SINSearchPanel : NSViewController
@property(nonatomic, copy, readonly) NSString *query;
- (instancetype)initWithEditor:(SINEditor *)editor;
- (void)showForWindow:(NSWindow *)window replace:(BOOL)replace;
- (void)findNext:(BOOL)backward;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
