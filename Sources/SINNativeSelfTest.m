#import "SINWindowController.h"
#import "SINNativeServices.h"
#import "SINSearchPanel.h"
#import "SINAppDelegate.h"

@interface SINWindowController (ContextMenuSelfTest)
- (void)runNativeContextMenuChecks:(void (^)(NSArray<NSString *> *,NSError *))completion;
@end

static NSError *NativeCheckError(NSString *message) { return [NSError errorWithDomain:@"SinNativeSelfTest" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static void LoadedEditor(SINEditor *editor, void (^done)(NSError *)) {
    if(!editor){done(NativeCheckError(@"The active native editor was not created."));return;}
    __weak SINEditor *weakEditor=editor;
    void (^start)(void)=^{ [weakEditor asyncScript:@"await window.editor.ready();return true;" completion:^(id result,NSError *error) { done(error); }]; };
    if (editor.ready) { start(); return; }
    void (^previous)(void)=editor.readyHandler;
    editor.readyHandler=^{ weakEditor.readyHandler=previous; if(previous)previous(); start(); };
}
static void NativeSteps(NSArray<void (^)(void (^)(NSError *))> *steps, NSUInteger index, void (^done)(NSError *)) {
    if(index==steps.count){done(nil);return;}
    NSLog(@"Native integration stage %lu/%lu",(unsigned long)index+1,(unsigned long)steps.count);
    steps[index](^(NSError *error){if(error)done(error);else NativeSteps(steps,index+1,done);});
}
static void PollNativeCheck(BOOL (^ready)(void), NSUInteger attempts, void (^done)(BOOL)) {
    if(ready()){done(YES);return;}
    if(!attempts){done(NO);return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{PollNativeCheck(ready,attempts-1,done);});
}
// Browser geometry arrives through ResizeObserver messages. Poll the real
// WKWebView rather than treating an asynchronous preference update as settled.
static void PollNativeLayout(SINWindowController *window, BOOL (^ready)(NSDictionary *), NSUInteger attempts, void (^done)(NSError *)) {
    [window.editor evaluate:@"(()=>{const t=document.querySelector('#toolbar').getBoundingClientRect(),d=document.querySelector('#document').getBoundingClientRect();return {toolbarLeft:t.left,toolbarWidth:t.width,toolbarHeight:t.height,documentLeft:d.left,documentTop:d.top,documentWidth:d.width};})()" completion:^(id value,NSError *error){
        if(error){done(error);return;}
        if([value isKindOfClass:NSDictionary.class]&&ready(value)){done(nil);return;}
        if(!attempts){done(NativeCheckError([NSString stringWithFormat:@"Native ribbon layout did not settle: %@",value]));return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{PollNativeLayout(window,ready,attempts-1,done);});
    }];
}
static BOOL NativeNear(CGFloat a,CGFloat b){return fabs(a-b)<1.5;}
static CGFloat NativeDocumentInset(SINWindowController *window){return window.navigator.view.hidden?0:NSMaxX(window.navigator.view.frame)+window.split.dividerThickness;}
static BOOL NativeVisualGeometryMatches(SINWindowController *window,NSDictionary *metrics){
    SINEditor *editor=window.editor;CGFloat scale=editor.webView.pageZoom,width=window.window.contentView.bounds.size.width,inset=NativeDocumentInset(window);
    NSRect host=[window.editorHost convertRect:window.editorHost.bounds toView:window.window.contentView];
    NSRect navigation=[window.navigator.view convertRect:window.navigator.view.bounds toView:window.window.contentView];
    return !editor.showingSource&&NativeNear(host.origin.x,0)&&NativeNear(host.size.width,width)&&NativeNear(editor.webView.bounds.size.width,width)
        &&NativeNear([metrics[@"toolbarLeft"] doubleValue]*scale,0)&&NativeNear([metrics[@"toolbarWidth"] doubleValue]*scale,width)
        &&NativeNear([metrics[@"documentLeft"] doubleValue]*scale,inset)&&NativeNear([metrics[@"documentWidth"] doubleValue]*scale,width-inset)
        &&NativeNear([metrics[@"toolbarHeight"] doubleValue]*scale,editor.ribbonHeight)
        &&(window.navigator.view.hidden||NativeNear(NSMaxY(navigation),NSMaxY(host)-editor.ribbonHeight));
}
static BOOL NativeHitBelongsTo(NSView *hit,NSView *owner){return hit==owner||[hit isDescendantOf:owner];}
static NSDictionary *NativeAssetSnapshot(NSString *folder,NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSArray<NSString *> *names=[fm contentsOfDirectoryAtPath:folder error:error];
    if(!names)return nil;
    NSMutableDictionary *snapshot=NSMutableDictionary.new;
    for(NSString *name in names){
        NSString *path=[folder stringByAppendingPathComponent:name];
        NSDictionary *attributes=[fm attributesOfItemAtPath:path error:error];
        if(!attributes)return nil;
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error];
        if(!data)return nil;
        snapshot[name]=@{@"data":data,@"fileNumber":attributes[NSFileSystemFileNumber]?:@0};
    }
    return snapshot;
}
@implementation SINWindowController (NativeSelfTest)
- (void)runNativeLayoutChecks:(void (^)(NSArray<NSString *> *,NSError *))completion {
    NSMutableArray<NSString *> *checks=NSMutableArray.new;
    SINEditor *editor=self.editor;NSInteger originalZoom=self.active.zoom;
    NSSize originalSize=self.window.contentView.bounds.size;CGFloat originalWidth=self.navigator.view.frame.size.width;
    BOOL originalNavigationHidden=self.navigator.view.hidden,originalTabsHidden=self.tabScroll.hidden;
    id originalWrap=self.store.settings[@"wrapToolbar"],originalToolbar=self.store.settings[@"showToolbar"];
    void (^finish)(NSError *)=^(NSError *error){
        self.active.zoom=originalZoom;self.store.settings[@"wrapToolbar"]=originalWrap?:@YES;self.store.settings[@"showToolbar"]=originalToolbar?:@YES;
        self.navigator.view.hidden=originalNavigationHidden;self.tabScroll.hidden=originalTabsHidden;
        [self.window setContentSize:originalSize];[self.split setPosition:originalWidth ofDividerAtIndex:0];[self layoutChrome];[editor applyPreferences];
        completion(checks,error);
    };
    void (^verify)(NSString *,void (^)(NSError *))=^(NSString *name,void (^next)(NSError *)){
        PollNativeLayout(self,^BOOL(NSDictionary *metrics){return NativeVisualGeometryMatches(self,metrics);},100,^(NSError *error){if(!error)[checks addObject:name];next(error);});
    };
    self.navigator.view.hidden=NO;self.store.settings[@"showToolbar"]=@YES;self.store.settings[@"wrapToolbar"]=@YES;
    self.active.zoom=100;[editor applyPreferences];[self.split setPosition:280 ofDividerAtIndex:0];[self layoutChrome];
    NSArray *steps=@[
        ^(void (^next)(NSError *)){
            [editor showSource:NO completion:^{LoadedEditor(editor,^(NSError *error){if(error){next(error);return;}verify(@"Native ribbon spans the entire content width while the document is inset beside navigation",next);});}];
        },
        ^(void (^next)(NSError *)){
            [self.split setPosition:380 ofDividerAtIndex:0];[self layoutChrome];
            verify(@"Resizing the native navigation divider changes only the document inset and keeps navigation below the full-width ribbon",next);
        },
        ^(void (^next)(NSError *)){
            [self handleCommand:@"documentList"];
            verify(@"Hiding native navigation expands the document to full width without narrowing the ribbon",next);
        },
        ^(void (^next)(NSError *)){
            [self handleCommand:@"documentList"];
            verify(@"Showing native navigation restores the document inset beneath the full-width ribbon",next);
        },
        ^(void (^next)(NSError *)){
            [editor showSource:YES completion:^{
                PollNativeCheck(^BOOL{
                    NSScrollView *scroll=editor.sourceView.enclosingScrollView;NSRect frame=[scroll convertRect:scroll.bounds toView:editor.view];
                    return editor.showingSource&&!scroll.hidden&&NativeNear(frame.origin.x,NativeDocumentInset(self))&&NativeNear(NSMaxX(frame),editor.view.bounds.size.width);
                },100,^(BOOL ready){if(ready)[checks addObject:@"Native HTML source stays beside navigation without covering the sidebar"];next(ready?nil:NativeCheckError(@"Native source overlaps navigation."));});
            }];
        },
        ^(void (^next)(NSError *)){
            [editor showSource:NO completion:^{LoadedEditor(editor,^(NSError *error){if(error){next(error);return;}verify(@"Returning from Source restores the full-width visual ribbon and inset document",next);});}];
        },
        ^(void (^next)(NSError *)){
            self.active.zoom=125;[editor applyPreferences];
            verify(@"Native navigation and document alignment stay correct at 125 percent WebKit zoom",next);
        },
        ^(void (^next)(NSError *)){
            self.active.zoom=100;[editor applyPreferences];[self.window setContentSize:NSMakeSize(900,720)];[self layoutChrome];
            verify(@"A narrower window wraps the full-width ribbon and moves navigation below its measured height",next);
        },
        ^(void (^next)(NSError *)){
            [self.window setContentSize:originalSize];[self layoutChrome];
            verify(@"Growing the native window restores ribbon and document geometry",^(NSError *error){
                if(!error && !NativeNear(self.navigator.view.frame.size.width,380))error=NativeCheckError(@"Window resizing changed the chosen navigation width.");
                next(error);
            });
        },
        ^(void (^next)(NSError *)){
            [self.split setPosition:640 ofDividerAtIndex:0];[self layoutChrome];
            [editor evaluate:@"document.querySelector('#fontColorOptions').click();(()=>{const r=document.querySelector('.color-palette:popover-open').getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};})()" completion:^(id value,NSError *error){
                if(error||![value isKindOfClass:NSDictionary.class]){next(error?:NativeCheckError(@"Font Color palette did not open."));return;}
                CGFloat scale=editor.webView.pageZoom,x=[value[@"x"] doubleValue]*scale,y=[value[@"y"] doubleValue]*scale,w=[value[@"width"] doubleValue]*scale,h=[value[@"height"] doubleValue]*scale;
                NSRect popup=NSMakeRect(x,editor.webView.isFlipped?y:editor.webView.bounds.size.height-y-h,w,h);
                NSRect popupInContent=[editor.webView convertRect:popup toView:self.window.contentView];
                NSRect navInContent=[self.navigator.view convertRect:self.navigator.view.bounds toView:self.window.contentView];
                NSRect overlap=NSIntersectionRect(popupInContent,navInContent);
                if(NSIsEmptyRect(overlap)){next(NativeCheckError([NSString stringWithFormat:@"Font Color palette did not overlap the expanded sidebar for testing (popup %@, navigation %@).",NSStringFromRect(popupInContent),NSStringFromRect(navInContent)]));return;}
                NSPoint center=NSMakePoint(NSMidX(overlap),NSMidY(overlap));
                PollNativeCheck(^BOOL{return editor.overlayRects.count>0&&NativeHitBelongsTo([self.window.contentView hitTest:center],editor.webView);},100,^(BOOL ready){
                    if(ready)[checks addObject:@"The real Font Color popover receives pointer events where it overlaps native navigation"];
                    next(ready?nil:NativeCheckError(@"Native navigation intercepts the Font Color popover."));
                });
            }];
        },
        ^(void (^next)(NSError *)){
            [editor evaluate:@"document.querySelector('.color-palette:popover-open').hidePopover();void 0" completion:^(id result,NSError *error){
                if(error){next(error);return;}
                PollNativeCheck(^BOOL{return editor.overlayRects.count==0;},100,^(BOOL ready){
                    if(ready)[checks addObject:@"Closing the Font Color popover removes its native sidebar exclusion"];
                    [self.split setPosition:380 ofDividerAtIndex:0];[self layoutChrome];next(ready?nil:NativeCheckError(@"Native popover exclusion did not clear."));
                });
            }];
        },
        ^(void (^next)(NSError *)){
            [editor evaluate:@"document.querySelector('#link').click();void 0" completion:^(id result,NSError *error){
                if(error){next(error);return;}
                PollNativeCheck(^BOOL{
                    NSPoint center=[self.navigator.view convertPoint:NSMakePoint(20,20) toView:self.window.contentView];
                    NSView *hit=[self.window.contentView hitTest:center];
                    return editor.modalOverlay&&NativeHitBelongsTo(hit,editor.webView);
                },100,^(BOOL ready){
                    NSError *error=ready?nil:NativeCheckError(@"Native navigation intercepts the Insert Link modal overlay.");
                    if(ready)[checks addObject:@"The native sidebar yields pointer events to a real WebKit Insert Link modal"];next(error);
                });
            }];
        },
        ^(void (^next)(NSError *)){
            [editor evaluate:@"document.querySelector('dialog[open] button[value=cancel]').click();void 0" completion:^(id result,NSError *error){
                if(error){next(error);return;}
                PollNativeCheck(^BOOL{
                    NSPoint center=[self.navigator.view convertPoint:NSMakePoint(20,20) toView:self.window.contentView];
                    NSView *hit=[self.window.contentView hitTest:center];
                    return !editor.modalOverlay&&NativeHitBelongsTo(hit,self.navigator.view);
                },100,^(BOOL ready){if(ready)[checks addObject:@"Closing the WebKit modal restores native sidebar pointer events"];next(ready?nil:NativeCheckError(@"Native navigation remains blocked after the modal closes."));});
            }];
        }
    ];
    NativeSteps(steps,0,finish);
}
- (void)runNativeShellChecks:(void (^)(NSArray<NSString *> *,NSError *))completion {
    if(!self.testMode){completion(@[],NativeCheckError(@"Native shell checks require an isolated --self-test profile."));return;}
    NSString *directory=[self.store.directory stringByAppendingPathComponent:[@"NativeShell-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *setupError=nil;SINStore *store=[[SINStore alloc] initWithDirectory:directory error:&setupError];
    if(!store){completion(@[],setupError);return;}
    SINDocument *first=[store newDocument:&setupError],*second=[store newDocument:&setupError];
    first.text=@"<!doctype html><html><head><title>Native source test</title></head><body><p>Native Alpha</p></body></html>";
    second.text=@"<!doctype html><html><head></head><body><p>Second document sentinel</p></body></html>";
    if(!first||!second||![first saveToPath:[directory stringByAppendingPathComponent:@"first.html"] overwriteConflict:NO error:&setupError]){completion(@[],setupError);return;}
    NSString *untouchedHTML=[first.text copy];
    NSData *untouchedBytes=[NSData dataWithContentsOfFile:first.path];
    SINWindowController *scratch=[[SINWindowController alloc] initWithStore:store documents:@[first,second] activeIdentifier:first.identifier];
    scratch.testMode=YES;[scratch.timer invalidate];
    [scratch.window orderWindow:NSWindowBelow relativeTo:self.window.windowNumber];
    NSMutableArray<NSString *> *checks=NSMutableArray.new;
    BOOL (^check)(BOOL,NSString *,NSError **)=^BOOL(BOOL passed,NSString *name,NSError **error){if(passed){[checks addObject:name];return YES;}if(error)*error=NativeCheckError(name);return NO;};
    __block SINWindowController *other=nil;
    __block SINWindowController *reopened=nil;
    __block SINWindowController *exportWindow=nil;
    __block NSString *firstBeforeSwitch=nil;
    __block BOOL finished=NO;
    SINAppDelegate *delegate=(SINAppDelegate *)NSApp.delegate;
    NSArray *originalWindows=delegate.windows.copy;
    void (^finish)(NSError *)=^(NSError *error){
        if(finished)return;finished=YES;
        delegate.windows=originalWindows.mutableCopy;
        scratch.closing=YES;other.closing=YES;reopened.closing=YES;exportWindow.closing=YES;
        [scratch.timer invalidate];[other.timer invalidate];[reopened.timer invalidate];[exportWindow.timer invalidate];
        [scratch.window close];[other.window close];[reopened.window close];[exportWindow.window close];
        for(SINEditor *editor in scratch.editors.allValues)[editor invalidate];
        for(SINEditor *editor in other.editors.allValues)[editor invalidate];
        for(SINEditor *editor in reopened.editors.allValues)[editor invalidate];
        for(SINEditor *editor in exportWindow.editors.allValues)[editor invalidate];
        [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
        completion(checks,error);
    };
    NSArray *steps=@[
        ^(void (^next)(NSError *)){
            NSError *error=nil;
            if(!check(scratch.documents.count==2&&scratch.editors.count==1,@"Native startup creates only the active editor for two documents",&error)){next(error);return;}
            LoadedEditor(scratch.editor,^(NSError *loadError){
                if(loadError){next(loadError);return;}
                [scratch.editor flush:^{
                    NSError *error=nil;
                    if(!check(!first.modified&&[first.text isEqual:untouchedHTML]&&[[first.text dataUsingEncoding:NSUTF8StringEncoding] isEqual:untouchedBytes]&&[[NSData dataWithContentsOfFile:first.path] isEqual:untouchedBytes],@"Flushing untouched Visual HTML preserves its clean state and exact original bytes",&error)){next(error);return;}
                    [scratch.editor showSource:YES completion:^{
                        NSError *error=nil;
                        check(!first.modified&&[scratch.editor.sourceView.string isEqual:untouchedHTML]&&[[scratch.editor.sourceView.string dataUsingEncoding:NSUTF8StringEncoding] isEqual:untouchedBytes]&&[[NSData dataWithContentsOfFile:first.path] isEqual:untouchedBytes],@"Switching untouched HTML to Source preserves its clean state and exact original bytes",&error);next(error);
                    }];
                }];
            });
        },
        ^(void (^next)(NSError *)){
            [scratch runNativeLayoutChecks:^(NSArray<NSString *> *layoutChecks,NSError *error){[checks addObjectsFromArray:layoutChecks];next(error);}];
        },
        ^(void (^next)(NSError *)){
            [scratch runNativeContextMenuChecks:^(NSArray<NSString *> *menuChecks,NSError *error){[checks addObjectsFromArray:menuChecks];next(error);}];
        },
        ^(void (^next)(NSError *)){
            [scratch.editor showSource:YES completion:^{
                NSError *error=nil;SINEditor *editor=scratch.editor;
                if(!check([editor.sourceView.string containsString:@"Native Alpha"],@"Native source view receives the complete visual document",&error)){next(error);return;}
                [editor.sourceView.undoManager removeAllActions];
                [editor.sourceView insertText:@"<!-- Native source edit -->" replacementRange:NSMakeRange(editor.sourceView.string.length,0)];
                NSRange selected=editor.sourceView.selectedRange;
                NSDate *modified=first.modifiedDate;editor.sourceView.selectedRange=NSMakeRange(1,0);
                if(!check([scratch.status.stringValue hasPrefix:@"Ln 1, Col 2"]&&[first.modifiedDate isEqual:modified],@"Source caret movement updates status without changing the document modification time",&error)){next(error);return;}
                editor.sourceView.selectedRange=selected;
                [scratch saveDocument:first saveAs:NO completion:^(BOOL saved){
                    NSError *error=nil;NSString *disk=[NSString stringWithContentsOfFile:first.path encoding:NSUTF8StringEncoding error:NULL];
                    if(!check(saved&&[disk containsString:@"Native source edit"],@"Native Save flushes source edits to the existing file",&error)||!check(NSEqualRanges(selected,editor.sourceView.selectedRange)&&editor.sourceView.undoManager.canUndo,@"Native Save preserves source caret and Undo history",&error)){next(error);return;}
                    [editor.sourceView.undoManager undo];
                    if(!check(![editor.sourceView.string containsString:@"Native source edit"],@"Native Undo still reverses the edit after saving",&error)){next(error);return;}
                    [editor showSource:NO completion:^{LoadedEditor(editor,^(NSError *loadError){
                        if(loadError){next(loadError);return;}
                        [editor asyncScript:@"return window.editor.html(true);" completion:^(id value,NSError *scriptError){NSError *e=scriptError;if(!e)check([value isKindOfClass:NSString.class]&&[value containsString:@"Native Alpha"]&&![value containsString:@"Native source edit"],@"Switching back to Visual reflects the undone source edit",&e);next(e);}];
                    });}];
                }];
            }];
        },
        ^(void (^next)(NSError *)){
            [scratch.editor flush:^{firstBeforeSwitch=first.text;[scratch activate:second];
                PollNativeCheck(^BOOL{return scratch.active==second;},200,^(BOOL activated){
                    if(!activated){next(NativeCheckError(@"Activating the second editor timed out."));return;}
                    LoadedEditor(scratch.editor,next);
                });
            }];
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;
            if(!check(scratch.editors.count==2&&scratch.active==second&&[first.text isEqual:firstBeforeSwitch],@"Lazy document switching retains the previous document buffer",&error)){next(error);return;}
            [scratch.editor asyncScript:@"return window.editor.html(true);" completion:^(id html,NSError *scriptError){NSError *e=scriptError;if(!e)check([html containsString:@"Second document sentinel"]&&![html containsString:@"Native Alpha"],@"Lazy document switching does not leak text between editors",&e);next(e);}];
        },
        ^(void (^next)(NSError *)){
            [scratch.editor showSource:YES completion:^{
                second.readOnly=YES;[scratch.editor applyPreferences];NSError *error=nil;
                if(!check(!scratch.editor.sourceView.editable,@"Read-only documents disable native source editing",&error)){next(error);return;}
                NSString *lockedText=scratch.editor.sourceView.string;
                [scratch.editor editCommand:@"insertText" value:@"MUST NOT INSERT"];
                if(!check([scratch.editor.sourceView.string isEqual:lockedText],@"Locked source rejects native insert commands as well as typing",&error)){next(error);return;}
                second.readOnly=NO;[scratch.editor applyPreferences];
                BOOL originalWrap=[store.settings[@"wordWrap"] boolValue];
                [scratch handleCommand:@"wordWrap"];
                BOOL wrapped=scratch.editor.sourceView.textContainer.widthTracksTextView;
                if(!check(wrapped!=originalWrap&&wrapped==[store.settings[@"wordWrap"] boolValue],@"Native View menu changes apply to the active editor immediately",&error)){next(error);return;}
                [scratch handleCommand:@"wordWrap"];
                NSString *preview=[directory stringByAppendingPathComponent:@"preview.txt"];
                [@"Preview outside document collection" writeToFile:preview atomically:YES encoding:NSUTF8StringEncoding error:&error];
                NSUInteger count=scratch.documents.count;SINDocument *active=scratch.active;
                [scratch showPreview:preview];
                if(!check(scratch.preview!=nil&&scratch.editor.view.hidden&&scratch.documents.count==count&&scratch.active==active,@"Native file preview covers document editing and stays outside open documents",&error)){next(error);return;}
                [scratch.preview removeFromSuperview];scratch.preview=nil;
                check(!scratch.editor.view.hidden,@"Returning from a file preview restores the active editor",&error);next(error);
            }];
        },
        ^(void (^next)(NSError *)){
            SINSearchPanel *search=[[SINSearchPanel alloc] initWithEditor:scratch.editor];(void)search.view;
            NSSearchField *field=[search valueForKey:@"queryField"];NSTextField *status=[search valueForKey:@"status"];
            field.stringValue=@"sentinel";[search findNext:NO];
            PollNativeCheck(^BOOL{return ![status.stringValue isEqual:@"Searching…"];},150,^(BOOL completed){
                NSError *error=nil;
                NSRange selection=scratch.editor.sourceView.selectedRange;
                NSString *selected=[scratch.editor.sourceView.string substringWithRange:selection];
                if(!check(completed&&[[search valueForKey:@"matches"] count]==1&&[selected isEqual:@"sentinel"],@"Native HTML search executes its worker and selects the matching source range",&error)){[search invalidate];next(error);return;}
                NSButton *regex=[search valueForKey:@"regex"];regex.state=NSControlStateValueOn;field.stringValue=@"[";[search findNext:NO];
                PollNativeCheck(^BOOL{return ![status.stringValue isEqual:@"Searching…"];},150,^(BOOL validCompleted){
                    NSError *regexError=nil;
                    if(!check(validCompleted&&[status.stringValue containsString:@"Invalid regular expression"],@"Native HTML search reports invalid regex without changing source",&regexError)){[search invalidate];next(regexError);return;}
                    NSString *original=scratch.editor.sourceView.string;
                    scratch.editor.sourceView.string=[[@"" stringByPaddingToLength:20000 withString:@"a" startingAtIndex:0] stringByAppendingString:@"!"];
                    field.stringValue=@"(a+)+$";NSDate *started=NSDate.date;[search findNext:NO];
                    PollNativeCheck(^BOOL{return ![status.stringValue isEqual:@"Searching…"];},150,^(BOOL timedOut){
                        NSError *timeoutError=nil;
                        // JavaScriptCore can reject excessive backtracking before
                        // our timeout; either bounded result is correct.
                        check(timedOut&&[[search valueForKey:@"matches"] count]==0&&-started.timeIntervalSinceNow<3,@"Native HTML search bounds catastrophic regex outside AppKit",&timeoutError);
                        scratch.editor.sourceView.string=original;[search invalidate];[scratch.editor flush:^{next(timeoutError);}];
                    });
                });
            });
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;
            NSBitmapImageRep *pixels=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:8 bitsPerPixel:32];
            memset(pixels.bitmapData,127,16);
            NSString *png=[[pixels representationUsingType:NSBitmapImageFileTypePNG properties:@{}] base64EncodedStringWithOptions:0];
            SINDocument *document=[store newDocument:&error];
            NSString *original=[NSString stringWithFormat:@"<!doctype html><html><head><title>Export regression</title></head><body><p>Export sentinel</p><img alt='Pixel' src='data:image/png;base64,%@'></body></html>",png];
            document.text=original;
            NSString *originalPath=[directory stringByAppendingPathComponent:@"export-original.html"];
            if(!document||![document saveToPath:originalPath overwriteConflict:NO error:&error]){next(error);return;}
            NSData *originalBytes=[NSData dataWithContentsOfFile:originalPath];
            exportWindow=[[SINWindowController alloc] initWithStore:store documents:@[document] activeIdentifier:document.identifier];
            exportWindow.testMode=YES;[exportWindow.timer invalidate];
            NSString *standalonePath=[directory stringByAppendingPathComponent:@"existing-standalone.html"];
            NSString *markdownPath=[directory stringByAppendingPathComponent:@"Markdown Output.md"];
            NSString *assetFolder=markdownPath.stringByDeletingPathExtension;
            if(![@"Old standalone export" writeToFile:standalonePath atomically:YES encoding:NSUTF8StringEncoding error:&error]||![@"Old Markdown export" writeToFile:markdownPath atomically:YES encoding:NSUTF8StringEncoding error:&error]){next(error);return;}
            LoadedEditor(exportWindow.editor,^(NSError *loadError){
                if(loadError){next(loadError);return;}
                [exportWindow exportDocument:NO toPath:standalonePath completion:^(NSError *exportError){
                    if(exportError){next(exportError);return;}
                    NSError *error=nil;
                    NSString *standalone=[NSString stringWithContentsOfFile:standalonePath encoding:NSUTF8StringEncoding error:&error];
                    if(!check(!error&&[standalone containsString:@"Export sentinel"]&&[standalone containsString:@"data:image/png;base64,"]&&![standalone containsString:@"Old standalone export"],@"Native Standalone export replaces a confirmed existing output with embedded images",&error)||!check(!document.modified&&[document.path isEqual:originalPath]&&[document.text isEqual:original]&&[[NSData dataWithContentsOfFile:originalPath] isEqual:originalBytes],@"Native Standalone export preserves the original document bytes and clean state",&error)){next(error);return;}
                    [exportWindow exportDocument:YES toPath:markdownPath completion:^(NSError *markdownError){
                        if(markdownError){next(markdownError);return;}
                        NSError *error=nil;
                        NSString *markdown=[NSString stringWithContentsOfFile:markdownPath encoding:NSUTF8StringEncoding error:&error];
                        NSDictionary *assets=NativeAssetSnapshot(assetFolder,&error);
                        NSString *imageName=assets.allKeys.firstObject;
                        NSBitmapImageRep *image=assets.count==1?[NSBitmapImageRep imageRepWithData:assets[imageName][@"data"]]:nil;
                        NSString *reference=[assetFolder.lastPathComponent stringByAppendingPathComponent:imageName?:@""];
                        if(!check(!error&&[markdown containsString:@"Export sentinel"]&&assets.count==1&&image.pixelsWide==2&&image.pixelsHigh==2&&[markdown.stringByRemovingPercentEncoding containsString:reference]&&![markdown containsString:@"Old Markdown export"],@"Native Markdown export writes PNGs into the final matching asset folder and links them",&error)||!check(![standalone containsString:@"SinAI-export-"]&&![markdown containsString:@"SinAI-export-"]&&![markdown containsString:@"sin-asset:"]&&![markdown containsString:@"file:"],@"Native exports contain no staging directory or internal image URLs",&error)){next(error);return;}
                        [exportWindow exportDocument:YES toPath:markdownPath completion:^(NSError *repeatError){
                            if(repeatError){next(repeatError);return;}
                            NSError *error=nil;
                            NSDictionary *repeatedAssets=NativeAssetSnapshot(assetFolder,&error);
                            NSString *repeatedMarkdown=[NSString stringWithContentsOfFile:markdownPath encoding:NSUTF8StringEncoding error:&error];
                            if(!check(!error&&[repeatedAssets isEqual:assets]&&[repeatedMarkdown isEqual:markdown],@"Repeated native Markdown export reuses the existing PNG file without duplicates",&error)||!check(!document.modified&&[document.path isEqual:originalPath]&&[document.text isEqual:original]&&[[NSData dataWithContentsOfFile:originalPath] isEqual:originalBytes],@"Native Markdown exports preserve the original document bytes and clean state",&error)){next(error);return;}
                            NSString *external=@"External change during export";
                            __block BOOL externalWritten=NO;
                            __block NSError *externalWriteError=nil;
                            [exportWindow exportDocument:NO toPath:standalonePath completion:^(NSError *conflictError){
                                if(externalWriteError){next(externalWriteError);return;}
                                NSError *error=nil;
                                NSString *current=[NSString stringWithContentsOfFile:standalonePath encoding:NSUTF8StringEncoding error:&error];
                                check(externalWritten&&conflictError&&!error&&[current isEqual:external],@"Native export detects a concurrent destination edit and preserves the external bytes",&error);next(error);
                            }];
                            externalWritten=[external writeToFile:standalonePath atomically:YES encoding:NSUTF8StringEncoding error:&externalWriteError];
                        }];
                    }];
                }];
            });
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;SINDocument *copy=[SINDocument openPath:first.path error:&error];
            if(!copy){next(error);return;}
            other=[[SINWindowController alloc] initWithStore:store documents:@[copy] activeIdentifier:copy.identifier];other.testMode=YES;[other.timer invalidate];
            copy.text=[copy.text stringByAppendingString:@"<!-- Other window edit -->"];
            NSString *external=@"<!doctype html><html><body>External version</body></html>";
            if(![external writeToFile:first.path atomically:YES encoding:NSUTF8StringEncoding error:&error]){next(error);return;}
            BOOL saved=[copy saveToPath:copy.path overwriteConflict:NO error:&error];
            if(!check(!saved&&error.code==SINErrorConflict&&[copy.text containsString:@"Other window edit"],@"A second window cannot silently overwrite an externally changed shared file",&error)){next(error);return;}
            // Exercise the real window aggregation path with only the isolated
            // test windows registered in the app delegate.
            delegate.windows=[NSMutableArray arrayWithObjects:scratch,other,nil];scratch.testMode=NO;[scratch persist];scratch.testMode=YES;
            error=nil;SINStore *restored=[[SINStore alloc] initWithDirectory:directory error:&error];NSArray<SINDocument*> *documents=[restored restoreDocuments:&error];
            NSSet *identifiers=[NSSet setWithArray:[documents valueForKey:@"identifier"]];
            if(!check(!error&&documents.count==3&&[identifiers containsObject:first.identifier]&&[identifiers containsObject:second.identifier]&&[identifiers containsObject:copy.identifier],@"Real native persistence recovers the union of documents from both windows",&error)){next(error);return;}
            if(!check([restored.settings[@"sessionWindows"] count]==2,@"Session recovery records both native window groups",&error)){next(error);return;}
            SINDocument *newOwner=[SINDocument documentFromDictionary:first.dictionaryRepresentation];newOwner.text=@"Reopened owner has the newest unsaved text";
            reopened=[[SINWindowController alloc] initWithStore:store documents:@[newOwner] activeIdentifier:newOwner.identifier];reopened.testMode=YES;[reopened.timer invalidate];
            scratch.closing=YES;
            delegate.windows=[NSMutableArray arrayWithObjects:scratch,other,reopened,nil];reopened.testMode=NO;[reopened persist];reopened.testMode=YES;
            SINStore *newRestore=[[SINStore alloc] initWithDirectory:directory error:&error];NSArray<SINDocument *> *newDocuments=[newRestore restoreDocuments:&error];
            SINDocument *winning=nil;for(SINDocument *document in newDocuments)if([document.identifier isEqual:newOwner.identifier])winning=document;
            check([winning.text isEqual:newOwner.text],@"Reopened document edits win over an older closed controller during recovery",&error);next(error);
        }
    ];
    NativeSteps(steps,0,finish);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!finished)finish(NativeCheckError(@"Native shell integration checks timed out."));});
}
@end
