#import "SINProjectSession.h"
#import "SINAppDelegate.h"
#import "SINNativeServices.h"

static NSError *ProjectSessionError(NSString *message) { return [NSError errorWithDomain:SINErrorDomain code:SINErrorStorage userInfo:@{NSLocalizedDescriptionKey:message}]; }
static BOOL ProjectSessionSamePath(NSString *first,NSString *second) {
    if(!first||!second)return NO;
    if(SINPathsReferToSameFile(first,second))return YES;
    first=first.stringByStandardizingPath.stringByResolvingSymlinksInPath;second=second.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    return [first isEqual:second] || (![SINProjects caseSensitiveAtPath:first]&&![SINProjects caseSensitiveAtPath:second]&&[first caseInsensitiveCompare:second]==NSOrderedSame);
}
static NSArray<SINWindowController *> *ProjectWindows(SINWindowController *owner) {
    NSMutableArray *windows=[((SINAppDelegate *)NSApp.delegate).windows mutableCopy]?:NSMutableArray.new;
    if(![windows containsObject:owner])[windows addObject:owner];
    NSIndexSet *closed=[windows indexesOfObjectsPassingTest:^BOOL(SINWindowController *window,NSUInteger index,BOOL *stop){return window.closing;}];[windows removeObjectsAtIndexes:closed];
    return windows;
}
static NSString *ProjectItemPath(id item) { return [item isKindOfClass:SINDocument.class]?[item path]:([item isKindOfClass:NSString.class]?item:nil); }
static BOOL ProjectItemValid(id item) { NSString *path=ProjectItemPath(item);return path.length&&[@[@"html",@"htm"] containsObject:path.pathExtension.lowercaseString]; }

@interface SINProjectOpen : NSObject
@property(nonatomic,strong) SINWindowController *window;
@property(nonatomic,strong) SINDocument *document;
@property(nonatomic,strong) SINEditor *editor;
@property(nonatomic) BOOL wasReadOnly;
@property(nonatomic) NSUInteger snapshotIndex;
@property(nonatomic,copy) NSString *originalText,*updatedText;
@end
@implementation SINProjectOpen
@end

@interface SINProjectRun : NSObject
@property(nonatomic,strong) SINWindowController *owner;
@property(nonatomic,copy) NSArray<SINWindowController *> *windows;
@property(nonatomic,copy) NSArray<NSString *> *paths;
@property(nonatomic,copy) NSString *destination;
@property(nonatomic,strong) NSArray<SINProjectMoveSnapshot *> *snapshots;
@property(nonatomic,strong) NSArray<SINProjectMoveResult *> *results;
@property(nonatomic,strong) NSMutableArray<SINProjectOpen *> *open;
@property(nonatomic,strong) NSArray<NSDictionary *> *moves;
@property(nonatomic,strong) NSMutableArray<NSString *> *warnings;
@property(nonatomic,strong) SINEditor *parser;
@property(nonatomic,copy) void (^completion)(NSArray<SINProjectMoveResult *> *,NSArray<NSString *> *,NSError *);
@property(nonatomic) BOOL locked;
- (void)start;
@end

