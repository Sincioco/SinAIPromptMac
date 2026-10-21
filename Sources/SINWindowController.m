#import "SINWindowController.h"
#import "SINNativeServices.h"
#import "SINTabButton.h"
#import "SINAppDelegate.h"
#import "SINWorkspaceSplitView.h"
#import "SINProjectSession.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <PDFKit/PDFKit.h>
static NSError *ShellError(NSString *text){return[NSError errorWithDomain:@"SinShell" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSArray<SINWindowController *> *WindowPeers(SINWindowController *owner){NSMutableArray *windows=NSMutableArray.new;for(SINWindowController *window in ((SINAppDelegate *)NSApp.delegate).windows)if(window.store==owner.store)[windows addObject:window];if(![windows containsObject:owner])[windows addObject:owner];return windows;}
@interface SINWindowController ()
@property(nonatomic) BOOL layingOutChrome;
@end
@implementation SINWindowController
- (instancetype)initWithStore:(SINStore *)store restore:(BOOL)restore {
    NSError *error=nil;NSArray *documents=restore?[store restoreDocuments:&error]:@[];
    if(error)NSLog(@"Recovery: %@",error.localizedDescription);
    return [self initWithStore:store documents:documents activeIdentifier:store.activeIdentifier];
}
- (instancetype)initWithStore:(SINStore *)store documents:(NSArray<SINDocument*>*)documents activeIdentifier:(NSString*)identifier {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,820) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if((self=[super initWithWindow:window])){
        self.store=store;self.documents=NSMutableArray.new;self.editors=NSMutableDictionary.new;window.delegate=self;window.minSize=NSMakeSize(880,430);window.title=@"Sin — AI Prompt";[window center];window.releasedWhenClosed=NO;
        [self buildWorkspace];
        NSError *error=nil;[self.documents addObjectsFromArray:documents?:@[]];
        if(!self.documents.count){SINDocument *document=[store newDocument:&error];if(document)[self.documents addObject:document];}
        SINDocument *selected=self.documents.firstObject;for(SINDocument *doc in self.documents)if([doc.identifier isEqual:identifier])selected=doc;
        if(selected)[self activate:selected];
        NSString *theme=[self.store.settings[@"theme"] lowercaseString];self.window.appearance=[theme isEqual:@"dark"]?[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]:([theme isEqual:@"light"]?[NSAppearance appearanceNamed:NSAppearanceNameAqua]:nil);
        __weak typeof(self) weakSelf=self;
        self.timer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){[weakSelf tick];}];
    }return self;
}
- (void)buildWorkspace {
    NSView *content=self.window.contentView;
    self.tabScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,784,1280,36)];self.tabScroll.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;self.tabScroll.hasHorizontalScroller=YES;self.tabScroll.scrollerStyle=NSScrollerStyleOverlay;
    self.tabs=[NSStackView stackViewWithViews:@[]];self.tabs.orientation=NSUserInterfaceLayoutOrientationHorizontal;self.tabs.spacing=4;self.tabs.edgeInsets=NSEdgeInsetsMake(3,8,3,8);self.tabs.frame=NSMakeRect(0,0,1260,34);self.tabScroll.documentView=self.tabs;self.tabScroll.hidden=![self.store.settings[@"showTabs"] boolValue];[content addSubview:self.tabScroll];
    self.status=[NSTextField labelWithString:@"Ready"];self.status.frame=NSMakeRect(10,3,1260,22);self.status.autoresizingMask=NSViewWidthSizable;self.status.font=[NSFont systemFontOfSize:11];self.status.textColor=NSColor.secondaryLabelColor;self.status.lineBreakMode=NSLineBreakByTruncatingMiddle;self.status.hidden=[self.store.settings[@"statusBar"] isEqual:@NO];[content addSubview:self.status];
    self.editorHost=[[NSView alloc] initWithFrame:NSMakeRect(0,28,1280,756)];self.editorHost.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[content addSubview:self.editorHost];
    self.split=[[SINWorkspaceSplitView alloc] initWithFrame:NSMakeRect(0,28,1280,756)];self.split.vertical=YES;self.split.dividerStyle=NSSplitViewDividerStyleThin;self.split.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.split.delegate=self;
    self.navigator=SINNavigator.new;self.navigator.directory=self.store.settings[@"explorerDirectory"]?:@"";self.navigator.sortMode=self.store.settings[@"documentSort"]?:@"manual";
    NSInteger mode=[self.store.settings[@"navigationMode"] integerValue];if(mode==2){self.store.settings[@"contentView"]=@YES;mode=1;self.store.settings[@"navigationMode"]=@1;}self.navigator.mode=mode;self.navigator.showFolders=![self.store.settings[@"explorerShowFolders"] isEqual:@NO];
    self.navigator.view.frame=NSMakeRect(0,0,250,756);[self.split addSubview:self.navigator.view];
    self.contentsNavigator=SINNavigator.new;self.contentsNavigator.contentsOnly=YES;self.contentsNavigator.mode=2;self.contentsNavigator.view.frame=NSMakeRect(251,0,MAX(160,[self.store.settings[@"contentWidth"] doubleValue]),756);self.contentsNavigator.view.hidden=![self.store.settings[@"contentView"] boolValue];if(!self.contentsNavigator.view.hidden)[self.split addSubview:self.contentsNavigator.view];
    self.documentPane=[[NSView alloc] initWithFrame:NSMakeRect(251,0,1029,756)];((SINWorkspaceSplitView *)self.split).documentPane=self.documentPane;[self.split addSubview:self.documentPane];[self.split setPosition:MAX(180,[self.store.settings[@"listWidth"] doubleValue]) ofDividerAtIndex:0];self.navigator.view.hidden=[self.store.settings[@"navigationVisible"] isEqual:@NO];[self.split adjustSubviews];[content addSubview:self.split];[self layoutChrome];
    __weak typeof(self) weakSelf=self;
    self.navigator.selected=^(id item){if(weakSelf.saving)return;if([item isKindOfClass:SINDocument.class])[weakSelf activate:item];else if([item isKindOfClass:NSDictionary.class])[weakSelf.editor evaluate:[NSString stringWithFormat:@"window.editor.outline.jump(%@)",item[@"index"]] completion:nil];else [weakSelf openPaths:@[item]];};
    self.contentsNavigator.selected=^(id item){if([item isKindOfClass:NSDictionary.class])[weakSelf.editor evaluate:[NSString stringWithFormat:@"window.editor.outline.jump(%@)",item[@"index"]] completion:nil];};
    self.navigator.action=^(NSString *action,id item){[weakSelf navigateAction:action item:item];};
    self.navigator.documentMenu=^NSMenu *(SINDocument *document){return [weakSelf documentContextMenu:document documentList:YES];};
    self.navigator.contextActionsEnabled=^BOOL{return weakSelf&&!weakSelf.annotating&&!weakSelf.saving&&!weakSelf.window.attachedSheet;};
    self.navigator.projectMenu=^NSMenuItem *(NSArray *items){return [weakSelf projectMenuForItems:items];};
    self.navigator.reordered=^(NSArray *documents){NSMutableArray *all=documents.mutableCopy;for(SINDocument *doc in weakSelf.documents)if(![all containsObject:doc])[all addObject:doc];weakSelf.documents=all;weakSelf.store.settings[@"documentSort"]=@"manual";weakSelf.navigator.sortMode=@"manual";[weakSelf sortDocuments];[weakSelf refresh];[weakSelf persist];};
}
- (void)setPreview:(NSView *)preview { _preview=preview;[self layoutChrome]; }
- (SINEditor *)editor {return self.editors[self.active.identifier];}
- (SINEditor *)editorFor:(SINDocument *)document {
    SINEditor *editor=self.editors[document.identifier];if(editor)return editor;
    editor=[[SINEditor alloc] initWithDocument:document dataDirectory:self.store.directory];editor.preferences=self.store.settings;self.editors[document.identifier]=editor;
    __weak typeof(self) weakSelf=self;__weak SINEditor *weakEditor=editor;
    editor.changed=^{if(weakEditor.document.modified)weakEditor.document.modifiedDate=NSDate.date;[weakSelf sortDocuments];[weakSelf refresh];};editor.command=^(NSString *command){[weakSelf handleCommand:command];};
    editor.selectionChanged=^{if(weakSelf.editor==weakEditor)[weakSelf refresh];};
    editor.imageStatus=^(NSString *path){if(weakSelf.editor==weakEditor){weakSelf.imageStatus=path;[weakSelf refresh];}};
    editor.annotationMode=^(BOOL open){[weakSelf setAnnotationMode:open editor:weakEditor];};
    editor.nativeMessage=^(NSDictionary *body,void(^reply)(id,NSError*)){[weakSelf receiveMessage:body editor:weakEditor reply:reply];};
    editor.chromeChanged=^{if(weakSelf.editor==weakEditor)[weakSelf layoutChrome];};
    editor.readyHandler=^{[weakEditor applyPreferences];[weakSelf layoutChrome];};return editor;
}
- (void)activate:(SINDocument *)document {
    if(!document||self.annotating)return;
    if(document.privateDocument&&[self.store.settings[@"showPrivateDocuments"] isEqual:@NO]){self.store.settings[@"showPrivateDocuments"]=@YES;[self refreshPrivacy];}
    void(^show)(void)=^{
        [self.preview removeFromSuperview];self.preview=nil;
        SINEditor *old=self.editor;if(old&&old.document!=document)[old evaluate:@"window.editor.stopMedia()" completion:nil];
        [old.view removeFromSuperview];self.active=document;self.imageStatus=@"";[self sortDocuments];
        SINEditor *editor=[self editorFor:document];editor.view.frame=self.editorHost.bounds;editor.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[self.editorHost addSubview:editor.view];
        editor.services.window=self.window;[self layoutChrome];[self refresh];[editor focusEditor];[self persist];
    };
    if(self.editor)[self.editor flush:show];else show();
}
- (void)refresh {
    if(!self.active)return;
    self.window.title=[NSString stringWithFormat:@"%@%@ — Sin — AI Prompt",self.active.name,self.active.modified?@" *":@""];self.window.documentEdited=self.active.modified;
    self.window.representedURL=self.active.path?[NSURL fileURLWithPath:self.active.path]:nil;
    NSString *text=self.active.text;NSUInteger location=self.editor.showingSource?MIN(self.editor.sourceView.selectedRange.location,text.length):0;NSUInteger line=1,col=1;
    if(self.editor.showingSource)for(NSUInteger i=0;i<location;i++){if([text characterAtIndex:i]=='\n'){line++;col=1;}else col++;}
    self.status.stringValue=[NSString stringWithFormat:@"Ln %lu, Col %lu    ·    %lu characters    ·    %@    ·    %ld%%    ·    %@    ·    %@%@",line,col,text.length,self.active.path?:@"Unsaved document",self.active.zoom,[self.active.newline isEqual:@"\r\n"]?@"CRLF":([self.active.newline isEqual:@"\r"]?@"CR":@"LF"),self.active.encodingName,self.active.readOnly?@"    ·    Locked":@""];
    if(self.imageStatus.length)self.status.stringValue=[self.status.stringValue stringByAppendingFormat:@"    ·    %@",self.imageStatus];
    NSArray<SINDocument *> *visible=self.visibleDocuments;
    BOOL rebuild=self.tabs.arrangedSubviews.count!=visible.count+1;
    if(!rebuild)for(NSUInteger i=0;i<visible.count;i++)if(![self.tabs.arrangedSubviews[i].identifier isEqual:visible[i].identifier]){rebuild=YES;break;}
    if(rebuild){
        for(NSView *view in self.tabs.arrangedSubviews.copy){[self.tabs removeArrangedSubview:view];[view removeFromSuperview];}
        __weak typeof(self) weakSelf=self;
        for(SINDocument *doc in visible){SINTabButton *button=[[SINTabButton alloc] initWithFrame:NSMakeRect(0,0,100,28)];button.target=self;button.action=@selector(tabClicked:);button.identifier=doc.identifier;button.bezelStyle=NSBezelStyleRounded;[button setButtonType:NSButtonTypePushOnPushOff];
            button.moveDocument=^(NSString *source,NSString *target){SINWindowController *owner=weakSelf;NSUInteger from=[owner.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.identifier isEqual:source];}],to=[owner.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.identifier isEqual:target];}];if(from==NSNotFound||to==NSNotFound||from==to)return;SINDocument *moved=owner.documents[from];[owner.documents removeObjectAtIndex:from];[owner.documents insertObject:moved atIndex:to];owner.navigator.sortMode=@"manual";owner.store.settings[@"documentSort"]=@"manual";[owner refresh];[owner persist];};
            button.closeDocument=^(NSString *identifier){if(weakSelf.annotating)return;for(SINDocument *d in weakSelf.documents)if([d.identifier isEqual:identifier]){[weakSelf closeDocument:d];break;}};
            button.documentMenu=^NSMenu *(NSString *identifier){for(SINDocument *d in weakSelf.documents)if([d.identifier isEqual:identifier])return [weakSelf documentContextMenu:d];return nil;};
            [self.tabs addArrangedSubview:button];
        }
        NSButton *add=[NSButton buttonWithTitle:@"+" target:self action:@selector(newClicked:)];[self.tabs addArrangedSubview:add];
    }
    CGFloat width=52;for(NSUInteger i=0;i<visible.count;i++){SINDocument *doc=visible[i];NSButton *button=(NSButton*)self.tabs.arrangedSubviews[i];button.title=[NSString stringWithFormat:@"%@%@%@%@%@%@",doc.emoji.length?[doc.emoji stringByAppendingString:@" "]:@"",doc.pinned?@"📌 ":@"",doc.readOnly?@"🔒 ":@"",doc.name,[SINProjects displaySuffixForDocumentPath:doc.path],doc.modified?@" *":@""];button.state=doc==self.active?NSControlStateValueOn:NSControlStateValueOff;button.toolTip=doc.path?:doc.name;width+=MAX(100,button.intrinsicContentSize.width)+4;}
    self.tabs.frame=NSMakeRect(0,0,MAX(width,self.tabScroll.contentSize.width),34);
    self.navigator.documents=visible;self.navigator.allDocuments=self.documents.copy;self.navigator.emojis=self.store.settings[@"documentEmojis"];if(rebuild||self.navigator.mode==1)[self.navigator refresh];[self.navigator selectDocument:self.active];
}
- (void)tabClicked:(NSButton *)sender {if(self.saving)return;for(SINDocument *doc in self.documents)if([doc.identifier isEqual:sender.identifier]){[self activate:doc];break;}}
- (void)newClicked:(id)sender {[self handleCommand:@"new"];}
- (NSArray<SINDocument *> *)recoveryDocuments {
    NSMutableArray *documents=NSMutableArray.new,*groups=NSMutableArray.new;NSMutableSet *seen=NSMutableSet.new;
    SINAppDelegate *delegate=(SINAppDelegate *)NSApp.delegate;
    NSMutableArray *windows=delegate.windows.mutableCopy?:NSMutableArray.new;if(![windows containsObject:self])[windows addObject:self];
    [windows sortUsingComparator:^NSComparisonResult(SINWindowController *a,SINWindowController *b){return a.closing==b.closing?NSOrderedSame:(a.closing?NSOrderedDescending:NSOrderedAscending);}];
    for(SINWindowController *controller in windows){if(controller.store!=self.store)continue;if(controller.closing&&[controller.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return d.modified;}]==NSNotFound)continue;NSMutableArray *identifiers=NSMutableArray.new;
        for(SINDocument *doc in controller.documents){if(![seen containsObject:doc.identifier]){[documents addObject:doc];[seen addObject:doc.identifier];}[identifiers addObject:doc.identifier];}
        [groups addObject:@{@"documents":identifiers,@"active":controller.active.identifier?:@"",@"frame":NSStringFromRect(controller.window.frame)}];
    }
    self.store.settings[@"sessionWindows"]=groups;
    return documents;
}
- (void)persist {
    if(self.testMode)return;NSArray *documents=[self recoveryDocuments];
    NSError *error=nil;
    self.recoveryError=nil;
    if(![self.store saveSessionDocuments:documents activeIdentifier:self.active.identifier error:&error]){self.recoveryError=error;self.status.stringValue=[@"Recovery could not be saved: " stringByAppendingString:error.localizedDescription];NSLog(@"%@",error);}
}
- (void)persistInBackground {if(self.testMode)return;[self.store saveSessionDocuments:[self recoveryDocuments] activeIdentifier:self.active.identifier completion:^(NSError *error){self.recoveryError=error;if(error)self.status.stringValue=[@"Recovery could not be saved: " stringByAppendingString:error.localizedDescription];}];}
- (void)tick {
    if(self.testMode||self.annotating||self.saving)return;
    [self.editor captureView:^{[self persistInBackground];}];
    for(SINDocument *document in self.documents)if(document.autosave&&document.modified&&!document.readOnly&&document.path){NSError *error=nil;if(![document saveToPath:document.path overwriteConflict:NO error:&error])self.status.stringValue=[@"Autosave paused: " stringByAppendingString:error.localizedDescription];}
    if(self.navigator.mode==0)[self.navigator refresh];
    if(!self.contentsNavigator.view.hidden&&self.editor.ready)[self.editor evaluate:@"window.editor.outline.items()" completion:^(id items,NSError *error){if([items isKindOfClass:NSArray.class]){self.contentsNavigator.headings=items;[self.contentsNavigator refresh];}}];
}
- (void)showError:(NSError *)error {if(!error)return;NSLog(@"Sin: %@",error.localizedDescription);if(self.testMode)return;NSAlert *alert=[NSAlert alertWithError:error];if(self.window.attachedSheet){[alert runModal];}else [alert beginSheetModalForWindow:self.window completionHandler:nil];}
- (void)openPaths:(NSArray<NSString*> *)paths {
    if(self.saving||self.annotating)return;
    for(NSString *raw in paths){NSString *path=raw.stringByStandardizingPath;NSString *ext=path.pathExtension.lowercaseString;
        if([@[@"md",@"markdown"] containsObject:ext]){[self importMarkdown:path completion:^(SINDocument *doc,NSError *error){if(error){[self showError:error];return;}[self.documents addObject:doc];[self.store addRecentPath:doc.path];[self activate:doc];}];continue;}
        if(![@[@"html",@"htm"] containsObject:ext]){[self showPreview:path];continue;}
        SINDocument *existing=nil;for(SINDocument *doc in self.documents)if([doc.path isEqual:path])existing=doc;
        if(existing){[self activate:existing];continue;}
        NSError *error=nil;SINDocument *doc=[SINDocument openPath:path error:&error];if(!doc){[self showError:error];continue;}[self.store restoreDocumentMetadata:doc];[self.documents addObject:doc];[self.store addRecentPath:path];[self activate:doc];
    }
}
- (void)setAnnotationMode:(BOOL)open editor:(SINEditor *)editor {
    self.annotating=open;self.split.hidden=open;
    if(open){[editor.view removeFromSuperview];editor.view.frame=self.window.contentView.bounds;[self.window.contentView addSubview:editor.view];[editor setNavigationWidth:0];}
    else {[editor.view removeFromSuperview];editor.view.frame=self.editorHost.bounds;[self.editorHost addSubview:editor.view];[self layoutChrome];[self refresh];}
}
- (void)receiveMessage:(NSDictionary *)body editor:(SINEditor *)editor reply:(void(^)(id,NSError*))reply {
    NSString *type=body[@"type"];
    if([type isEqual:@"templates-load"]){reply([self.store.templates copy],nil);return;}
    if([type isEqual:@"templates-save"]){NSError *error=nil;self.store.templates=[body[@"templates"] mutableCopy];[self.store saveTemplates:&error];reply(nil,error);return;}
    if([type isEqual:@"recent-colors"]){reply(self.store.settings[@"recentColors"]?:@[],nil);return;}
    if([type isEqual:@"color-used"]){NSMutableArray *colors=[(self.store.settings[@"recentColors"]?:@[]) mutableCopy];[colors removeObject:body[@"value"]];[colors insertObject:body[@"value"] atIndex:0];while(colors.count>10)[colors removeLastObject];self.store.settings[@"recentColors"]=colors;[self.store saveSettings:nil];reply(nil,nil);return;}
    if([type isEqual:@"rename-image"]){NSError *error=nil;NSString *path=[editor.services localPathForSource:body[@"source"] base:nil error:&error];if(path)[self navigateAction:@"renamePath" item:path];reply(nil,error);return;}
    if([type isEqual:@"drop-paths"]){
        NSArray<NSURL*> *urls=nil;
        urls=[[NSPasteboard pasteboardWithName:NSPasteboardNameDrag] readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
        NSArray *names=body[@"names"];NSMutableArray *paths=NSMutableArray.new;for(NSURL *url in urls)if([names containsObject:url.lastPathComponent])[paths addObject:url.path];
        if(paths.count!=names.count||!paths.count){reply(@NO,nil);return;}
        [self handleDroppedPaths:paths editor:editor];reply(@YES,nil);return;
    }
    if([type isEqual:@"drop-files"]){
        for(NSDictionary *file in body[@"files"]){NSString *dataURL=file[@"data"]?:@"";if([body[@"kind"] isEqual:@"images"]){[editor evaluate:[NSString stringWithFormat:@"window.editor.insertImage(%@);void 0",SINJSON(dataURL)] completion:nil];}
            else {NSArray *parts=[dataURL componentsSeparatedByString:@","];NSData *data=parts.count>1?[[NSData alloc] initWithBase64EncodedString:parts.lastObject options:0]:nil;NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text){NSError *error=nil;SINDocument *doc=[self.store newDocument:&error];doc.text=text;doc.draftName=file[@"name"];[self.documents addObject:doc];[self activate:doc];}}}
        reply(@YES,nil);return;
    }
    BOOL needsSaved=[type isEqual:@"save-image"]||([type isEqual:@"reference-image"]&&![body[@"absolute"] boolValue])||[type isEqual:@"region-capture"];
    void(^perform)(void)=^{editor.services.documentPath=editor.document.path;editor.services.window=self.window;if(![editor.services handleMessage:body completion:reply])reply(nil,ShellError([@"Native command is not implemented: " stringByAppendingString:type?:@""]));};
    if(needsSaved&&!editor.document.path){[self saveDocument:editor.document saveAs:NO completion:^(BOOL saved){if(saved)perform();else reply(nil,ShellError(@"Save the HTML document before creating a separate image or a relative reference."));}];}else perform();
}
- (void)handleDroppedPaths:(NSArray<NSString*>*)paths editor:(SINEditor *)editor {
    for(NSString *path in paths){if([@[@"html",@"htm",@"md",@"txt",@"pdf"] containsObject:path.pathExtension.lowercaseString])[self openPaths:@[path]];else [editor evaluate:[NSString stringWithFormat:@"window.editor.insertImage(%@);void 0",SINJSON([NSURL fileURLWithPath:path].absoluteString)] completion:nil];}
}
- (void)handleCommand:(NSString *)command {
    if(self.annotating||self.saving)return;
    if([command isEqual:@"new"]){NSError *error=nil;SINDocument *doc=[self.store newDocument:&error];if(doc){[self.documents addObject:doc];[self activate:doc];}else [self showError:error];}
    else if([command isEqual:@"open"]){NSOpenPanel *p=NSOpenPanel.openPanel;p.allowsMultipleSelection=YES;p.allowedContentTypes=@[UTTypeHTML,UTTypePlainText,UTTypeImage,UTTypePDF];[p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r==NSModalResponseOK)[self openPaths:[p.URLs valueForKey:@"path"]];}];}
    else if([@[@"save",@"saveAs"] containsObject:command])[self saveDocument:self.active saveAs:[command isEqual:@"saveAs"] completion:^(BOOL saved){}];
    else if([command isEqual:@"saveAll"])[self saveAllAtIndex:0];
    else if([command isEqual:@"close"]){if(self.preview){[self.preview removeFromSuperview];self.preview=nil;[self.editor focusEditor];}else [self closeDocument:self.active];}
    else if([command isEqual:@"source"])[self.editor showSource:!self.editor.showingSource completion:nil];
    else if([command isEqual:@"find"]||[command isEqual:@"replace"])[self.editor showFind:[command isEqual:@"replace"]];
    else if([command isEqual:@"findNext"]||[command isEqual:@"findPrevious"])[self.editor findNext:[command isEqual:@"findPrevious"]];
    else if([@[@"undo",@"redo",@"cut",@"copy",@"paste",@"pasteText",@"delete",@"selectAll",@"bold",@"italic",@"underline"] containsObject:command])[self.editor editCommand:command value:nil];
    else if([@[@"zoomIn",@"zoomOut",@"zoomReset"] containsObject:command]){self.active.zoom=[command isEqual:@"zoomReset"]?100:MAX(25,MIN(400,self.active.zoom+([command isEqual:@"zoomIn"]?10:-10)));[self.editor applyPreferences];[self refresh];}
    else if([@[@"next",@"previous"] containsObject:command]){NSArray *docs=self.visibleDocuments;NSUInteger index=[docs indexOfObject:self.active];if(docs.count)[self activate:docs[(index+docs.count+([command isEqual:@"next"]?1:-1))%docs.count]];}
    else if([command isEqual:@"documentList"]){self.navigator.view.hidden=!self.navigator.view.hidden;self.tabScroll.hidden=!self.navigator.view.hidden;self.store.settings[@"navigationVisible"]=@(!self.navigator.view.hidden);self.store.settings[@"showTabs"]=@(!self.tabScroll.hidden);[self.split adjustSubviews];[self layoutChrome];[self persist];}
    else if([command isEqual:@"contentView"]){BOOL show=self.contentsNavigator.view.hidden;self.contentsNavigator.view.hidden=!show;self.store.settings[@"contentView"]=@(show);if(show)[self.split addSubview:self.contentsNavigator.view positioned:NSWindowBelow relativeTo:self.documentPane];else [self.contentsNavigator.view removeFromSuperview];[self.split adjustSubviews];[self layoutChrome];[self.editor evaluate:@"window.editor.outline.items()" completion:^(id items,NSError *e){self.contentsNavigator.headings=[items isKindOfClass:NSArray.class]?items:@[];[self.contentsNavigator refresh];}];[self persist];}
    else if([command isEqual:@"multiSelection"]){self.navigator.multiSelection=!self.navigator.multiSelection;}
    else if([command isEqual:@"showPrivateDocuments"]){self.store.settings[@"showPrivateDocuments"]=@(![self.store.settings[@"showPrivateDocuments"] boolValue]);for(SINWindowController *window in WindowPeers(self))[window refreshPrivacy];}
    else if([command isEqual:@"combineSelection"])[self combineItems:self.navigator.checkedItems];
    else if([command isEqual:@"deleteSelection"])[self deleteItems:self.navigator.checkedItems];
    else if([command isEqual:@"createProject"])[self createProject];
    else if([command hasPrefix:@"reference:"])[self addBundledDocument:[command substringFromIndex:10]];
    else if([command isEqual:@"settings"])[self showSettings];
    else if([command isEqual:@"scanUnused"])[self scanUnusedImages];
    else if([command isEqual:@"rename"])[self renameDocument:self.active];
    else if([command isEqual:@"exportHTML"])[self exportDocument:NO];
    else if([command isEqual:@"exportMarkdown"])[self exportDocument:YES];
    else if([command isEqual:@"lock"]||[command isEqual:@"unlock"])[self changeDocumentLock:self.active locked:[command isEqual:@"lock"] completion:nil];
    else if([command isEqual:@"date"]||[command isEqual:@"longDate"]||[command isEqual:@"dateSeparator"]){
        NSArray *patterns=@[@"EEEE, MMMM d, yyyy 'at' h:mm a",@"M/d/yyyy",@"M/d/yyyy h:mm a",@"yyyyMMddHHmm",@"yyyy-MM-dd HHmm",@"yyyy-MM-dd' - 'HHmm"];
        NSInteger choice=[command isEqual:@"longDate"]?0:MIN(5,MAX(0,[self.store.settings[@"dateTimeFormat"] integerValue]));
        NSDateFormatter *format=NSDateFormatter.new;format.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];format.dateFormat=patterns[choice];format.AMSymbol=@"am";format.PMSymbol=@"pm";
        NSString *text=[format stringFromDate:NSDate.date];if([command isEqual:@"dateSeparator"])text=[text stringByAppendingFormat:@"\n%@\n",[@"" stringByPaddingToLength:80 withString:@"_" startingAtIndex:0]];[self.editor editCommand:[command isEqual:@"longDate"]&&!self.editor.showingSource?@"insertDateHeading":@"insertText" value:text];
    }
    else if([command isEqual:@"separator"])[self.editor editCommand:@"insertText" value:[NSString stringWithFormat:@"\n%@\n",[@"" stringByPaddingToLength:80 withString:@"_" startingAtIndex:0]]];
    else if([command isEqual:@"goTo"])[self goToLine];
    else if([command isEqual:@"tabBar"]){self.tabScroll.hidden=!self.tabScroll.hidden;self.store.settings[@"showTabs"]=@(!self.tabScroll.hidden);[self layoutChrome];[self persist];}
    else if([command isEqual:@"statusBar"]){self.status.hidden=!self.status.hidden;self.store.settings[@"statusBar"]=@(!self.status.hidden);[self layoutChrome];[self persist];}
    else if([@[@"lineNumbers",@"wordWrap",@"wrapToolbar",@"showToolbar",@"showSpellcheck"] containsObject:command]){self.store.settings[command]=@(![self.store.settings[command] boolValue]);for(SINWindowController *window in WindowPeers(self))for(SINEditor *editor in window.editors.allValues){editor.preferences=self.store.settings;[editor applyPreferences];}[self.store saveSettings:nil];}
    else if([command hasPrefix:@"sort:"]){
        NSString *mode=[command substringFromIndex:5];
        if([self.navigator.sortMode isEqual:@"manual"])self.store.settings[@"manualDocumentOrder"]=[self.documents valueForKey:@"identifier"];
        self.navigator.sortMode=mode;self.store.settings[@"documentSort"]=mode;
        NSArray *manual=self.store.settings[@"manualDocumentOrder"]?:@[];
        [self.documents sortUsingComparator:^NSComparisonResult(SINDocument *a,SINDocument *b){if(a.pinned!=b.pinned)return a.pinned?NSOrderedAscending:NSOrderedDescending;
            if([mode isEqual:@"manual"]){NSUInteger ai=[manual indexOfObject:a.identifier],bi=[manual indexOfObject:b.identifier];return ai==bi?NSOrderedSame:(ai<bi?NSOrderedAscending:NSOrderedDescending);}
            return [mode isEqual:@"created"]?[b.createdDate compare:a.createdDate]:[b.modifiedDate compare:a.modifiedDate];}];
        [self refresh];[self persist];
    }
    else if([command isEqual:@"chooseFolder"]){NSOpenPanel *p=NSOpenPanel.openPanel;p.canChooseDirectories=YES;p.canChooseFiles=NO;[p beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r==NSModalResponseOK){self.navigator.directory=p.URL.path;self.store.settings[@"explorerDirectory"]=p.URL.path;[self.navigator refresh];[self.store saveSettings:nil];}}];}
    else if([command isEqual:@"refresh"])[self.navigator refresh];
    else if([command isEqual:@"encoding"])[self chooseEncoding];
    else if([command isEqual:@"newline"]){self.active.newline=[self.active.newline isEqual:@"\n"]?@"\r\n":@"\n";[self refresh];}
    else if([command hasPrefix:@"newline:"]){self.active.newline=[@{@"LF":@"\n",@"CRLF":@"\r\n",@"CR":@"\r"} objectForKey:[command substringFromIndex:8]]?:@"\n";[self refresh];}
    else [self navigateAction:command item:self.active];
}
- (void)layoutChrome {
    if(self.layingOutChrome || !self.split)return;self.layingOutChrome=YES;
    NSRect bounds=self.window.contentView.bounds;CGFloat top=self.tabScroll.hidden?0:36,bottom=self.status.hidden?0:28;
    self.editorHost.frame=NSMakeRect(0,bottom,bounds.size.width,MAX(0,bounds.size.height-top-bottom));
    SINEditor *editor=self.editor;editor.view.hidden=self.preview!=nil && !self.annotating;
    CGFloat ribbon=self.preview?0:MIN(editor.ribbonHeight,self.editorHost.bounds.size.height);
    self.split.frame=NSMakeRect(0,bottom,bounds.size.width,MAX(0,self.editorHost.bounds.size.height-ribbon));
    CGFloat inset=self.navigator.view.hidden?0:NSMaxX(self.navigator.view.frame)+self.split.dividerThickness;
    if(!self.contentsNavigator.view.hidden)inset=NSMaxX(self.contentsNavigator.view.frame)+self.split.dividerThickness;
    [editor setNavigationWidth:self.annotating?0:inset];
    self.split.hidden=self.annotating || (!self.preview && !editor.showingSource && editor.modalOverlay);
    NSMutableArray *holes=NSMutableArray.new;
    if(!self.preview && !editor.showingSource)for(NSValue *value in editor.overlayRects)[holes addObject:[NSValue valueWithRect:[self.split convertRect:value.rectValue fromView:editor.webView]]];
    ((SINWorkspaceSplitView *)self.split).excludedRects=holes;
    self.layingOutChrome=NO;
}
- (void)saveAllAtIndex:(NSUInteger)index {if(index>=self.documents.count)return;[self saveDocument:self.documents[index] saveAs:NO completion:^(BOOL saved){if(saved)[self saveAllAtIndex:index+1];}];}
- (void)goToLine {NSAlert *alert=NSAlert.new;alert.messageText=@"Go to line";NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,220,26)];field.stringValue=@"1";alert.accessoryView=field;[alert addButtonWithTitle:@"Go"];[alert addButtonWithTitle:@"Cancel"];[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r!=NSAlertFirstButtonReturn)return;[self.editor showSource:YES completion:^{NSUInteger target=MAX(1,field.integerValue),line=1,index=0;NSString *text=self.editor.sourceView.string;while(index<text.length&&line<target){if([text characterAtIndex:index++]=='\n')line++;}self.editor.sourceView.selectedRange=NSMakeRange(index,0);[self.editor.sourceView scrollRangeToVisible:NSMakeRange(index,0)];}];}];}
- (void)chooseEncoding {NSAlert *alert=NSAlert.new;alert.messageText=@"Document encoding";NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,240,28)];[popup addItemsWithTitles:SINDocument.encodingNames];[popup selectItemWithTitle:self.active.encodingName];alert.accessoryView=popup;[alert addButtonWithTitle:@"Apply"];[alert addButtonWithTitle:@"Cancel"];[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r==NSAlertFirstButtonReturn){self.active.encodingName=popup.titleOfSelectedItem;[self refresh];}}];}
- (BOOL)splitView:(NSSplitView *)split canCollapseSubview:(NSView *)view{return view!=self.documentPane;}
- (BOOL)splitView:(NSSplitView *)split shouldAdjustSizeOfSubview:(NSView *)view{return view==self.documentPane;}
- (CGFloat)splitView:(NSSplitView *)split constrainMinCoordinate:(CGFloat)value ofSubviewAt:(NSInteger)index{return 180;}
- (CGFloat)splitView:(NSSplitView *)split constrainMaxCoordinate:(CGFloat)value ofSubviewAt:(NSInteger)index{return split.bounds.size.width-400;}
- (void)windowDidBecomeKey:(NSNotification *)note {[self checkExternalChange];}
- (void)splitViewDidResizeSubviews:(NSNotification *)note {if(!self.navigator.view.hidden)self.store.settings[@"listWidth"]=@(self.navigator.view.frame.size.width);if(!self.contentsNavigator.view.hidden)self.store.settings[@"contentWidth"]=@(self.contentsNavigator.view.frame.size.width);[self layoutChrome];}
- (void)windowDidResize:(NSNotification *)note {[self layoutChrome];}
- (BOOL)windowShouldClose:(NSWindow *)window {
    if(self.closing)return YES;
    [self prepareToClose:^(BOOL ready){if(!ready)return;[self persist];if(self.recoveryError){[self showError:self.recoveryError];return;}self.closing=YES;[self.timer invalidate];[self.window close];}];return NO;
}
- (void)windowWillClose:(NSNotification *)note {for(SINEditor *editor in self.editors.allValues)[editor invalidate];}
@end
