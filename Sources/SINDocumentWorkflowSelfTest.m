#import "SINWindowController.h"
#import "SINAppDelegate.h"

@interface SINWorkflowCheckWindow : SINWindowController
@property(nonatomic,strong) NSError *workflowFailure;
@end
@implementation SINWorkflowCheckWindow
- (void)showError:(NSError *)error {self.workflowFailure=error;}
@end
static NSError *WorkflowCheckError(NSString *text){return [NSError errorWithDomain:@"SinDocumentWorkflowTest" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static void WorkflowCheckPoll(BOOL(^condition)(void),NSUInteger remaining,void(^done)(BOOL)){
    if(condition()){done(YES);return;}if(!remaining){done(NO);return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WorkflowCheckPoll(condition,remaining-1,done);});
}
static void WorkflowCheckSteps(NSArray *steps,NSUInteger index,BOOL(^finished)(void),void(^done)(NSError *)){
    if(finished())return;if(index==steps.count){done(nil);return;}void(^step)(void(^)(NSError *))=steps[index];step(^(NSError *error){if(error)done(error);else WorkflowCheckSteps(steps,index+1,finished,done);});
}
static void WorkflowCheckReady(SINEditor *editor,void(^done)(NSError *)){
    (void)editor.view;WorkflowCheckPoll(^BOOL{return editor.ready;},250,^(BOOL ready){if(!ready){done(WorkflowCheckError(@"Workflow editor did not become ready."));return;}[editor asyncScript:@"await window.editor.ready();return true;" completion:^(id value,NSError *error){done(error);}];});
}
static void WorkflowCheckSheet(SINWorkflowCheckWindow *window,NSModalResponse response,void(^done)(NSError *)){
    WorkflowCheckPoll(^BOOL{return window.window.attachedSheet||window.workflowFailure;},250,^(BOOL ready){if(!ready||window.workflowFailure){done(window.workflowFailure?:WorkflowCheckError(@"Workflow confirmation did not appear."));return;}[window.window endSheet:window.window.attachedSheet returnCode:response];WorkflowCheckPoll(^BOOL{return !window.saving&&!window.window.attachedSheet;},250,^(BOOL closed){done(closed?nil:WorkflowCheckError(@"Workflow confirmation did not finish."));});});
}
static CGFloat WorkflowCheckInset(SINWindowController *window){CGFloat inset=0;for(SINNavigator *pane in @[window.navigator,window.contentsNavigator])if(!pane.view.hidden)inset=MAX(inset,NSMaxX(pane.view.frame)+window.split.dividerThickness);return inset;}
static id WorkflowCheckItem(NSOutlineView *outline,NSString *path){for(NSInteger row=0;row<outline.numberOfRows;row++){id item=[outline itemAtRow:row];if([item isKindOfClass:NSString.class]&&SINPathsReferToSameFile(item,path))return item;}return nil;}
static void WorkflowCheckLayout(SINWindowController *window,NSUInteger remaining,void(^done)(NSError *)){
    [window.window.contentView layoutSubtreeIfNeeded];[window.editor evaluate:@"(()=>{const d=document.querySelector('#document').getBoundingClientRect(),t=document.querySelector('#toolbar').getBoundingClientRect();return {left:d.left,width:d.width,toolbarLeft:t.left,toolbarWidth:t.width};})()" completion:^(id value,NSError *error){
        if(error){done(error);return;}CGFloat scale=window.editor.webView.pageZoom,inset=WorkflowCheckInset(window),width=window.editor.view.bounds.size.width;
        if([value isKindOfClass:NSDictionary.class]&&fabs([value[@"left"] doubleValue]*scale-inset)<1.5&&fabs([value[@"width"] doubleValue]*scale-(width-inset))<1.5&&fabs([value[@"toolbarLeft"] doubleValue]*scale)<1.5&&fabs([value[@"toolbarWidth"] doubleValue]*scale-width)<1.5){done(nil);return;}
        if(!remaining){done(WorkflowCheckError([NSString stringWithFormat:@"Contents/navigation layout did not settle (inset %.1f, width %.1f, metrics %@)",inset,width,value]));return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WorkflowCheckLayout(window,remaining-1,done);});
    }];
}