@implementation SINProjectRun
- (void)finish:(NSError *)error {
    if(self.locked) {
        for(SINProjectOpen *item in self.open){item.document.readOnly=self.results?self.results[item.snapshotIndex].readOnly:item.wasReadOnly;[item.editor applyPreferences];}
        for(SINWindowController *window in self.windows){window.saving=NO;[window refreshPrivacy];[window refresh];[window.navigator refresh];if(self.results)[window.navigator clearSelection];[window persist];}
    }
    void (^done)(NSArray *,NSArray *,NSError *)=self.completion;self.completion=nil;
    if(done)done(self.results,self.warnings?:@[],error);
}
- (void)start {
    self.warnings=NSMutableArray.new;self.open=NSMutableArray.new;self.windows=ProjectWindows(self.owner);
    for(SINWindowController *window in self.windows)if(window.saving||window.annotating||window.window.attachedSheet){[self finish:ProjectSessionError(@"Finish the current file operation, dialog or image edit before moving prompts to a project.")];return;}
    for(SINWindowController *window in self.windows)for(SINDocument *document in window.documents) {
        for(NSUInteger index=0;index<self.paths.count;index++) {
            NSString *source=self.paths[index],*target=[self.destination stringByAppendingPathComponent:source.lastPathComponent];
            if(ProjectSessionSamePath(document.path,target)){[self finish:ProjectSessionError(@"A destination file is already open. Choose another project or close that file first.")];return;}
            if(ProjectSessionSamePath(document.path,source)) {
                SINProjectOpen *item=SINProjectOpen.new;item.window=window;item.document=document;item.editor=window.editors[document.identifier];item.wasReadOnly=document.readOnly;item.snapshotIndex=index;[self.open addObject:item];break;
            }
        }
    }
    self.parser=self.owner.editor;
    if(!self.parser){[self finish:ProjectSessionError(@"Open an editor before moving documents into a project.")];return;}
    for(SINWindowController *window in self.windows)window.saving=YES;
    self.locked=YES;
    for(SINProjectOpen *item in self.open){item.document.readOnly=YES;[item.editor applyPreferences];}
    self.owner.status.stringValue=@"Preparing project move…";
    [self flushAtIndex:0];
}
- (void)flushAtIndex:(NSUInteger)index {
    if(index>=self.open.count){[self.parser flush:^{[self readSnapshots];}];return;}
    SINProjectOpen *item=self.open[index];
    void (^next)(void)=^{item.originalText=item.document.text;[self flushAtIndex:index+1];};
    if(item.editor)[item.editor flush:next];else next();
}
- (void)readSnapshots {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSMutableArray *snapshots=NSMutableArray.new;NSError *error=nil;
        for(NSString *path in self.paths){SINProjectMoveSnapshot *snapshot=[SINProjectMoveSnapshot readPath:path destinationFolder:self.destination error:&error];if(!snapshot)break;[snapshots addObject:snapshot];}
        dispatch_async(dispatch_get_main_queue(),^{
            if(error){[self finish:error];return;}
            self.snapshots=snapshots;self.moves=[SINProjects referenceMovesForSnapshots:snapshots];
            for(SINProjectOpen *item in self.open)if(item.document.fingerprint&&![item.document.fingerprint isEqual:self.snapshots[item.snapshotIndex].fingerprint]){[self finish:ProjectSessionError([NSString stringWithFormat:@"A selected document changed outside Sin AI Prompt. Reload it before moving: %@",item.document.path])];return;}
            [self rewriteSavedAtIndex:0];
        });
    });
}
- (void)rewriteHTML:(NSString *)html snapshot:(SINProjectMoveSnapshot *)snapshot completion:(void (^)(NSString *,NSError *))completion {
    NSString *script=[NSString stringWithFormat:@"return window.editor.rewriteProjectReferences(%@,%@,%@,%@,%@,%@);",SINJSON(html),SINJSON([NSURL fileURLWithPath:snapshot.sourcePath].absoluteString),SINJSON([NSURL fileURLWithPath:snapshot.destinationPath].absoluteString),SINJSON(self.moves),[SINProjects caseSensitiveAtPath:snapshot.sourcePath]?@"true":@"false",[SINProjects caseSensitiveAtPath:snapshot.destinationPath]?@"true":@"false"];
    [self.parser asyncScript:script completion:^(id result,NSError *error){completion([result isKindOfClass:NSString.class]?result:nil,error?:([result isKindOfClass:NSString.class]?nil:ProjectSessionError(@"The editor could not rewrite the project's document references.")));}];
}
- (void)rewriteSavedAtIndex:(NSUInteger)index {
    if(index>=self.snapshots.count){[self rewriteBuffersAtIndex:0];return;}
    SINProjectMoveSnapshot *snapshot=self.snapshots[index];
    [self rewriteHTML:snapshot.html snapshot:snapshot completion:^(NSString *html,NSError *error){if(error){[self finish:error];return;}snapshot.html=html;[self rewriteSavedAtIndex:index+1];}];
}
- (void)rewriteBuffersAtIndex:(NSUInteger)index {
    if(index>=self.open.count){[self commit];return;}
    SINProjectOpen *item=self.open[index];
    [self rewriteHTML:item.originalText snapshot:self.snapshots[item.snapshotIndex] completion:^(NSString *html,NSError *error){if(error){[self finish:error];return;}item.updatedText=html;[self rewriteBuffersAtIndex:index+1];}];
}
- (void)commit {
    for(SINProjectOpen *item in self.open)if(![item.document.text isEqual:item.originalText]||![item.window.documents containsObject:item.document]){[self finish:ProjectSessionError(@"An open document changed while preparing the move. Its text is preserved; try the move again.")];return;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSArray *results=[SINProjects commitSnapshots:self.snapshots progress:^(NSUInteger done,NSUInteger total){dispatch_async(dispatch_get_main_queue(),^{self.owner.status.stringValue=[NSString stringWithFormat:@"Moving to project: %lu/%lu",(unsigned long)done,(unsigned long)total];});} error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            if(!results){[self finish:error];return;}
            self.results=results;
            for(SINProjectOpen *item in self.open) {
                SINProjectMoveResult *result=results[item.snapshotIndex];SINProjectMoveSnapshot *snapshot=self.snapshots[item.snapshotIndex];SINDocument *document=item.document;
                document.path=result.destinationPath;document.savedText=result.html;document.text=item.updatedText;
                document.fingerprint=result.fingerprint;document.savedEncoding=snapshot.encodingName;document.savedNewline=snapshot.newline;
                document.createdDate=result.createdDate;document.modifiedDate=result.modifiedDate;
                item.editor.services.documentPath=result.destinationPath;
            }
            [self updateMetadata];
            [self refreshAtIndex:0];
        });
    });
}
- (void)updateMetadata {
    NSMutableSet *stores=NSMutableSet.new;for(SINWindowController *window in self.windows)[stores addObject:window.store];
    for(SINStore *store in stores) {
        NSMutableArray *recent=[store.settings[@"recent"] mutableCopy]?:NSMutableArray.new;
        NSMutableDictionary *emojis=[store.settings[@"documentEmojis"] mutableCopy]?:NSMutableDictionary.new;
        for(SINProjectMoveResult *result in self.results) {
            NSIndexSet *old=[recent indexesOfObjectsPassingTest:^BOOL(id path,NSUInteger index,BOOL *stop){return [path isKindOfClass:NSString.class]&&ProjectSessionSamePath(path,result.sourcePath);}];[recent removeObjectsAtIndexes:old];
            for(NSString *path in emojis.allKeys)if(ProjectSessionSamePath(path,result.sourcePath)){id value=emojis[path];[emojis removeObjectForKey:path];emojis[result.destinationPath]=value;}
        }
        store.settings[@"recent"]=recent;store.settings[@"documentEmojis"]=emojis;
        for(SINProjectOpen *item in self.open)if(item.window.store==store&&item.document.emoji.length)[store rememberDocumentEmoji:item.document oldPath:self.results[item.snapshotIndex].sourcePath];
        NSError *error=nil;if(![SINProjects rememberProjectFolder:self.destination settings:store.settings error:&error])[self.warnings addObject:error.localizedDescription];
        for(SINProjectMoveResult *result in self.results)[store addRecentPath:result.destinationPath];
        if(![store saveSettings:&error])[self.warnings addObject:[@"Project settings could not be saved: " stringByAppendingString:error.localizedDescription]];
    }
    for(SINProjectMoveResult *result in self.results)if(result.cleanupWarning)[self.warnings addObject:[@"Recovery copy retained: " stringByAppendingString:result.cleanupWarning]];
}
- (void)refreshAtIndex:(NSUInteger)index {
    if(index>=self.open.count){[self finish:nil];return;}
    SINProjectOpen *item=self.open[index];
    if(!item.editor){[self refreshAtIndex:index+1];return;}
    [item.editor acceptProjectMoveHTML:item.updatedText savedHTML:self.results[item.snapshotIndex].html completion:^(NSError *error){
        if(error){item.document.autosave=NO;[self.warnings addObject:[NSString stringWithFormat:@"%@: The file moved, but its editor could not refresh. Unsaved text is preserved and autosave is off. %@",item.document.name,error.localizedDescription]];}
        [self refreshAtIndex:index+1];
    }];
}
@end

