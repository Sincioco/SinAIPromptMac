#import "SINProjectSession.h"
#import "SINAppDelegate.h"

static NSError *ProjectTestError(NSString *message) { return [NSError errorWithDomain:@"SinProjectSelfTest" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static void ProjectTestSteps(NSArray<void (^)(void (^)(NSError *))> *steps,NSUInteger index,void (^done)(NSError *)) {
    if(index==steps.count){done(nil);return;}
    NSLog(@"Project integration stage %lu/%lu",(unsigned long)index+1,(unsigned long)steps.count);
    steps[index](^(NSError *error){if(error)done(error);else ProjectTestSteps(steps,index+1,done);});
}
static void ProjectTestImage(SINEditor *editor,NSUInteger attempts,void (^done)(NSError *)) {
    [editor evaluate:@"(()=>{const image=document.querySelector('#document').contentDocument.querySelector('img');return image&&image.complete&&image.naturalWidth>0;})()" completion:^(id result,NSError *error){
        if(error){done(error);return;}if([result boolValue]){done(nil);return;}
        if(!attempts){done(ProjectTestError(@"A moved document image did not load at its new path."));return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ProjectTestImage(editor,attempts-1,done);});
    }];
}
static void ProjectTestActive(SINWindowController *window,SINDocument *document,NSUInteger attempts,void (^done)(NSError *)) {
    if(window.active==document&&window.editor.document==document){[window.editor flush:^{done(nil);}];return;}
    if(!attempts){done(ProjectTestError(@"Native document activation did not complete."));return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ProjectTestActive(window,document,attempts-1,done);});
}
@implementation SINWindowController (ProjectSelfTest)
- (void)runProjectChecks:(void (^)(NSArray<NSString *> *,NSError *))completion {
    if(!self.testMode){completion(@[],ProjectTestError(@"Project integration checks require the isolated self-test profile."));return;}
    NSMutableArray *checks=NSMutableArray.new;__block NSError *failure=nil;
    BOOL (^check)(BOOL,NSString *)=^BOOL(BOOL condition,NSString *name){if(condition)[checks addObject:name];else failure=ProjectTestError(name);return condition;};
    NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
    NSString *root=[self.store.directory stringByAppendingPathComponent:[@"Project integration " stringByAppendingString:NSUUID.UUID.UUIDString]],*source=[root stringByAppendingPathComponent:@"Original prompts"];
    if(![fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:&error]){completion(checks,error);return;}
    NSString *project=[SINProjects createProjectInDirectory:root name:@"故事 #1" error:&error],*later=[SINProjects createProjectInDirectory:root name:@"Second destination" error:&error],*third=[SINProjects createProjectInDirectory:root name:@"Conflict destination" error:&error];
    if(!project||!later||!third){completion(checks,error);return;}
    NSArray *names=@[@"Open #1",@"Lazy #2",@"Closed #3",@"Locked #4"];NSMutableArray *paths=NSMutableArray.new;
    NSData *png=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6VAAAAABJRU5ErkJggg==" options:0];
    for(NSString *name in names){NSString *path=[[source stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"html"],*assets=path.stringByDeletingPathExtension;[paths addObject:path];
        [fm createDirectoryAtPath:assets withIntermediateDirectories:YES attributes:nil error:&error];[png writeToFile:[assets stringByAppendingPathComponent:@"picture.png"] options:0 error:&error];
        NSString *url=[name stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];url=[url stringByReplacingOccurrencesOfString:@"#" withString:@"%23"];
        NSString *html=[NSString stringWithFormat:@"<!doctype html><html><head><title>%@</title></head><body><p>Saved %@</p><img src=\"%@/picture.png\" data-sin-storage=\"separate\"><a href=\"../reference.txt\">Reference</a></body></html>",name,name,url];
        [html writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    }
    [@"External reference" writeToFile:[root stringByAppendingPathComponent:@"reference.txt"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    [fm setAttributes:@{NSFilePosixPermissions:@0444} ofItemAtPath:paths[3] error:&error];
    SINStore *store=[[SINStore alloc] initWithDirectory:[root stringByAppendingPathComponent:@"Profile"] error:&error];
    if(!store||error){completion(checks,error);return;}
    [SINProjects rememberProjectFolder:project settings:store.settings error:NULL];[SINProjects rememberProjectFolder:later settings:store.settings error:NULL];
    SINDocument *visible=[SINDocument openPath:paths[0] error:&error],*lazy=[SINDocument openPath:paths[1] error:&error],*locked=[SINDocument openPath:paths[3] error:&error],*alias=[SINDocument openPath:paths[0] error:&error];
    lazy.text=[lazy.text stringByReplacingOccurrencesOfString:@"</body>" withString:@"<p>Unsaved lazy project text</p></body>"];visible.emoji=@"🌌";[store rememberDocumentEmoji:visible oldPath:nil];[store addRecentPath:visible.path];
    SINWindowController *window=[[SINWindowController alloc] initWithStore:store documents:@[visible,lazy,locked] activeIdentifier:visible.identifier];window.testMode=YES;[window.timer invalidate];window.timer=nil;
    SINWindowController *other=[[SINWindowController alloc] initWithStore:store documents:@[alias] activeIdentifier:alias.identifier];other.testMode=YES;[other.timer invalidate];other.timer=nil;
    SINAppDelegate *delegate=(SINAppDelegate *)NSApp.delegate;[delegate.windows addObject:window];[delegate.windows addObject:other];[window showWindow:nil];[other showWindow:nil];
    SINEditor *editor=window.editor,*otherEditor=other.editor;NSUInteger editorCount=window.editors.count+other.editors.count;
    void (^finish)(NSError *)=^(NSError *problem){
        for(SINWindowController *owner in @[window,other]){for(SINEditor *created in owner.editors.allValues)[created invalidate];owner.closing=YES;owner.window.delegate=nil;[owner.window close];[delegate.windows removeObject:owner];}
        [fm removeItemAtPath:root error:NULL];[self.window makeKeyAndOrderFront:nil];completion(checks,problem);
    };
    NSArray *steps=@[
        ^(void (^next)(NSError *)){
            [editor flush:^{[otherEditor flush:^{
                if(!check([visible.text isEqual:visible.savedText]&&[alias.text isEqual:alias.savedText]&&[alias.text containsString:@"Saved Open #1"],@"Immediate flush waits for initial native editor HTML to load without erasing the saved buffer")){next(ProjectTestError([NSString stringWithFormat:@"%@\nSource saved:%@\nSource actual:%@\nAlias saved:%@\nAlias actual:%@",failure.localizedDescription,visible.savedText,visible.text,alias.savedText,alias.text]));return;}
                visible.text=@"<p>Superseded load must never replace the latest buffer</p>";[editor reload];visible.text=visible.savedText;[editor reload];
                [editor flush:^{
                if(!check([visible.text isEqual:visible.savedText]&&!visible.modified,@"Overlapping native reloads publish only the latest raw HTML baseline before flushing")){next(failure);return;}
                [editor showSource:YES completion:^{
                    [editor.sourceView setSelectedRange:NSMakeRange(editor.sourceView.string.length,0)];[editor.sourceView insertText:@"\n<p>Unsaved source project text</p>" replacementRange:editor.sourceView.selectedRange];
                    [otherEditor asyncScript:@"const doc=document.querySelector('#document').contentDocument,p=doc.querySelector('p'),range=doc.createRange();range.selectNodeContents(p);range.collapse(false);doc.body.focus();doc.getSelection().removeAllRanges();doc.getSelection().addRange(range);doc.dispatchEvent(new Event('selectionchange'));window.editor.command('insertText','Independent second-window pending text');return true;" completion:^(id result,NSError *e){if(e){next(e);return;}[otherEditor flush:^{check(alias.modified&&[alias.text containsString:@"Independent second-window pending text"],@"The second window independently edits its visual prompt before moving");next(failure);}];}];
                }];
                }];
            }];}];
        },
        ^(void (^next)(NSError *)){
            NSMenuItem *menu=[window projectMenuForItems:@[visible,lazy]],*lockedMenu=[window projectMenuForItems:@[locked]],*draftMenu=[window projectMenuForItems:@[SINDocument.new]];
            if(!check(menu.enabled&&menu.submenu.numberOfItems==4&&lockedMenu.enabled&&!draftMenu.enabled,@"Project menus offer physical destinations for saved and locked prompts and reject drafts")){next(failure);return;}
            [window moveItems:@[visible,@"not-html.txt"] toProject:project completion:^(NSArray *results,NSArray *warnings,NSError *e){
                if(!check(!results&&e&&[fm fileExistsAtPath:visible.path],@"Mixed non-HTML project selection is rejected without moving saved prompts")){next(failure);return;}
                [window moveItems:@[SINDocument.new] toProject:project completion:^(NSArray *r,NSArray *w,NSError *err){check(!r&&err,@"Unsaved drafts cannot be moved into a project");next(failure);}];
            }];
        },
        ^(void (^next)(NSError *)){
            [window moveItems:@[visible,lazy,paths[2],locked] toProject:project completion:^(NSArray<SINProjectMoveResult *> *results,NSArray *warnings,NSError *e){
                if(e){next(e);return;}
                if(!check(results.count==4&&!warnings.count,@"Native project workflow moves a mixed open, closed, lazy and locked batch")){next(failure);return;}
                for(NSString *path in paths)if(!check(![fm fileExistsAtPath:path]&&[fm fileExistsAtPath:[project stringByAppendingPathComponent:path.lastPathComponent]]&&[fm fileExistsAtPath:[[project stringByAppendingPathComponent:path.lastPathComponent] stringByDeletingPathExtension]],@"Project publication moves saved HTML and its matching image folder")){next(failure);return;}
                if(!check(window.active==visible&&window.editor==editor&&other.active==alias&&other.editor==otherEditor&&[visible.path isEqual:alias.path],@"Existing editors and every window sharing a moved source retain their model identity")){next(failure);return;}
                if(!check(visible.modified&&lazy.modified&&alias.modified&&[visible.text containsString:@"Unsaved source project text"]&&[lazy.text containsString:@"Unsaved lazy project text"]&&[alias.text containsString:@"Independent second-window pending text"]&&![alias.text containsString:@"Unsaved source project text"],@"Project moves preserve independent source, lazy and second-window unsaved buffers")){next(ProjectTestError([NSString stringWithFormat:@"%@\nSource dirty=%d: %@\nLazy dirty=%d: %@\nSecond window dirty=%d: %@",failure.localizedDescription,visible.modified,visible.text,lazy.modified,lazy.text,alias.modified,alias.text]));return;}
                SINDocument *saved=[SINDocument openPath:visible.path error:NULL];
                if(!check(![saved.text containsString:@"Unsaved"]&&[visible.savedText isEqual:saved.text]&&[visible.fingerprint isEqual:saved.fingerprint]&&locked.readOnly&&!locked.modified,@"Moved saved files exclude pending text and retain clean locked state and fingerprints")){next(failure);return;}
                if(!check(editor.showingSource&&[editor.sourceView.string isEqual:visible.text]&&window.editors.count+other.editors.count==editorCount&&window.documents.count==3,@"Source view stays active and closed or lazy moves create no extra models or WebViews")){next(failure);return;}
                if(!check([store.settings[@"recent"] containsObject:visible.path]&&![store.settings[@"recent"] containsObject:paths[0]]&&[store.settings[@"documentEmojis"][visible.path] isEqual:@"🌌"]&&!store.settings[@"documentEmojis"][paths[0]],@"Project integration transfers recent-file and emoji metadata to destination paths")){next(failure);return;}
                if(!check(!window.saving&&!other.saving&&!visible.readOnly&&!alias.readOnly,@"Project completion restores each window and document's editing state")){next(failure);return;}
                ProjectTestImage(otherEditor,100,^(NSError *imageError){if(!imageError)check(YES,@"The existing visual editor loads images from the moved project folder");next(imageError);});
            }];
        },
        ^(void (^next)(NSError *)){
            [window moveItems:@[visible,lazy] toProject:later completion:^(NSArray *results,NSArray *warnings,NSError *e){
                if(e){next(e);return;}
                if(!check(results.count==2&&editor.showingSource&&[editor.sourceView.string containsString:@"Unsaved source project text"]&&[visible.path.stringByDeletingLastPathComponent isEqual:later]&&[alias.path isEqual:visible.path]&&[lazy.text containsString:@"Unsaved lazy project text"],@"A second project move preserves source editing, shared windows and lazy dirty buffers")){next(failure);return;}
                [editor showSource:NO completion:^{[editor flush:^{ProjectTestImage(editor,100,^(NSError *imageError){if(!imageError)check(visible.modified&&[visible.text containsString:@"Unsaved source project text"],@"Returning to Visual after project moves loads relocated images and preserves unsaved source text");next(imageError?:failure);});}];}];
            }];
        },
        ^(void (^next)(NSError *)){
            [window activate:locked];
            ProjectTestActive(window,locked,100,^(NSError *activationError){
                if(activationError){next(activationError);return;}
                [window moveItems:@[locked] toProject:later completion:^(NSArray *results,NSArray *warnings,NSError *e){if(e){next(e);return;}
                    if(!check(results.count==1&&locked.readOnly&&!locked.modified,@"Moving the active clean read-only prompt preserves its file lock and clean baseline")){next(failure);return;}
                    ProjectTestImage(window.editor,100,^(NSError *imageError){if(!imageError)check(YES,@"A moved locked document still renders its image");next(imageError);});
                }];
            });
        },
        ^(void (^next)(NSError *)){
            NSString *old=visible.path,*pending=visible.text;[@"External disk edit" writeToFile:old atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [window moveItems:@[visible] toProject:third completion:^(NSArray *results,NSArray *warnings,NSError *e){
                check(!results&&e&&[visible.path isEqual:old]&&[visible.text isEqual:pending]&&!visible.readOnly&&!window.saving&&!other.saving&&[[NSString stringWithContentsOfFile:old encoding:NSUTF8StringEncoding error:NULL] isEqual:@"External disk edit"],@"External disk conflicts reject project moves while preserving pending edits and restoring all window guards");next(failure);
            }];
        }
    ];
    ProjectTestSteps(steps,0,finish);
}
@end
