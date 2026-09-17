#import <Cocoa/Cocoa.h>
@class SINDocument;
@interface SINNavigator : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@property(nonatomic,copy) NSArray<SINDocument*> *documents;
@property(nonatomic,copy) NSString *directory;
@property(nonatomic,copy) NSString *sortMode;
@property(nonatomic) BOOL showFolders;
@property(nonatomic) NSInteger mode;
@property(nonatomic,copy) NSArray<NSDictionary*> *headings;
@property(nonatomic,copy) void (^selected)(id item);
@property(nonatomic,copy) void (^action)(NSString *command,id item);
@property(nonatomic,copy) void (^reordered)(NSArray<SINDocument*> *documents);
@property(nonatomic,strong) NSOutlineView *outline;
- (void)refresh;
- (void)selectDocument:(SINDocument *)document;
@end