@interface SINProjectCreateDialog : NSObject
@property(nonatomic,strong) SINWindowController *owner;
@property(nonatomic,strong) NSAlert *alert;
@property(nonatomic,strong) NSTextField *name,*parent;
@property(nonatomic,copy) void (^completion)(NSString *);
- (void)show;
@end
@implementation SINProjectCreateDialog
- (void)show {
    self.alert=NSAlert.new;self.alert.messageText=@"New Project";self.alert.informativeText=@"Create a physical folder named Project - <Name>.";
    [self.alert addButtonWithTitle:@"Create"];[self.alert addButtonWithTitle:@"Cancel"];
    NSView *accessory=[[NSView alloc] initWithFrame:NSMakeRect(0,0,470,120)];
    NSTextField *nameLabel=[NSTextField labelWithString:@"Project Name"];nameLabel.frame=NSMakeRect(0,96,470,18);[accessory addSubview:nameLabel];
    self.name=[[NSTextField alloc] initWithFrame:NSMakeRect(0,68,470,25)];self.name.accessibilityLabel=@"Project Name";[accessory addSubview:self.name];
    NSTextField *parentLabel=[NSTextField labelWithString:@"Parent Folder"];parentLabel.frame=NSMakeRect(0,38,470,18);[accessory addSubview:parentLabel];
    self.parent=[[NSTextField alloc] initWithFrame:NSMakeRect(0,7,375,25)];self.parent.accessibilityLabel=@"Project Parent Folder";
    NSString *folder=self.owner.navigator.mode==0?self.owner.navigator.directory:self.owner.active.path.stringByDeletingLastPathComponent;
    if(!folder.length)folder=self.owner.store.settings[@"autoSaveDirectory"];
    if(!folder.length)folder=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject?:NSHomeDirectory();
    self.parent.stringValue=folder;[accessory addSubview:self.parent];
    NSButton *browse=[NSButton buttonWithTitle:@"Browse…" target:self action:@selector(browse:)];browse.frame=NSMakeRect(380,5,90,29);[accessory addSubview:browse];self.alert.accessoryView=accessory;
    [self.alert beginSheetModalForWindow:self.owner.window completionHandler:^(NSModalResponse response){
        NSString *project=nil;
        if(response==NSAlertFirstButtonReturn){NSError *error=nil;NSString *parent=[self.parent.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if(!parent.stringByExpandingTildeInPath.isAbsolutePath)error=ProjectSessionError(@"Enter a full parent folder path.");
            else project=[SINProjects createProjectInDirectory:parent name:self.name.stringValue error:&error];
            if(project){[SINProjects rememberProjectFolder:project settings:self.owner.store.settings error:&error];[self.owner.store saveSettings:&error];for(SINWindowController *window in ProjectWindows(self.owner))[window.navigator refresh];}
            if(error)[self.owner showError:error];
        }
        void (^done)(NSString *)=self.completion;self.completion=nil;if(done)done(project);
    }];
    [self.alert.window makeFirstResponder:self.name];
}
- (void)browse:(id)sender {
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseDirectories=YES;panel.canChooseFiles=NO;panel.allowsMultipleSelection=NO;panel.directoryURL=[NSURL fileURLWithPath:self.parent.stringValue];
    [panel beginSheetModalForWindow:self.alert.window completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK)self.parent.stringValue=panel.URL.path;}];
}
@end

