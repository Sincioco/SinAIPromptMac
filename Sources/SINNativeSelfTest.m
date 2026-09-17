#import "SINWindowController.h"
#import "SINNativeServices.h"
#import "SINSearchPanel.h"
#import "SINAppDelegate.h"

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
            [scratch.editor showSource:YES completion:^{
                NSError *error=nil;SINEditor *editor=scratch.editor;
                if(!check([editor.sourceView.string containsString:@"Native Alpha"],@"Native source view receives the complete visual document",&error)){next(error);return;}
                [editor.sourceView.undoManager removeAllActions];
                [editor.sourceView insertText:@"<!-- Native source edit -->" replacementRange:NSMakeRange(editor.sourceView.string.length,0)];
                NSRange selected=editor.sourceView.selectedRange;
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
                if(!check(scratch.preview!=nil&&scratch.documents.count==count&&scratch.active==active,@"Native file preview stays outside open documents and preserves the active HTML",&error)){next(error);return;}
                [scratch.preview removeFromSuperview];scratch.preview=nil;next(nil);
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
