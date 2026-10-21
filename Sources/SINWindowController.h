#import <Cocoa/Cocoa.h>
#import "SINDocument.h"
#import "SINStore.h"
#import "SINEditor.h"
#import "SINNavigator.h"
@interface SINWindowController : NSWindowController <NSWindowDelegate, NSSplitViewDelegate>
@property(nonatomic,strong) SINStore *store;
@property(nonatomic,strong) NSMutableArray<SINDocument*> *documents;
@property(nonatomic,strong) NSMutableDictionary<NSString*,SINEditor*> *editors;
@property(nonatomic,strong) SINDocument *active;
@property(nonatomic,readonly) SINEditor *editor;
@property(nonatomic,strong) SINNavigator *navigator;
@property(nonatomic,strong) SINNavigator *contentsNavigator;
@property(nonatomic,copy) NSString *imageStatus;
@property(nonatomic,strong) NSSplitView *split;
@property(nonatomic,strong) NSView *editorHost;
@property(nonatomic,strong) NSView *documentPane;
@property(nonatomic,strong) NSScrollView *tabScroll;
@property(nonatomic,strong) NSStackView *tabs;
@property(nonatomic,strong) NSTextField *status;
@property(nonatomic,strong) NSView *preview;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL annotating;
@property(nonatomic) BOOL saving;
@property(nonatomic) BOOL testMode;
@property(nonatomic) BOOL closing;
@property(nonatomic,strong) NSError *recoveryError;
@property(nonatomic,strong) NSDictionary *testResult;
- (instancetype)initWithStore:(SINStore *)store restore:(BOOL)restore;
- (instancetype)initWithStore:(SINStore *)store documents:(NSArray<SINDocument*>*)documents activeIdentifier:(NSString*)identifier;
- (void)handleCommand:(NSString *)command;
- (void)openPaths:(NSArray<NSString*> *)paths;
- (void)activate:(SINDocument *)document;
- (void)showError:(NSError *)error;
- (void)refresh;
- (void)layoutChrome;
- (void)persist;
- (void)persistInBackground;
- (SINEditor *)editorFor:(SINDocument *)document;
@end

@interface SINWindowController (ExplorerActions)
- (void)renameImageAtPath:(NSString *)path;
- (void)trashPath:(NSString *)path;
@end

@interface SINWindowController (FileActions)
- (void)saveDocument:(SINDocument *)document saveAs:(BOOL)saveAs completion:(void (^)(BOOL))completion;
- (void)closeDocument:(SINDocument *)document;
- (void)renameDocument:(SINDocument *)document;
- (void)changeDocumentLock:(SINDocument *)document locked:(BOOL)locked completion:(void (^)(BOOL))completion;
- (void)copyDocumentForAI:(SINDocument *)document;
- (void)revertDocument:(SINDocument *)document;
- (BOOL)reloadDocumentFromDisk:(SINDocument *)document;
- (void)removeOpenDocument:(SINDocument *)document;
- (void)exportDocument:(BOOL)markdown;
// Called after a Save panel has confirmed the destination (including Replace).
- (void)exportDocument:(BOOL)markdown toPath:(NSString *)path completion:(void (^)(NSError *))completion;
- (void)checkExternalChange;
@end
@interface SINWindowController (DocumentWorkflows)
- (NSArray<SINDocument *> *)visibleDocuments;
- (void)sortDocuments;
- (void)refreshPrivacy;
- (void)chooseEmoji:(SINDocument *)document;
- (void)combineItems:(NSArray *)items;
- (void)deleteItems:(NSArray *)items;
- (void)addBundledDocument:(NSString *)name;
- (void)ensureBundledDocuments;
- (void)importMarkdown:(NSString *)path completion:(void (^)(SINDocument *,NSError *))completion;
- (void)resolveFirstSave:(SINDocument *)document completion:(void (^)(NSString *,NSString *))completion;
@end
@interface SINWindowController (NavigationActions)
- (void)navigateAction:(NSString *)action item:(id)item;
- (void)showPreview:(NSString *)path;
@end
@interface SINWindowController (ContextMenus)
- (NSMenu *)documentContextMenu:(SINDocument *)document;
- (NSMenu *)documentContextMenu:(SINDocument *)document documentList:(BOOL)documentList;
@end
@interface SINWindowController (Settings)
- (void)showSettings;
@end
@interface SINWindowController (SelfTest)
- (void)runSelfTests;
@end
@interface SINWindowController (NativeSelfTest)
- (void)runNativeShellChecks:(void (^)(NSArray<NSString *> *, NSError *))completion;
@end
@interface SINWindowController (DocumentWorkflowSelfTest)
- (void)runDocumentWorkflowChecks:(void (^)(NSArray<NSString *> *, NSError *))completion;
@end

@interface SINWindowController (Lifecycle)
- (void)prepareToClose:(void (^)(BOOL))completion;
@end

FOUNDATION_EXPORT NSArray<NSString *> *SINUnusedImagePaths(NSString *folder, NSArray<NSDictionary *> *snapshots, NSError **error);
@interface SINWindowController (UnusedImages)
- (void)scanUnusedImages;
@end

FOUNDATION_EXPORT BOOL SINFolderContainsReferencedFiles(NSString *folder, NSArray<NSDictionary *> *snapshots, NSError **error);