@implementation SINWindowController (ProjectSession)
- (void)requestProjectWithCompletion:(void (^)(NSString *))completion {
    if(self.saving||self.annotating||self.window.attachedSheet)return;
    SINProjectCreateDialog *dialog=SINProjectCreateDialog.new;dialog.owner=self;dialog.completion=completion;[dialog show];
}
- (void)createProject { [self requestProjectWithCompletion:^(NSString *project){if(project)[self persist];}]; }
- (NSMenuItem *)projectMenuForItems:(NSArray *)items {
    NSMenuItem *root=[[NSMenuItem alloc] initWithTitle:@"Move to Project" action:nil keyEquivalent:@""];NSMenu *menu=[[NSMenu alloc] initWithTitle:root.title];menu.autoenablesItems=NO;root.submenu=menu;
    BOOL enabled=items.count&&!self.saving&&!self.annotating&&!self.window.attachedSheet;for(id item in items)if(!ProjectItemValid(item))enabled=NO;root.enabled=enabled;
    for(NSString *folder in [SINProjects knownProjectFoldersInSettings:self.store.settings]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:folder.lastPathComponent action:@selector(moveToProjectMenu:) keyEquivalent:@""];item.target=self;item.representedObject=@{@"items":items.copy,@"folder":folder};item.toolTip=folder;item.enabled=enabled;[menu addItem:item];
    }
    if(menu.numberOfItems)[menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *create=[[NSMenuItem alloc] initWithTitle:@"New Project…" action:@selector(newProjectMenu:) keyEquivalent:@""];create.target=self;create.representedObject=items.copy;create.enabled=enabled;[menu addItem:create];return root;
}
- (void)moveToProjectMenu:(NSMenuItem *)sender { [self moveItems:sender.representedObject[@"items"] toProject:sender.representedObject[@"folder"]]; }
- (void)newProjectMenu:(NSMenuItem *)sender { NSArray *items=sender.representedObject;[self requestProjectWithCompletion:^(NSString *folder){if(folder)[self moveItems:items toProject:folder];}]; }
- (void)moveItems:(NSArray *)items toProject:(NSString *)folder {
    [self moveItems:items toProject:folder completion:^(NSArray *results,NSArray *warnings,NSError *error){if(error)[self showError:error];else if(warnings.count)[self showError:ProjectSessionError([@"The prompt files moved. Follow-up is needed:\n\n" stringByAppendingString:[warnings componentsJoinedByString:@"\n"]])];}];
}
- (void)moveItems:(NSArray *)items toProject:(NSString *)folder completion:(void (^)(NSArray<SINProjectMoveResult *> *,NSArray<NSString *> *,NSError *))completion {
    if(!items.count){completion(nil,@[],ProjectSessionError(@"Select saved HTML prompts to move into a project."));return;}
    NSMutableArray *paths=NSMutableArray.new;
    for(id item in items) {
        if(!ProjectItemValid(item)){completion(nil,@[],ProjectSessionError(@"Select saved HTML prompts. Save new documents and uncheck other file types first."));return;}
        NSString *path=ProjectItemPath(item);BOOL duplicate=NO;for(NSString *other in paths)if(ProjectSessionSamePath(path,other)){duplicate=YES;break;}if(!duplicate)[paths addObject:path];
    }
    SINProjectRun *run=SINProjectRun.new;run.owner=self;run.paths=paths;run.destination=folder.stringByExpandingTildeInPath.stringByStandardizingPath;run.completion=completion;[run start];
}
@end