@implementation SINWindowController (DocumentWorkflowSelfTest)
- (void)runDocumentWorkflowChecks:(void (^)(NSArray<NSString *> *,NSError *))completion {
    if(!self.testMode){completion(@[],WorkflowCheckError(@"Workflow tests require an isolated test window."));return;}
    NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
    NSString *directory=[self.store.directory stringByAppendingPathComponent:[@"DocumentWorkflows-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    SINStore *store=[[SINStore alloc] initWithDirectory:directory error:&error];if(!store){completion(@[],error);return;}
    SINDocument *first=SINDocument.new,*second=SINDocument.new;first.draftName=@"2026-10-21 1045 - Prompt 9.html";first.text=@"<!doctype html><html><body><h1 data-sin-style='title'>A title / for saving</h1><p>FIRST LIVE SENTINEL</p></body></html>";second.text=@"<!doctype html><html><body><p>SECOND SAVED SENTINEL</p></body></html>";
    NSString *secondPath=[directory stringByAppendingPathComponent:@"Second.html"];
    if(![second saveToPath:secondPath overwriteConflict:NO error:&error]){completion(@[],error);return;}
    SINWorkflowCheckWindow *scratch=[[SINWorkflowCheckWindow alloc] initWithStore:store documents:@[first] activeIdentifier:first.identifier];scratch.testMode=YES;[scratch.timer invalidate];
    SINWorkflowCheckWindow *peer=[[SINWorkflowCheckWindow alloc] initWithStore:store documents:@[second] activeIdentifier:second.identifier];peer.testMode=YES;[peer.timer invalidate];
    SINAppDelegate *delegate=(SINAppDelegate *)NSApp.delegate;[delegate.windows addObject:scratch];[delegate.windows addObject:peer];
    [scratch.window orderWindow:NSWindowBelow relativeTo:self.window.windowNumber];[peer.window orderWindow:NSWindowBelow relativeTo:scratch.window.windowNumber];
    NSMutableArray *checks=NSMutableArray.new;__block BOOL finished=NO;__block SINDocument *combined=nil;
    BOOL(^check)(BOOL,NSString *,NSError **)=^BOOL(BOOL passed,NSString *label,NSError **failure){if(passed){[checks addObject:label];return YES;}if(failure&&!*failure)*failure=WorkflowCheckError(label);return NO;};
    void(^finish)(NSError *)=^(NSError *failure){if(finished)return;finished=YES;for(SINWorkflowCheckWindow *window in @[scratch,peer]){if(window.window.attachedSheet)[window.window endSheet:window.window.attachedSheet returnCode:NSModalResponseCancel];window.closing=YES;[window.timer invalidate];for(SINEditor *editor in window.editors.allValues)[editor invalidate];[window.window close];[delegate.windows removeObject:window];}[fm removeItemAtPath:directory error:NULL];completion(checks,failure?:scratch.workflowFailure?:peer.workflowFailure);};
    NSArray *steps=@[
        ^(void(^next)(NSError *)){NSError *failure=nil;NSSegmentedControl *main=[scratch.navigator valueForKey:@"modeControl"],*contents=[scratch.contentsNavigator valueForKey:@"modeControl"];if(!check(main.segmentCount==2&&main.selectedSegment>=0&&main.selectedSegment<2&&scratch.contentsNavigator.mode==2&&contents.selectedSegment==-1,@"Independent Contents navigator initializes without selecting a nonexistent segment",&failure)){next(failure);return;}WorkflowCheckReady(scratch.editor,^(NSError *failure){if(failure){next(failure);return;}WorkflowCheckReady(peer.editor,next);});},
        ^(void(^next)(NSError *)){
            [scratch handleCommand:@"contentView"];WorkflowCheckPoll(^BOOL{return scratch.contentsNavigator.headings.count>0;},200,^(BOOL populated){
                NSError *failure=nil;if(!check(populated&&!scratch.navigator.view.hidden&&!scratch.contentsNavigator.view.hidden&&scratch.contentsNavigator.view.frame.size.width>100&&NSMinX(scratch.contentsNavigator.view.frame)>=NSMaxX(scratch.navigator.view.frame)&&[scratch.contentsNavigator.headings.firstObject[@"text"] containsString:@"A title / for saving"],@"Contents and navigation remain visible together and display real editor headings",&failure)){next(failure);return;}
                WorkflowCheckLayout(scratch,150,^(NSError *layoutError){if(layoutError){next(layoutError);return;}[checks addObject:@"Visual document begins after both native panes beneath the full-width ribbon"];
                    [scratch handleCommand:@"documentList"];WorkflowCheckLayout(scratch,150,^(NSError *hiddenError){NSError *failure=hiddenError;if(!check(!hiddenError&&scratch.navigator.view.hidden&&!scratch.contentsNavigator.view.hidden&&WorkflowCheckInset(scratch)>100,@"Hiding navigation keeps Contents and updates the document inset",&failure)){next(failure);return;}
                        [scratch.editor showSource:YES completion:^{NSScrollView *scroll=scratch.editor.sourceView.enclosingScrollView;NSRect source=[scroll convertRect:scroll.bounds toView:scratch.editor.view];NSError *failure=nil;if(!check(scratch.editor.showingSource&&!scroll.hidden&&fabs(source.origin.x-WorkflowCheckInset(scratch))<1.5&&fabs(NSMaxX(source)-scratch.editor.view.bounds.size.width)<1.5,@"HTML Source uses the independent Contents pane inset",&failure)){next(failure);return;}
                            [scratch.editor showSource:NO completion:^{[scratch handleCommand:@"documentList"];[scratch handleCommand:@"contentView"];WorkflowCheckLayout(scratch,150,next);}];
                        }];
                    });
                });
            });
        },
        ^(void(^next)(NSError *)){
            scratch.navigator.directory=directory;[scratch resolveFirstSave:first completion:^(NSString *name,NSString *path){NSError *failure=nil;check([name isEqual:@"2026-10-21 1045 - A title - for saving.html"]&&[path.lastPathComponent isEqual:name]&&SINPathsReferToSameFile(path.stringByDeletingLastPathComponent,directory),@"First save derives a safe title while preserving the draft timestamp",&failure);next(failure);}];
        },
        ^(void(^next)(NSError *)){
            [scratch saveDocument:first saveAs:NO completion:^(BOOL saved){NSError *failure=nil;if(!check(saved&&first.path&&[fm fileExistsAtPath:first.path]&&[first.text containsString:@"FIRST LIVE SENTINEL"],@"Title-based first save writes the editable document without a Save panel",&failure)){next(failure);return;}
                NSString *savedHTML=first.savedText;first.text=[first.text stringByAppendingString:@"<!-- pending rename -->"];NSString *pending=first.text;NSString *old=first.path;first.emoji=@"🧪";[store rememberDocumentEmoji:first oldPath:nil];
                BOOL renamed=[first renameToFilename:@"Renamed title" error:&failure];[store rememberDocumentEmoji:first oldPath:old];
                if(!check(renamed&&[first.name isEqual:@"Renamed title.html"]&&[first.text isEqual:pending]&&[first.savedText isEqual:savedHTML],@"Saved rename adds .html while preserving pending and saved snapshots",&failure)){next(failure);return;}
                SINDocument *draft=SINDocument.new;BOOL draftRenamed=[draft renameToFilename:@"Draft title" error:&failure];SINDocument *restored=[SINDocument documentFromDictionary:first.dictionaryRepresentation];
                check(draftRenamed&&[draft.name isEqual:@"Draft title.html"]&&[restored.emoji isEqual:@"🧪"]&&[store.settings[@"documentEmojis"][first.path] isEqual:@"🧪"]&&!store.settings[@"documentEmojis"][old],@"Draft extension and emoji recovery/path remapping persist",&failure);[scratch.editor reload];next(failure);
            }];
        },
        ^(void(^next)(NSError *)){
            NSError *failure=nil;NSString *source=[directory stringByAppendingPathComponent:@"Import Source"];[fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:&failure];NSString *markdown=[source stringByAppendingPathComponent:@"Example.md"];
            [@"# Markdown title\n\n[relative link](next.html)\n\n![picture](image.png)" writeToFile:markdown atomically:YES encoding:NSUTF8StringEncoding error:&failure];if(failure){next(failure);return;}
            [scratch importMarkdown:markdown completion:^(SINDocument *doc,NSError *importError){NSError *result=importError;if(!check(doc&&[doc.name isEqual:@"Example - Converted.html"]&&[doc.path.stringByDeletingLastPathComponent isEqual:[directory stringByAppendingPathComponent:@"Markdown Imports"]]&&[doc.text containsString:@"<h1>Markdown title</h1>"]&&[doc.text containsString:@"Import%20Source/next.html"]&&[doc.text containsString:@"Import%20Source/image.png"]&&doc.autosave,@"Markdown import creates a full editable internal HTML document with rebased links and images",&result)){next(result);return;}
                [scratch importMarkdown:markdown completion:^(SINDocument *copy,NSError *secondError){NSError *result=secondError;check(copy&&[copy.name isEqual:@"Example - Converted (2).html"]&&[fm fileExistsAtPath:doc.path],@"Repeated Markdown imports number copies and retain the first conversion",&result);next(result);}];
            }];
        },
        ^(void(^next)(NSError *)){
            NSError *failure=nil;SINDocument *hidden=SINDocument.new;hidden.privateDocument=YES;hidden.draftName=@"Hidden secret.html";[scratch.documents addObject:hidden];scratch.navigator.mode=1;scratch.navigator.multiSelection=YES;
            NSMutableArray *selected=[scratch.navigator valueForKey:@"documentSelection"];[selected addObject:first];[selected addObject:hidden];scratch.navigator.filterText=@"Renamed";[scratch refresh];
            if(!check(scratch.navigator.outline.numberOfRows==1&&[scratch.navigator.checkedItems isEqual:@[first,hidden]]&&scratch.documents.count==2,@"Filename filtering changes only navigation and preserves ordered checked selection",&failure)){next(failure);return;}
            scratch.navigator.mode=0;NSMenu *tab=[scratch documentContextMenu:first];if(!check([tab itemWithTitle:@"Combine Selected Documents…"]&&[tab itemWithTitle:@"Delete…"]&&[[scratch.navigator selectionIncludingItem:first] isEqual:@[first,hidden]],@"Checked document tabs retain Combine while Explorer is visible and Delete still targets one tab",&failure)){next(failure);return;}scratch.navigator.mode=1;[selected removeObject:hidden];if(!check([[scratch documentContextMenu:first documentList:YES] itemWithTitle:@"Delete Selected Files…"]!=nil,@"One checked document uses the selected-files deletion action",&failure)){next(failure);return;}[selected addObject:hidden];
            store.settings[@"showPrivateDocuments"]=@NO;[scratch refreshPrivacy];second.privateDocument=YES;[peer refreshPrivacy];
            if(!check(![scratch.visibleDocuments containsObject:hidden]&&!scratch.navigator.checkedItems.count&&![peer.visibleDocuments containsObject:second],@"Privacy removes private entries and clears selection in each window",&failure)){next(failure);return;}
            WorkflowCheckPoll(^BOOL{return peer.active!=second;},200,^(BOOL changed){NSError *failure=nil;if(!changed){next(WorkflowCheckError(@"Hiding the active private document did not activate a visible draft."));return;}
                NSString *alias=[directory stringByAppendingPathComponent:@"Explorer alias"];if(![fm createSymbolicLinkAtPath:alias withDestinationPath:directory error:&failure]){next(failure);return;}peer.navigator.mode=0;peer.navigator.directory=alias;[peer.navigator refresh];if(!check(!WorkflowCheckItem(peer.navigator.outline,second.path)&&WorkflowCheckItem(peer.navigator.outline,first.path),@"Private Explorer documents stay hidden through symlink aliases while public files remain visible",&failure)){NSMutableArray *rows=NSMutableArray.new;for(NSInteger row=0;row<peer.navigator.outline.numberOfRows;row++)[rows addObject:[peer.navigator.outline itemAtRow:row]];next(WorkflowCheckError([NSString stringWithFormat:@"%@ (private %@, public %@, hidden %@, rows %@)",failure.localizedDescription,second.path,first.path,peer.navigator.hiddenPaths,rows]));return;}
                store.settings[@"showPrivateDocuments"]=@YES;[scratch refreshPrivacy];[peer refreshPrivacy];scratch.navigator.filterText=@"";
                hidden.modifiedDate=[NSDate dateWithTimeIntervalSince1970:10];first.modifiedDate=[NSDate dateWithTimeIntervalSince1970:20];hidden.pinned=YES;store.settings[@"documentSort"]=@"newest";[scratch sortDocuments];BOOL pinned=scratch.documents.firstObject==hidden;hidden.pinned=NO;[scratch sortDocuments];
                check(pinned&&scratch.documents.firstObject==first&&scratch.visibleDocuments.count==2,@"Automatic sorting keeps pinned prompts first and then orders by modification time",&failure);next(failure);
            });
        },
        ^(void(^next)(NSError *)){
            NSError *failure=nil;NSString *html=[directory stringByAppendingPathComponent:@"Navigation.html"],*folder=html.stringByDeletingPathExtension,*image=[folder stringByAppendingPathComponent:@"Nested-picture.png"];
            [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&failure];[@"<html><body><img src='Navigation/Nested-picture.png'></body></html>" writeToFile:html atomically:YES encoding:NSUTF8StringEncoding error:&failure];[@"filter fixture" writeToFile:image atomically:YES encoding:NSUTF8StringEncoding error:&failure];if(failure){next(failure);return;}
            scratch.navigator.mode=0;scratch.navigator.directory=directory;scratch.navigator.filterText=@"";scratch.navigator.showFolders=NO;[scratch.navigator refresh];id htmlItem=WorkflowCheckItem(scratch.navigator.outline,html);if(htmlItem)[scratch.navigator.outline expandItem:htmlItem];id folderItem=WorkflowCheckItem(scratch.navigator.outline,folder);if(folderItem)[scratch.navigator.outline expandItem:folderItem];
            if(!check(folderItem&&SINPathsReferToSameFile([scratch.navigator.outline parentForItem:folderItem],html)&&WorkflowCheckItem(scratch.navigator.outline,image),@"Explorer nests and expands the companion image folder beneath its HTML even with ordinary folders hidden",&failure)){NSMutableArray *rows=NSMutableArray.new;for(NSInteger row=0;row<scratch.navigator.outline.numberOfRows;row++){id item=[scratch.navigator.outline itemAtRow:row];[rows addObject:@{@"item":[item description],@"parent":[[scratch.navigator.outline parentForItem:item] description]?:@"",@"expanded":@([scratch.navigator.outline isItemExpanded:item])}];}next(WorkflowCheckError([NSString stringWithFormat:@"%@ (HTML %@, folder %@, rows %@)",failure.localizedDescription,htmlItem,folderItem,rows]));return;}
            scratch.navigator.filterText=@"Nested-picture";[scratch.navigator refresh];if(!check(WorkflowCheckItem(scratch.navigator.outline,html)&&WorkflowCheckItem(scratch.navigator.outline,folder)&&WorkflowCheckItem(scratch.navigator.outline,image),@"Explorer filename filter retains loaded ancestors of a nested matching image",&failure)){next(failure);return;}
            scratch.navigator.filterText=@"Navigation.html";[scratch.navigator refresh];NSSearchField *input=[scratch.navigator valueForKey:@"filterInput"];input.stringValue=@"Navigation.html";BOOL descendants=WorkflowCheckItem(scratch.navigator.outline,image)!=nil;BOOL handled=[scratch.navigator control:input textView:NSTextView.new doCommandBySelector:@selector(cancelOperation:)];
            check(descendants&&handled&&!scratch.navigator.filterText.length&&!input.stringValue.length,@"A matching Explorer ancestor retains its descendants and Escape clears the filename filter",&failure);scratch.navigator.mode=1;next(failure);
        },
        ^(void(^next)(NSError *)){
            [scratch ensureBundledDocuments];NSError *failure=scratch.workflowFailure;NSString *name=@"AI Prompt - Output Formatting.html";SINDocument *reference=nil;for(SINDocument *doc in scratch.documents)if([doc.name isEqual:name])reference=doc;
            if(!check(reference&&reference.pinned&&[fm fileExistsAtPath:reference.path],@"Startup publishes pinned bundled reference working copies",&failure)){next(failure);return;}
            NSString *original=[NSString stringWithContentsOfFile:reference.path encoding:NSUTF8StringEncoding error:&failure];reference.text=@"Recovered unsaved reference sentinel";NSString *fingerprint=reference.fingerprint;[fm removeItemAtPath:reference.path error:&failure];[scratch ensureBundledDocuments];
            if(!check([reference.text isEqual:@"Recovered unsaved reference sentinel"]&&[reference.fingerprint isEqual:fingerprint]&&[[NSString stringWithContentsOfFile:reference.path encoding:NSUTF8StringEncoding error:NULL] isEqual:original],@"Bundled restore recreates a missing disk copy while preserving recovery text and fingerprint",&failure)){next(failure);return;}
            [@"User-owned reference version" writeToFile:reference.path atomically:YES encoding:NSUTF8StringEncoding error:&failure];[scratch ensureBundledDocuments];check([[NSString stringWithContentsOfFile:reference.path encoding:NSUTF8StringEncoding error:NULL] isEqual:@"User-owned reference version"],@"Bundled startup never overwrites an existing user-owned reference",&failure);next(failure);
        },
        ^(void(^next)(NSError *)){
            [peer activate:second];WorkflowCheckPoll(^BOOL{return peer.active==second;},200,^(BOOL active){if(!active){next(WorkflowCheckError(@"Peer document activation timed out."));return;}
                [peer.editor showSource:YES completion:^{peer.editor.sourceView.string=@"<!doctype html><html><body><p>OTHER WINDOW DIRTY SENTINEL</p></body></html>";[peer.editor textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:peer.editor.sourceView]];
                    NSError *setup=nil;SINDocument *closed=SINDocument.new;closed.text=@"<html><body><p>CLOSED EMOJI SENTINEL</p></body></html>";closed.emoji=@"⭐";if(![closed saveToPath:[directory stringByAppendingPathComponent:@"Closed emoji.html"] overwriteConflict:NO error:&setup]){next(setup);return;}[store rememberDocumentEmoji:closed oldPath:nil];NSArray *before=scratch.documents.copy;scratch.navigator.mode=0;scratch.navigator.directory=directory;[scratch combineItems:@[first,secondPath,closed.path]];
                    WorkflowCheckPoll(^BOOL{return scratch.workflowFailure||(!scratch.saving&&![before containsObject:scratch.active]);},350,^(BOOL ready){NSError *failure=scratch.workflowFailure;combined=scratch.active;check(ready&&combined&&[combined.text containsString:@"FIRST LIVE SENTINEL"]&&[combined.text containsString:@"OTHER WINDOW DIRTY SENTINEL"]&&![[NSString stringWithContentsOfFile:secondPath encoding:NSUTF8StringEncoding error:NULL] containsString:@"OTHER WINDOW DIRTY SENTINEL"]&&[first.emoji isEqual:@"🧪"]&&[second.emoji isEqual:@"❌"]&&[store.settings[@"documentEmojis"][closed.path] isEqual:@"⭐"],@"Combine preserves live snapshots across windows, source disk bytes and existing open/closed emoji labels",&failure);next(failure);});
                }];
            });
        },
        ^(void(^next)(NSError *)){
            scratch.navigator.mode=1;scratch.navigator.multiSelection=YES;NSMutableArray *selected=[scratch.navigator valueForKey:@"documentSelection"];[selected addObject:combined];[selected addObject:first];[scratch deleteItems:@[combined,first]];
            WorkflowCheckSheet(scratch,NSAlertSecondButtonReturn,^(NSError *failure){check([scratch.navigator.checkedItems isEqual:@[combined,first]]&&[fm fileExistsAtPath:combined.path],@"Cancel batch delete preserves every checked document and file",&failure);next(failure);});
        },
        ^(void(^next)(NSError *)){
            NSString *missing=[directory stringByAppendingPathComponent:@"Missing batch fixture.html"];[scratch deleteItems:@[missing,first]];
            WorkflowCheckSheet(scratch,NSAlertFirstButtonReturn,^(NSError *failure){BOOL reported=scratch.workflowFailure!=nil;scratch.workflowFailure=nil;check(reported&&[scratch.navigator.checkedItems isEqual:@[combined,first]]&&[fm fileExistsAtPath:first.path],@"Failed batch delete preserves unprocessed checked documents and their disk files",&failure);next(failure);});
        },
        ^(void(^next)(NSError *)){
            SINDocument *draft=SINDocument.new;draft.text=@"Disposable unsaved draft";[scratch.documents addObject:draft];NSString *path=combined.path;[scratch deleteItems:@[combined,draft]];
            WorkflowCheckSheet(scratch,NSAlertFirstButtonReturn,^(NSError *failure){check(![fm fileExistsAtPath:path]&&![scratch.documents containsObject:combined]&&![scratch.documents containsObject:draft]&&[scratch.navigator.checkedItems isEqual:@[first]],@"Confirmed batch delete trashes saved files, removes their open tabs, closes drafts and keeps unrelated checks",&failure);next(failure);});
        }
    ];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!finished)finish(WorkflowCheckError(@"Document workflow checks timed out."));});
    WorkflowCheckSteps(steps,0,^BOOL{return finished;},finish);
}
@end
