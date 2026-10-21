#import "SINWindowController.h"
#import "SINAppDelegate.h"
#import "SINTabButton.h"

// Keep this regression suite callable without exposing test-only behavior in
// production menu actions. Every action below targets disposable local files.
@interface SINWindowController (ContextMenuCheckAPI)
- (NSMenu *)documentContextMenu:(SINDocument *)document;
@end
@interface SINNavigator (ContextMenuCheckAPI)
- (NSMenu *)contextMenuForItem:(id)item;
@end
@interface SINContextCheckWindow : SINWindowController
@property(nonatomic,strong) NSError *contextFailure;
@end
@implementation SINContextCheckWindow
- (void)showError:(NSError *)error { self.contextFailure=error; }
@end

static NSError *ContextError(NSString *message) {
    return [NSError errorWithDomain:@"SinContextMenuSelfTest" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static void ContextPoll(BOOL (^ready)(void), NSUInteger remaining, void (^done)(BOOL)) {
    if(ready()){done(YES);return;}
    if(!remaining){done(NO);return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ContextPoll(ready,remaining-1,done);});
}
static void ContextLoaded(SINEditor *editor,void (^done)(NSError *)) {
    if(!editor){done(ContextError(@"Context-menu test did not create the requested editor."));return;}
    ContextPoll(^BOOL{return editor.ready;},200,^(BOOL ready){
        if(!ready){done(ContextError(@"Context-menu editor did not become ready."));return;}
        [editor asyncScript:@"await window.editor.ready();return true;" completion:^(id result,NSError *error){done(error);}];
    });
}
static void ContextRespondToSheet(SINContextCheckWindow *window,NSModalResponse response,void (^done)(NSError *)) {
    ContextPoll(^BOOL{return window.contextFailure||window.window.attachedSheet!=nil;},150,^(BOOL shown){
        if(!shown||window.contextFailure){done(window.contextFailure?:ContextError(@"The context action did not present its confirmation sheet."));return;}
        [window.window endSheet:window.window.attachedSheet returnCode:response];
        ContextPoll(^BOOL{return !window.window.attachedSheet;},100,^(BOOL dismissed){done(dismissed?nil:ContextError(@"The confirmation sheet did not close."));});
    });
}
static void ContextSteps(NSArray *steps,NSUInteger index,BOOL (^finished)(void),void (^done)(NSError *)) {
    if(finished())return;
    if(index==steps.count){done(nil);return;}
    void (^step)(void (^)(NSError *))=steps[index];
    step(^(NSError *error){if(error)done(error);else ContextSteps(steps,index+1,finished,done);});
}
static NSArray *ContextMenuValues(NSMenu *menu,NSString *field) {
    NSMutableArray *values=NSMutableArray.new;
    for(NSMenuItem *item in menu.itemArray){
        if(item.separatorItem){[values addObject:@"|"];continue;}
        if([field isEqual:@"title"])[values addObject:item.title?:@""];
        else if([field isEqual:@"command"])[values addObject:[item.representedObject isKindOfClass:NSDictionary.class]?item.representedObject[@"command"]?:@"":@""];
        else [values addObject:@(item.enabled)];
    }
    return values;
}
static NSMenuItem *ContextItem(NSMenu *menu,NSString *command) {
    for(NSMenuItem *item in menu.itemArray)if([item.representedObject isKindOfClass:NSDictionary.class]&&[item.representedObject[@"command"] isEqual:command])return item;
    return nil;
}
static BOOL ContextClick(NSMenu *menu,NSString *command,NSError **error) {
    NSMenuItem *item=ContextItem(menu,command);
    if(!item||!item.enabled||!item.action||![NSApp sendAction:item.action to:item.target from:item]){
        if(error)*error=ContextError([@"Unable to dispatch enabled menu command: " stringByAppendingString:command]);return NO;
    }
    return YES;
}
static BOOL ContextMatches(NSArray *actual,NSArray *expected,NSString *name,NSError **error) {
    if([actual isEqual:expected])return YES;
    if(error)*error=ContextError([NSString stringWithFormat:@"%@: expected %@; received %@",name,expected,actual]);return NO;
}
static NSString *ContextPathText(NSString *path) { return [path containsString:@" "]?[NSString stringWithFormat:@"\"%@\"",path]:path; }
static NSString *ContextFirstImageSource(NSString *html) {
    NSRegularExpression *expression=[NSRegularExpression regularExpressionWithPattern:@"<img\\b[^>]*?\\bsrc\\s*=\\s*([\"'])(.*?)\\1" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *match=[expression firstMatchInString:html?:@"" options:0 range:NSMakeRange(0,html.length)];
    return match?[html substringWithRange:[match rangeAtIndex:2]]:@"(missing)";
}
static NSString *ContextGeometry(NSOutlineView *outline,NSTableCellView *cell) {
    return [NSString stringWithFormat:@"outline=%@ column=%.2f columnRect=%@ cell=%@ text=%@ clip=%@ intercell=%.2f contentInsets={%.2f,%.2f,%.2f,%.2f}",NSStringFromRect(outline.bounds),outline.tableColumns.firstObject.width,NSStringFromRect([outline rectOfColumn:0]),NSStringFromRect(cell.frame),NSStringFromRect(cell.textField.frame),NSStringFromRect(outline.enclosingScrollView.contentView.bounds),outline.intercellSpacing.width,outline.enclosingScrollView.contentInsets.top,outline.enclosingScrollView.contentInsets.left,outline.enclosingScrollView.contentInsets.bottom,outline.enclosingScrollView.contentInsets.right];
}
static BOOL ContextColumnFillsOutline(NSOutlineView *outline,NSTableCellView *cell) {
    // AppKit's SourceList style reserves symmetric outer margins. Compare the
    // rendered cell with those margins, not the un-inset scroll viewport.
    NSRect column=[cell.superview convertRect:cell.frame toView:outline];
    return column.origin.x>=0&&column.origin.x<=20&&fabs(NSMaxX(column)-(outline.bounds.size.width-column.origin.x))<3&&fabs(column.size.width-outline.tableColumns.firstObject.width)<3;
}
static NSArray *ContextPasteboard(NSError **error) {
    NSMutableArray *saved=NSMutableArray.new;
    for(NSPasteboardItem *item in NSPasteboard.generalPasteboard.pasteboardItems){
        NSMutableDictionary *values=NSMutableDictionary.new;
        for(NSPasteboardType type in item.types){NSData *bytes=[item dataForType:type];if(!bytes){if(error)*error=ContextError(@"An existing clipboard format could not be preserved.");return nil;}values[type]=bytes;}
        [saved addObject:values];
    }
    return saved;
}
static void ContextRestorePasteboard(NSArray *saved) {
    NSMutableArray *items=NSMutableArray.new;
    for(NSDictionary *values in saved){NSPasteboardItem *item=NSPasteboardItem.new;for(NSPasteboardType type in values)[item setData:values[type] forType:type];[items addObject:item];}
    [NSPasteboard.generalPasteboard clearContents];if(items.count)[NSPasteboard.generalPasteboard writeObjects:items];
}

@implementation SINWindowController (ContextMenuSelfTest)
- (void)runNativeContextMenuChecks:(void (^)(NSArray<NSString *> *,NSError *))completion {
    if(!self.testMode){completion(@[],ContextError(@"Context-menu checks require an isolated test-mode window."));return;}
    NSError *setupError=nil;NSArray *pasteboard=ContextPasteboard(&setupError);
    if(!pasteboard){completion(@[],setupError);return;}
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *directory=[self.store.directory stringByAppendingPathComponent:[@"ContextMenu-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    SINStore *store=[[SINStore alloc] initWithDirectory:directory error:&setupError];
    if(!store){completion(@[],setupError);return;}
    SINDocument *active=[store newDocument:&setupError],*target=[store newDocument:&setupError],*draft=[store newDocument:&setupError],*missing=[store newDocument:&setupError],*lazy=[store newDocument:&setupError];
    active.text=@"<!doctype html><html><body><p>ACTIVE DOCUMENT SENTINEL</p></body></html>";
    target.text=@"<!doctype html><html><body><p>CLICKED TARGET SENTINEL</p></body></html>";
    lazy.text=@"<!doctype html><html><body><p>LAZY DUPLICATE SOURCE SENTINEL</p><img src='External%20original.png' data-sin-storage='separate'></body></html>";
    lazy.newline=@"\r\n";
    NSBitmapImageRep *pixels=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:8 bitsPerPixel:32];
    memset(pixels.bitmapData,127,16);
    NSData *originalPNG=[pixels representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSString *externalImage=[directory stringByAppendingPathComponent:@"External original.png"];
    NSString *longName=@"Active-document-with-a-long-name-that-needs-the-available-sidebar-width.html";
    if(!active||!target||!draft||!missing||!lazy||![originalPNG writeToFile:externalImage options:NSDataWritingAtomic error:&setupError]||
       ![active saveToPath:[directory stringByAppendingPathComponent:longName] overwriteConflict:NO error:&setupError]||
       ![target saveToPath:[directory stringByAppendingPathComponent:@"Saved Target.html"] overwriteConflict:NO error:&setupError]||
       ![missing saveToPath:[directory stringByAppendingPathComponent:@"Missing.html"] overwriteConflict:NO error:&setupError]||
       ![lazy saveToPath:[directory stringByAppendingPathComponent:@"Lazy.html"] overwriteConflict:NO error:&setupError]||
       ![fm removeItemAtPath:missing.path error:&setupError]){
        [fm removeItemAtPath:directory error:NULL];completion(@[],setupError?:ContextError(@"Unable to create context-menu fixtures."));return;
    }
    NSString *assetFolder=target.path.stringByDeletingPathExtension,*plainFolder=[directory stringByAppendingPathComponent:@"Ordinary folder"];
    NSString *imagePath=[assetFolder stringByAppendingPathComponent:@"picture.png"],*pdfPath=[directory stringByAppendingPathComponent:@"Preview.pdf"];
    if(![fm createDirectoryAtPath:assetFolder withIntermediateDirectories:YES attributes:nil error:&setupError]||
       ![fm createDirectoryAtPath:plainFolder withIntermediateDirectories:YES attributes:nil error:&setupError]||
       ![@"menu fixture" writeToFile:imagePath atomically:YES encoding:NSUTF8StringEncoding error:&setupError]||
       ![@"menu fixture" writeToFile:pdfPath atomically:YES encoding:NSUTF8StringEncoding error:&setupError]){
        [fm removeItemAtPath:directory error:NULL];completion(@[],setupError);return;
    }
    SINContextCheckWindow *scratch=[[SINContextCheckWindow alloc] initWithStore:store documents:@[active,target,draft,missing,lazy] activeIdentifier:active.identifier];
    scratch.testMode=YES;[scratch.timer invalidate];
    [scratch.window orderWindow:NSWindowBelow relativeTo:self.window.windowNumber];
    NSMutableArray<NSString *> *checks=NSMutableArray.new;
    BOOL (^check)(BOOL,NSString *,NSError **)=^BOOL(BOOL passed,NSString *name,NSError **error){if(passed){[checks addObject:name];return YES;}if(error&&!*error)*error=ContextError(name);return NO;};
    __block BOOL finished=NO;
    __block SINEditor *targetEditor=nil;
    __block NSString *targetSaved=nil;
    __block CGFloat narrowOutlineWidth=0,narrowTextWidth=0;
    NSData *activeBytes=[NSData dataWithContentsOfFile:active.path];
    void (^finish)(NSError *)=^(NSError *error){
        if(finished)return;finished=YES;
        if(scratch.window.attachedSheet)[scratch.window endSheet:scratch.window.attachedSheet returnCode:NSModalResponseCancel];
        scratch.closing=YES;[scratch.timer invalidate];
        for(SINDocument *document in scratch.documents)if(document.readOnly)[document setFileReadOnly:NO error:NULL];
        for(SINEditor *editor in scratch.editors.allValues)[editor invalidate];
        [scratch.window close];ContextRestorePasteboard(pasteboard);
        [fm removeItemAtPath:directory error:NULL];completion(checks,error?:scratch.contextFailure);
    };
    BOOL (^menuCheck)(SINDocument *,NSArray *,NSArray *,NSString *,NSError **)=^BOOL(SINDocument *document,NSArray *titles,NSArray *enabled,NSString *name,NSError **error){
        NSMenu *menu=[scratch documentContextMenu:document];
        NSArray *commands=@[@"rename",@"duplicate",@"pin",@"private",@"emoji",document.readOnly?@"unlock":@"lock",@"",@"trash",@"|",@"copyPath",@"copyAI",@"openFolder",@"|",@"revert",@"close"];
        if(!ContextMatches(ContextMenuValues(menu,@"title"),titles,[name stringByAppendingString:@" titles"],error)||
           !ContextMatches(ContextMenuValues(menu,@"command"),commands,[name stringByAppendingString:@" commands"],error)||
           !ContextMatches(ContextMenuValues(menu,@"enabled"),enabled,[name stringByAppendingString:@" enabled states"],error))return NO;
        [checks addObject:name];return YES;
    };
    NSArray *normalTitles=@[@"Rename…",@"Duplicate",@"Pin To Top",@"Private",@"Choose Emoji…",@"Lock Document",@"Move to Project",@"Delete…",@"|",@"Copy Full Path",@"Copy for AI Use",@"Open Containing Folder",@"|",@"Revert To Last Saved…",@"Close"];
    NSArray *allEnabled=@[@YES,@YES,@YES,@YES,@YES,@YES,@YES,@YES,@"|",@YES,@YES,@YES,@"|",@YES,@YES];
    NSArray *steps=@[
        ^(void (^next)(NSError *)){
            ContextLoaded(scratch.editor,next);
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;
            if(!menuCheck(draft,normalTitles,@[@YES,@YES,@YES,@YES,@YES,@YES,@NO,@YES,@"|",@NO,@YES,@NO,@"|",@NO,@YES],@"Draft document menu includes emoji, privacy and Delete while disabling saved-file actions",&error)||
               !menuCheck(target,normalTitles,allEnabled,@"Saved document menu matches upstream command order, labels and enabled states",&error)||
               !menuCheck(missing,normalTitles,@[@NO,@YES,@YES,@YES,@YES,@YES,@YES,@NO,@"|",@YES,@YES,@YES,@"|",@NO,@YES],@"Missing-file document menu retains path actions and disables file-required actions",&error)){next(error);return;}
            target.pinned=YES;NSMutableArray *pinned=normalTitles.mutableCopy;pinned[2]=@"Unpin";
            if(!menuCheck(target,pinned,allEnabled,@"Pinned document menu offers Unpin at the original command position",&error)){next(error);return;}
            target.pinned=NO;
            if(![target setFileReadOnly:YES error:&error]){next(error);return;}
            NSMutableArray *locked=normalTitles.mutableCopy;locked[5]=@"Unlock Document";
            if(!menuCheck(target,locked,allEnabled,@"Locked document menu offers Unlock without dropping other upstream commands",&error)){next(error);return;}
            if(![target setFileReadOnly:NO error:&error]){next(error);return;}
            NSMenuItem *close=ContextItem([scratch documentContextMenu:target],@"close");
            check([close.keyEquivalent.lowercaseString isEqual:@"w"]&&(close.keyEquivalentModifierMask&NSEventModifierFlagCommand),@"Document context Close displays the Mac Command-W equivalent",&error);next(error);
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;[scratch refresh];NSMenu *shared=[scratch documentContextMenu:target],*navigator=[scratch.navigator contextMenuForItem:target];
            SINTabButton *tab=nil;for(NSView *view in scratch.tabs.arrangedSubviews)if([view.identifier isEqual:target.identifier])tab=(SINTabButton *)view;
            NSEvent *event=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSMakePoint(1,1) modifierFlags:0 timestamp:0 windowNumber:scratch.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
            NSMenu *tabs=[tab menuForEvent:event];
            if(!check(tab&&ContextMatches(ContextMenuValues(tabs,@"title"),ContextMenuValues(shared,@"title"),@"Tab menu labels",&error)&&ContextMatches(ContextMenuValues(tabs,@"command"),ContextMenuValues(shared,@"command"),@"Tab menu commands",&error)&&ContextMatches(ContextMenuValues(tabs,@"enabled"),ContextMenuValues(shared,@"enabled"),@"Tab menu enabled states",&error),@"Document tabs use the same complete menu and enabled states as document rows",&error)||
               !check(ContextMatches(ContextMenuValues(navigator,@"title"),ContextMenuValues(shared,@"title"),@"Navigator menu labels",&error)&&ContextMatches(ContextMenuValues(navigator,@"command"),ContextMenuValues(shared,@"command"),@"Navigator menu commands",&error),@"Document navigator delegates to the shared document context menu",&error)){next(error);return;}
            if(!ContextClick(tabs,@"copyPath",&error)){next(error);return;}
            if(!check([[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] isEqual:ContextPathText(target.path)]&&scratch.active==active,@"Copy Full Path from an inactive tab copies that document's quoted path",&error)){next(error);return;}
            if(!ContextClick([scratch.navigator contextMenuForItem:target],@"pin",&error)){next(error);return;}
            if(!check(target.pinned&&!active.pinned&&scratch.active==active,@"Pin from an inactive document row targets the clicked document",&error)){next(error);return;}
            if(!ContextClick([scratch documentContextMenu:target],@"pin",&error)){next(error);return;}
            check(!target.pinned,@"Unpin menu action reverses pinning on the same document",&error);next(error);
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;
            NSArray *fileTitles=@[@"Rename…",@"Delete to Trash…",@"|",@"Show in Finder",@"Open Containing Folder"];
            NSArray *fileCommands=@[@"renamePath",@"trashPath",@"|",@"revealPath",@"openFolderPath"];
            for(NSString *path in @[target.path,imagePath]){
                NSMenu *menu=[scratch.navigator contextMenuForItem:path];
                NSMutableArray *titles=fileTitles.mutableCopy,*commands=fileCommands.mutableCopy,*enabled=[@[@YES,@YES,@"|",@YES,@YES] mutableCopy];if([path isEqual:target.path]){[titles insertObject:@"Move to Project" atIndex:1];[commands insertObject:@"" atIndex:1];[enabled insertObject:@YES atIndex:1];}
                if(!ContextMatches(ContextMenuValues(menu,@"title"),titles,@"HTML/image Explorer labels",&error)||!ContextMatches(ContextMenuValues(menu,@"command"),commands,@"HTML/image Explorer commands",&error)||!ContextMatches(ContextMenuValues(menu,@"enabled"),enabled,@"HTML/image Explorer enabled states",&error)){next(error);return;}
            }
            [checks addObject:@"Explorer HTML and image menus preserve Rename/Delete order and Finder equivalents"];
            for(NSString *path in @[pdfPath,assetFolder]){
                NSMenu *menu=[scratch.navigator contextMenuForItem:path];
                if(!ContextMatches(ContextMenuValues(menu,@"title"),@[@"Delete to Trash…",@"|",@"Show in Finder",@"Open Containing Folder"],@"PDF/image-folder Explorer labels",&error)||!ContextMatches(ContextMenuValues(menu,@"command"),@[@"trashPath",@"|",@"revealPath",@"openFolderPath"],@"PDF/image-folder Explorer commands",&error)){next(error);return;}
            }
            [checks addObject:@"Explorer PDF and matching HTML asset-folder menus allow Delete without Rename"];
            NSMenu *folder=[scratch.navigator contextMenuForItem:plainFolder];
            check(ContextMatches(ContextMenuValues(folder,@"title"),@[@"Show in Finder",@"Open Containing Folder"],@"Ordinary folder Explorer labels",&error)&&ContextMatches(ContextMenuValues(folder,@"command"),@[@"revealPath",@"openFolderPath"],@"Ordinary folder Explorer commands",&error),@"Explorer ordinary folders expose only the two Finder location actions",&error);next(error);
        },
        ^(void (^next)(NSError *)){
            scratch.navigator.mode=1;[scratch.navigator refresh];[scratch.split setPosition:250 ofDividerAtIndex:0];[scratch layoutChrome];
            ContextPoll(^BOOL{[scratch.window.contentView layoutSubtreeIfNeeded];return scratch.navigator.outline.bounds.size.width>200;},100,^(BOOL settled){
                NSError *error=nil;NSOutlineView *outline=scratch.navigator.outline;NSInteger row=[outline rowForItem:active];NSTableCellView *cell=row>=0?[outline viewAtColumn:0 row:row makeIfNecessary:YES]:nil;
                narrowOutlineWidth=outline.bounds.size.width;narrowTextWidth=cell.textField.bounds.size.width;
                if(!check(settled&&cell&&ContextColumnFillsOutline(outline,cell)&&NSMaxX(cell.textField.frame)>cell.bounds.size.width-10,@"Document sidebar column and row label fill the available narrow outline width",&error))error=ContextError([NSString stringWithFormat:@"%@ (%@)",error.localizedDescription,ContextGeometry(outline,cell)]);next(error);
            });
        },
        ^(void (^next)(NSError *)){
            [scratch.split setPosition:450 ofDividerAtIndex:0];[scratch layoutChrome];
            ContextPoll(^BOOL{[scratch.window.contentView layoutSubtreeIfNeeded];return scratch.navigator.outline.bounds.size.width>narrowOutlineWidth+150;},100,^(BOOL settled){
                NSError *error=nil;NSOutlineView *outline=scratch.navigator.outline;NSInteger row=[outline rowForItem:active];NSTableCellView *cell=row>=0?[outline viewAtColumn:0 row:row makeIfNecessary:YES]:nil;
                if(!check(settled&&cell&&ContextColumnFillsOutline(outline,cell)&&cell.textField.bounds.size.width>narrowTextWidth+150&&[cell.textField.stringValue containsString:longName],@"Widening the sidebar grows the rendered long document label instead of keeping a fixed truncation width",&error))error=ContextError([NSString stringWithFormat:@"%@ (narrowText=%.2f; %@)",error.localizedDescription,narrowTextWidth,ContextGeometry(outline,cell)]);next(error);
            });
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;NSUInteger count=scratch.documents.count;NSArray *before=scratch.documents.copy;
            NSString *autosave=[directory stringByAppendingPathComponent:@"Duplicate autosave guard"];
            store.settings[@"autoSaveDirectory"]=autosave;
            NSNumber *nextDocumentNumber=store.settings[@"nextDocumentNumber"];
            if(!check(!scratch.editors[lazy.identifier]&&scratch.active==active,@"Duplicate regression begins with an inactive document whose editor is still lazy",&error)||!ContextClick([scratch documentContextMenu:lazy],@"duplicate",&error)){next(error);return;}
            ContextPoll(^BOOL{return scratch.contextFailure||(scratch.documents.count==count+1&&![before containsObject:scratch.active]&&!scratch.saving);},250,^(BOOL complete){
                NSError *failure=scratch.contextFailure;
                if(!check(complete&&!failure&&scratch.documents.count==count+1,@"Duplicating an inactive lazy document completes through its context action",&failure)){next(failure);return;}
                SINDocument *copy=scratch.active;NSString *disk=[NSString stringWithContentsOfFile:copy.path encoding:NSUTF8StringEncoding error:&failure];
                if(!check(!failure&&copy!=lazy&&[copy.text containsString:@"LAZY DUPLICATE SOURCE SENTINEL"]&&![copy.text containsString:@"ACTIVE DOCUMENT SENTINEL"]&&[disk containsString:@"LAZY DUPLICATE SOURCE SENTINEL"]&&![copy.path isEqual:lazy.path],@"Inactive lazy Duplicate exports the clicked source rather than the active document",&failure)){next(failure);return;}
                if(!check([copy.newline isEqual:lazy.newline]&&[store.settings[@"nextDocumentNumber"] isEqual:nextDocumentNumber]&&[fm contentsOfDirectoryAtPath:autosave error:NULL].count==0,@"Duplicate preserves source newline choice without consuming a prompt number or creating a blank autosave file",&failure)){next(failure);return;}
                NSString *copiedFolder=copy.path.stringByDeletingPathExtension;NSArray *assets=[fm contentsOfDirectoryAtPath:copiedFolder error:&failure];
                NSString *imageName=assets.firstObject;NSBitmapImageRep *copiedImage=imageName?[NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:[copiedFolder stringByAppendingPathComponent:imageName]]]:nil;
                NSString *relativeImage=[[copiedFolder.lastPathComponent stringByAppendingPathComponent:imageName?:@""] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
                if(!check(!failure&&assets.count==1&&copiedImage.pixelsWide==2&&copiedImage.pixelsHigh==2&&[disk containsString:[NSString stringWithFormat:@"src=\"%@\"",relativeImage]]&&![disk containsString:@"SinAI-duplicate-"]&&![disk containsString:@"External%20original.png"]&&[[NSData dataWithContentsOfFile:externalImage] isEqual:originalPNG],@"Saved Duplicate owns an independent PNG copied from outside the source asset folder without staging URLs or original-file changes",&failure)){
                    next(ContextError([NSString stringWithFormat:@"%@ (assets=%@ pixels=%ldx%ld originalUnchanged=%d expectedSrc=%@ actualSrc=%@)",failure.localizedDescription,assets,(long)copiedImage.pixelsWide,(long)copiedImage.pixelsHigh,[[NSData dataWithContentsOfFile:externalImage] isEqual:originalPNG],relativeImage,ContextFirstImageSource(disk)]));return;
                }
                ContextLoaded(scratch.editor,^(NSError *loadError){if(loadError){next(loadError);return;}[scratch activate:target];ContextPoll(^BOOL{return scratch.active==target;},150,^(BOOL activated){if(!activated){next(ContextError(@"Could not activate context target."));return;}targetEditor=scratch.editor;ContextLoaded(targetEditor,^(NSError *error){if(error){next(error);return;}[targetEditor showSource:YES completion:^{[scratch activate:active];ContextPoll(^BOOL{return scratch.active==active;},150,^(BOOL restored){next(restored?nil:ContextError(@"Could not restore the unrelated active document."));});}];});});});
            });
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;if(!ContextClick([scratch documentContextMenu:target],@"lock",&error)){next(error);return;}
            ContextPoll(^BOOL{return scratch.contextFailure||(!scratch.saving&&target.readOnly);},150,^(BOOL complete){
                NSError *error=scratch.contextFailure;NSUInteger mode=[[fm attributesOfItemAtPath:target.path error:NULL][NSFilePosixPermissions] unsignedIntegerValue];
                if(!check(complete&&!error&&target.readOnly&&!(mode&0222)&&!targetEditor.sourceView.editable&&!active.readOnly&&scratch.active==active,@"Lock from an inactive document menu saves and locks only the clicked file and editor",&error)){next(error);return;}
                if(!ContextClick([scratch documentContextMenu:target],@"unlock",&error)){next(error);return;}
                ContextRespondToSheet(scratch,NSAlertFirstButtonReturn,^(NSError *sheetError){
                    if(sheetError){next(sheetError);return;}
                    ContextPoll(^BOOL{return scratch.contextFailure||(!scratch.saving&&!target.readOnly);},150,^(BOOL unlocked){
                        NSError *error=scratch.contextFailure;NSUInteger mode=[[fm attributesOfItemAtPath:target.path error:NULL][NSFilePosixPermissions] unsignedIntegerValue];
                        check(unlocked&&!error&&(mode&0200)&&targetEditor.sourceView.editable&&!active.readOnly,@"Confirmed Unlock context action restores writable file permissions and the clicked source editor",&error);next(error);
                    });
                });
            });
        },
        ^(void (^next)(NSError *)){
            [targetEditor.sourceView insertText:@"<!-- FRESH AI HANDOFF EDIT -->" replacementRange:NSMakeRange(targetEditor.sourceView.string.length,0)];
            [NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:@"Before AI copy" forType:NSPasteboardTypeString];
            NSError *error=nil;if(!ContextClick([scratch documentContextMenu:target],@"copyAI",&error)){next(error);return;}
            NSString *expected=[NSString stringWithFormat:@"Read and execute the instructions in the \"%@\" file.",target.path];
            ContextPoll(^BOOL{return scratch.contextFailure||[[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] isEqual:expected];},200,^(BOOL copied){
                NSError *error=scratch.contextFailure;NSString *disk=[NSString stringWithContentsOfFile:target.path encoding:NSUTF8StringEncoding error:&error];
                if(!check(copied&&!error&&target.readOnly&&!target.modified&&[disk containsString:@"FRESH AI HANDOFF EDIT"]&&[[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] isEqual:expected],@"Copy for AI Use saves pending edits, locks the clicked document and copies exact quoted-path instructions",&error)){next(error);return;}
                if(!check(scratch.active==active&&!active.readOnly&&[[NSData dataWithContentsOfFile:active.path] isEqual:activeBytes],@"Copy for AI Use on an inactive document leaves the active document and its disk bytes unchanged",&error)){next(error);return;}
                targetSaved=disk;
                if(!ContextClick([scratch documentContextMenu:target],@"unlock",&error)){next(error);return;}
                ContextRespondToSheet(scratch,NSAlertFirstButtonReturn,^(NSError *sheetError){
                    if(sheetError){next(sheetError);return;}
                    ContextPoll(^BOOL{return !scratch.saving&&!target.readOnly;},150,^(BOOL unlocked){next(unlocked?nil:ContextError(@"Unlock after AI copy did not complete."));});
                });
            });
        },
        ^(void (^next)(NSError *)){
            [targetEditor.sourceView insertText:@"<!-- UNSAVED REVERT SENTINEL -->" replacementRange:NSMakeRange(targetEditor.sourceView.string.length,0)];
            NSString *pending=targetEditor.sourceView.string;NSError *error=nil;
            if(!ContextClick([scratch documentContextMenu:target],@"revert",&error)){next(error);return;}
            ContextPoll(^BOOL{return scratch.contextFailure||scratch.window.attachedSheet!=nil;},150,^(BOOL shown){
                if(!shown||scratch.contextFailure){next(scratch.contextFailure?:ContextError(@"Revert did not request confirmation."));return;}
                [scratch.window endSheet:scratch.window.attachedSheet returnCode:NSAlertSecondButtonReturn];
                ContextPoll(^BOOL{return !scratch.window.attachedSheet&&!scratch.saving;},150,^(BOOL dismissed){
                    NSError *error=nil;check(dismissed&&[targetEditor.sourceView.string isEqual:pending]&&[target.text isEqual:pending]&&target.modified&&[[NSString stringWithContentsOfFile:target.path encoding:NSUTF8StringEncoding error:NULL] isEqual:targetSaved],@"Cancelling Revert preserves the clicked document's unsaved source and saved file",&error);next(error);
                });
            });
        },
        ^(void (^next)(NSError *)){
            NSError *error=nil;if(!ContextClick([scratch documentContextMenu:target],@"revert",&error)){next(error);return;}
            ContextPoll(^BOOL{return scratch.contextFailure||scratch.window.attachedSheet!=nil;},150,^(BOOL shown){
                if(!shown||scratch.contextFailure){next(scratch.contextFailure?:ContextError(@"Second Revert did not request confirmation."));return;}
                [scratch.window endSheet:scratch.window.attachedSheet returnCode:NSAlertFirstButtonReturn];
                ContextPoll(^BOOL{return scratch.contextFailure||(!scratch.window.attachedSheet&&!scratch.saving&&[targetEditor.sourceView.string isEqual:targetSaved]);},150,^(BOOL reverted){
                    NSError *error=scratch.contextFailure;
                    check(reverted&&!error&&[target.text isEqual:targetSaved]&&!target.modified&&!targetEditor.sourceView.undoManager.canUndo&&!active.readOnly&&[[NSData dataWithContentsOfFile:active.path] isEqual:activeBytes],@"Confirmed Revert restores the clicked file's saved source, clears Undo and leaves the unrelated document unchanged",&error);next(error);
                });
            });
        },
        ^(void (^next)(NSError *)){
            [scratch activate:active];ContextPoll(^BOOL{return scratch.active==active;},150,^(BOOL activated){
                NSError *error=nil;if(!activated||!ContextClick([scratch documentContextMenu:target],@"close",&error)){next(error?:ContextError(@"Could not close the inactive target."));return;}
                ContextPoll(^BOOL{return ![scratch.documents containsObject:target];},150,^(BOOL closed){
                    NSError *error=nil;check(closed&&scratch.active==active&&[scratch.documents containsObject:active]&&!scratch.editors[target.identifier]&&[fm fileExistsAtPath:target.path],@"Close from an inactive document menu removes only that tab and retains its saved file",&error);next(error);
                });
            });
        }
    ];
    ContextSteps(steps,0,^BOOL{return finished;},finish);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!finished)finish(ContextError(@"Context-menu integration checks timed out."));});
}
@end
