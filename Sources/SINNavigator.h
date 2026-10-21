#import <Cocoa/Cocoa.h>
@class SINDocument;
@interface SINNavigator : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSSearchFieldDelegate>
@property(nonatomic,copy) NSArray<SINDocument*> *documents;
@property(nonatomic,copy) NSArray<SINDocument*> *allDocuments;
@property(nonatomic,copy) NSString *directory;
@property(nonatomic,copy) NSString *sortMode;
@property(nonatomic) BOOL showFolders;
@property(nonatomic) NSInteger mode;
@property(nonatomic) BOOL contentsOnly;
@property(nonatomic) BOOL multiSelection;
@property(nonatomic,copy) NSSet<NSString *> *hiddenPaths;
@property(nonatomic,copy) NSDictionary<NSString *,NSString *> *emojis;
@property(nonatomic,copy) NSString *filterText;
@property(nonatomic,copy) NSMenuItem *(^projectMenu)(NSArray *items);
@property(nonatomic,readonly) NSArray *checkedItems;
@property(nonatomic,copy) NSArray<NSDictionary*> *headings;
@property(nonatomic,copy) void (^selected)(id item);
@property(nonatomic,copy) void (^action)(NSString *command,id item);
@property(nonatomic,copy) NSMenu *(^documentMenu)(SINDocument *document);
@property(nonatomic,copy) BOOL (^contextActionsEnabled)(void);
@property(nonatomic,copy) void (^reordered)(NSArray<SINDocument*> *documents);
@property(nonatomic,strong) NSOutlineView *outline;
- (void)refresh;
- (void)selectDocument:(SINDocument *)document;
- (NSMenu *)contextMenuForItem:(id)item;
- (void)clearSelection;
- (void)removeCheckedItems:(NSArray *)items;
- (NSArray *)selectionIncludingItem:(id)item;
- (BOOL)isItemChecked:(id)item;
@end
