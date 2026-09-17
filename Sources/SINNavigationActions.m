#import "SINWindowController.h"
#import "SINNativeServices.h"
#import <PDFKit/PDFKit.h>
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
    if([action isEqual:@"reveal"]||[action isEqual:@"revealPath"]){if(path)[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];return;}
    if([action isEqual:@"openFolder"]||[action isEqual:@"openFolderPath"]){if(path)[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path.stringByDeletingLastPathComponent]];return;}
    if([action isEqual:@"copyPath"]){if(path){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:path forType:NSPasteboardTypeString];}return;}
    if([action isEqual:@"pin"]){document.pinned=!document.pinned;[self refresh];[self persist];return;}
    if([action isEqual:@"rename"]){[self renameDocument:document];return;}
    if([action isEqual:@"close"]){[self closeDocument:document];return;}
    if([action isEqual:@"trash"]||[action isEqual:@"trashPath"]){if(path)[self trashPath:path];return;}
    if([action isEqual:@"renamePath"]){if([@[@"html",@"htm"] containsObject:path.pathExtension.lowercaseString]){SINDocument *doc=nil;for(SINDocument *d in self.documents)if([d.path isEqual:path])doc=d;
            if(!doc){NSError *error=nil;doc=[SINDocument openPath:path error:&error];if(!doc){[self showError:error];return;}[self.documents addObject:doc];}[self renameDocument:doc];}
        else if([@[@"png",@"jpg",@"jpeg",@"gif"] containsObject:path.pathExtension.lowercaseString])[self renameImageAtPath:path];
        return;
    }
    if([action isEqual:@"duplicate"]){
        SINEditor *editor=self.editors[document.identifier];if(!editor){[self activate:document];editor=self.editor;}
        [editor exportKind:@"duplicate" completion:^(NSString *html,NSError *error){if(error){[self showError:error];return;}SINDocument *copy=[self.store newDocument:&error];if(!copy){[self showError:error];return;}copy.text=html;copy.encodingName=document.encodingName;copy.zoom=document.zoom;copy.autosave=NO;
            NSString *stem=document.name.stringByDeletingPathExtension;NSUInteger number=2;NSString *name;do{name=[NSString stringWithFormat:@"%@ %lu.html",stem,(unsigned long)number++];}while([self.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.name isEqual:name];}]!=NSNotFound||[NSFileManager.defaultManager fileExistsAtPath:[document.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name]?:@""]);
            copy.draftName=name;if(document.path){NSString *destination=[document.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];if(![copy saveToPath:destination overwriteConflict:NO error:&error]){[self showError:error];return;}}
            [self.documents addObject:copy];[self activate:copy];
        }];return;
    }
}
- (void)showPreview:(NSString *)path {
    if(self.annotating)return;
    [self.editor flush:^{
        [self.preview removeFromSuperview];SINPreviewContainer *container=[[SINPreviewContainer alloc] initWithFrame:self.editorHost.bounds];container.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.preview=container;
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
        [self.editor evaluate:@"window.editor.stopMedia()" completion:nil];[self.editorHost addSubview:container];self.status.stringValue=[@"Read-only preview    ·    " stringByAppendingString:path];
    }];
}
- (void)returnFromPreview:(id)sender {[self.preview removeFromSuperview];self.preview=nil;[self refresh];[self.editor focusEditor];}
@end
