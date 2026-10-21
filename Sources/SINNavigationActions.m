#import "SINWindowController.h"
#import "SINNativeServices.h"
#import "SINAppDelegate.h"
#import <PDFKit/PDFKit.h>
@interface SINWindowController (NavigationEditor)
- (SINEditor *)editorFor:(SINDocument *)document;
@end
@interface SINPreviewContainer : NSView
@property(nonatomic,strong) SINEditor *previewEditor;
@end
@implementation SINPreviewContainer
- (void)removeFromSuperview {[self.previewEditor invalidate];self.previewEditor=nil;[super removeFromSuperview];}
@end
@implementation SINWindowController (NavigationActions)
- (void)navigateAction:(NSString *)action item:(id)item {
    SINDocument *document=[item isKindOfClass:SINDocument.class]?item:self.active;
    NSString *path=[item isKindOfClass:NSString.class]?item:document.path;
    if([action isEqual:@"navigationMode"]){self.store.settings[@"navigationMode"]=item;if([item integerValue]==2)[self handleCommand:@"contentView"];[self persist];return;}
    if([action isEqual:@"showFolders"]){self.store.settings[@"explorerShowFolders"]=item;[self persist];return;}
    if([action isEqual:@"openDropped"]){[self openPaths:item];return;}
    if([action isEqual:@"chooseFolder"]||[action isEqual:@"new"]){[self handleCommand:action];return;}
    if(self.annotating||self.saving||self.window.attachedSheet)return;
    if([item isKindOfClass:SINDocument.class]&&![self.documents containsObject:document])return;
    if([action isEqual:@"private"]){document.privateDocument=!document.privateDocument;[self refreshPrivacy];return;}
    if([action isEqual:@"emoji"]){[self chooseEmoji:document];return;}
    if([action isEqual:@"combineSelection"]){[self combineItems:[self.navigator selectionIncludingItem:item]];return;}
    if([action isEqual:@"deleteSelection"]){[self deleteItems:[self.navigator selectionIncludingItem:item]];return;}
    if([action isEqual:@"reveal"]||[action isEqual:@"revealPath"]){if(path)[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];return;}
    if([action isEqual:@"openFolder"]||[action isEqual:@"openFolderPath"]){if(path)[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path.stringByDeletingLastPathComponent]];return;}
    if([action isEqual:@"copyPath"]){if(path){NSString *text=[path containsString:@" "]?[NSString stringWithFormat:@"\"%@\"",path]:path;[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];}return;}
    if([action isEqual:@"pin"]){
        document.pinned=!document.pinned;NSString *mode=self.navigator.sortMode;
        [self.documents sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(SINDocument *a,SINDocument *b){
            if(a.pinned!=b.pinned)return a.pinned?NSOrderedAscending:NSOrderedDescending;
            return [mode isEqual:@"manual"]?NSOrderedSame:([mode isEqual:@"created"]?[b.createdDate compare:a.createdDate]:[b.modifiedDate compare:a.modifiedDate]);
        }];[self refresh];[self persist];return;
    }
    if([action isEqual:@"lock"]||[action isEqual:@"unlock"]){[self changeDocumentLock:document locked:[action isEqual:@"lock"] completion:nil];return;}
    if([action isEqual:@"copyAI"]){[self copyDocumentForAI:document];return;}
    if([action isEqual:@"revert"]){[self revertDocument:document];return;}
    if([action isEqual:@"rename"]){[self renameDocument:document];return;}
    if([action isEqual:@"close"]){[self closeDocument:document];return;}
    if([action isEqual:@"trash"]||[action isEqual:@"trashPath"]){if(path)[self trashPath:path];else if(document)[self deleteItems:@[document]];return;}
    if([action isEqual:@"renamePath"]){if([@[@"html",@"htm"] containsObject:path.pathExtension.lowercaseString]){SINDocument *doc=nil;for(SINDocument *d in self.documents)if([d.path isEqual:path])doc=d;
            if(!doc){NSError *error=nil;doc=[SINDocument openPath:path error:&error];if(!doc){[self showError:error];return;}[self.documents addObject:doc];}[self renameDocument:doc];}
        else if([@[@"png",@"jpg",@"jpeg",@"gif"] containsObject:path.pathExtension.lowercaseString])[self renameImageAtPath:path];
        return;
    }
    if([action isEqual:@"duplicate"]){
        SINEditor *editor=[self editorFor:document];editor.services.window=self.window;self.saving=YES;
        NSString *stem=document.name.stringByDeletingPathExtension,*extension=document.name.pathExtension;NSUInteger number=2;NSString *name,*destination;
        NSMutableArray *windows=[((SINAppDelegate *)NSApp.delegate).windows mutableCopy]?:NSMutableArray.new;if(![windows containsObject:self])[windows addObject:self];
        NSMutableSet *names=NSMutableSet.new;for(SINWindowController *window in windows)for(SINDocument *open in window.documents)[names addObject:open.name.lowercaseString];
        do{name=[NSString stringWithFormat:@"%@ %lu%@%@",stem,(unsigned long)number++,extension.length?@".":@"",extension];destination=[document.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];}
        while([names containsObject:name.lowercaseString]||(destination&&([NSFileManager.defaultManager fileExistsAtPath:destination]||[NSFileManager.defaultManager fileExistsAtPath:destination.stringByDeletingPathExtension])));
        NSString *staging=nil,*stagedPath=nil;
        if(destination){
            staging=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SinAI-duplicate-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            NSError *error=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:&error]){self.saving=NO;[self showError:error];return;}
            stagedPath=[staging stringByAppendingPathComponent:name];editor.services.saveAsPath=stagedPath;
        }
        void (^create)(NSString *,NSError *)=^(NSString *html,NSError *error){
            editor.services.saveAsPath=nil;
            if(error||![self.documents containsObject:document]){if(staging)[NSFileManager.defaultManager removeItemAtPath:staging error:NULL];self.saving=NO;if(error)[self showError:error];return;}
            SINDocument *copy=SINDocument.new;copy.text=html;copy.encodingName=document.encodingName;copy.newline=document.newline;copy.zoom=document.zoom;copy.autosave=document.autosave&&document.path!=nil;
            copy.draftName=name;
            if(destination){
                BOOL saved=[copy saveToPath:stagedPath overwriteConflict:NO error:&error]&&[copy saveAsToPath:destination error:&error];
                [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
                if(!saved){self.saving=NO;[self showError:error];return;}[self.store addRecentPath:destination];
            }
            self.saving=NO;
            [self.documents addObject:copy];[self activate:copy];
        };
        [editor exportKind:destination?@"relocate":@"duplicate" completion:create];
        return;
    }
}
- (void)showPreview:(NSString *)path {
    if(self.annotating)return;
    [self.editor flush:^{
        [self.preview removeFromSuperview];SINPreviewContainer *container=[[SINPreviewContainer alloc] initWithFrame:self.documentPane.bounds];container.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.preview=container;container.frame=self.documentPane.bounds;
        NSButton *back=[NSButton buttonWithTitle:@"← Return to document" target:self action:@selector(returnFromPreview:)];back.frame=NSMakeRect(12,container.bounds.size.height-38,190,28);back.autoresizingMask=NSViewMinYMargin;[container addSubview:back];
        NSTextField *label=[NSTextField labelWithString:path.lastPathComponent];label.frame=NSMakeRect(220,container.bounds.size.height-34,MAX(100,container.bounds.size.width-230),24);label.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;[container addSubview:label];
        NSRect frame=NSMakeRect(0,0,container.bounds.size.width,container.bounds.size.height-44);NSString *extension=path.pathExtension.lowercaseString;
        if([extension isEqual:@"pdf"]){PDFView *pdf=[[PDFView alloc] initWithFrame:frame];pdf.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;pdf.autoScales=YES;pdf.document=[[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];[container addSubview:pdf];}
        else if([@[@"png",@"jpg",@"jpeg",@"gif"] containsObject:extension]){NSImageView *image=[[NSImageView alloc] initWithFrame:frame];image.image=[[NSImage alloc] initWithContentsOfFile:path];image.imageScaling=NSImageScaleProportionallyUpOrDown;image.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[container addSubview:image];}
        else {
            NSError *error=nil;NSString *text=[NSString stringWithContentsOfFile:path usedEncoding:NULL error:&error];if(!text){[self showError:error];return;}
            if([extension isEqual:@"md"]){
                SINDocument *doc=SINDocument.new;doc.path=path;doc.text=@"";doc.readOnly=YES;SINEditor *preview=[[SINEditor alloc] initWithDocument:doc dataDirectory:self.store.directory];preview.preferences=@{@"showToolbar":@NO};container.previewEditor=preview;
                preview.view.frame=frame;preview.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[container addSubview:preview.view];__weak SINEditor *weakPreview=preview;
                preview.readyHandler=^{[weakPreview asyncScript:[NSString stringWithFormat:@"const markdown=await import('./markdown.js'); await window.editor.load(markdown.markdownToHtml(%@,'sin-asset://document/'),'sin-asset://document/');window.editor.setReadOnly(true);document.querySelector('#toolbar').hidden=true;return true;",SINJSON(text)] completion:^(id result,NSError *e){if(e)[self showError:e];}];};
            }else {NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:frame];scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;scroll.hasVerticalScroller=YES;NSTextView *view=[[NSTextView alloc] initWithFrame:scroll.bounds];view.editable=NO;view.richText=NO;view.string=text;view.font=[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];view.autoresizingMask=NSViewWidthSizable;view.textContainerInset=NSMakeSize(14,14);scroll.documentView=view;[container addSubview:scroll];}
        }
        [self.editor evaluate:@"window.editor.stopMedia()" completion:nil];[self.documentPane addSubview:container];self.status.stringValue=[@"Read-only preview    ·    " stringByAppendingString:path];
    }];
}
- (void)returnFromPreview:(id)sender {[self.preview removeFromSuperview];self.preview=nil;[self refresh];[self.editor focusEditor];}
@end
