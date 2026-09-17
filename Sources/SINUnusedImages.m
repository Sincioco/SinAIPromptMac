#import "SINWindowController.h"
#import "SINAppDelegate.h"
#import <objc/runtime.h>

static NSError *UnusedError(NSString *message) { return [NSError errorWithDomain:SINErrorDomain code:SINErrorStorage userInfo:@{NSLocalizedDescriptionKey:message}]; }
static NSString *UnusedIdentity(NSString *path) {
    path=path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if(attributes[NSFileSystemNumber]&&attributes[NSFileSystemFileNumber])return [NSString stringWithFormat:@"%@:%@",attributes[NSFileSystemNumber],attributes[NSFileSystemFileNumber]];
    return path.precomposedStringWithCanonicalMapping;
}
static NSString *UnusedDecode(NSString *value,BOOL *safe) {
    NSDictionary *named=@{@"amp":@"&",@"quot":@"\"",@"apos":@"'",@"lt":@"<",@"gt":@">",@"nbsp":@"\u00a0",@"ensp":@"\u2002",@"emsp":@"\u2003",@"thinsp":@"\u2009"};
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);" options:0 error:nil];NSMutableString *result=value.mutableCopy;
    for(NSTextCheckingResult *match in [[pattern matchesInString:value options:0 range:NSMakeRange(0,value.length)] reverseObjectEnumerator]) {
        NSString *entity=[value substringWithRange:[match rangeAtIndex:1]],*replacement=named[entity];
        if([entity hasPrefix:@"#"]){unsigned int number=0;if([entity hasPrefix:@"#x"])[[NSScanner scannerWithString:[entity substringFromIndex:2]] scanHexInt:&number];else number=[[entity substringFromIndex:1] intValue];if(number>0&&number<=0x10ffff&&!(number>=0xd800&&number<=0xdfff)){UTF32Char scalar=number;replacement=[[NSString alloc] initWithBytes:&scalar length:sizeof(scalar) encoding:NSUTF32LittleEndianStringEncoding];}}
        if(replacement)[result replaceCharactersInRange:match.range withString:replacement];else if(safe)*safe=NO;
    }return result;
}
static NSURL *UnusedLocalURL(NSURL *url,NSURL *document) {
    if([url.scheme isEqual:@"sin-asset"]&&[url.host isEqual:@"original"]){NSString *path=[[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES].percentEncodedPath stringByRemovingPercentEncoding];while([path hasPrefix:@"//"])path=[path substringFromIndex:1];return [NSURL fileURLWithPath:path];}
    if(([url.scheme isEqual:@"sin-asset"]&&[url.host isEqual:@"document"])||[url.host isEqual:@"sin-document.local"]){NSString *path=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES].percentEncodedPath;while([path hasPrefix:@"/"])path=[path substringFromIndex:1];return [[NSURL URLWithString:path relativeToURL:[document URLByDeletingLastPathComponent]] absoluteURL];}return url;
}
static BOOL UnusedCollect(NSString *html,NSString *path,NSMutableSet *used,NSError **error) {
    NSURL *document=[NSURL fileURLWithPath:path?:@"/Untitled.html"];
    NSRegularExpression *comments=[NSRegularExpression regularExpressionWithPattern:@"<!--[\\s\\S]*?(?:-->|$)|<(script|textarea)\\b[^>]*>[\\s\\S]*?</\\1\\s*>" options:NSRegularExpressionCaseInsensitive error:nil];
    html=[comments stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0,html.length) withTemplate:@""];
    NSRegularExpression *tags=[NSRegularExpression regularExpressionWithPattern:@"<[a-z][\\w:-]*\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *attributes=[NSRegularExpression regularExpressionWithPattern:@"([\\w:-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))" options:0 error:nil];
    NSMutableArray<NSDictionary *> *records=NSMutableArray.new;NSString *baseAddress=nil;
    for(NSTextCheckingResult *match in [tags matchesInString:html options:0 range:NSMakeRange(0,html.length)]){
        NSString *tag=[html substringWithRange:match.range];NSMutableDictionary *values=NSMutableDictionary.new;
        for(NSTextCheckingResult *attr in [attributes matchesInString:tag options:0 range:NSMakeRange(0,tag.length)])for(NSUInteger i=2;i<=4;i++)if([attr rangeAtIndex:i].location!=NSNotFound){values[[[tag substringWithRange:[attr rangeAtIndex:1]] lowercaseString]]=[tag substringWithRange:[attr rangeAtIndex:i]];break;}
        BOOL isBase=[tag rangeOfString:@"^<base\\b" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound;
        if(isBase){if(!baseAddress)baseAddress=values[@"href"];}else[records addObject:values];
    }
    __block BOOL safe=YES;NSURL *base=baseAddress?UnusedLocalURL([[NSURL URLWithString:UnusedDecode(baseAddress,&safe) relativeToURL:document] absoluteURL],document):document;
    void(^add)(NSString *)=^(NSString *source){if(!source.length)return;NSString *value=[source stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!value.length)return;
        // Network and inline references cannot use a local sibling asset.
        NSURL *raw=[NSURL URLWithString:value];if([@[@"data",@"blob",@"http",@"https",@"mailto",@"tel"] containsObject:raw.scheme.lowercaseString]&&![raw.host isEqual:@"sin-document.local"])return;
        NSURL *url=UnusedLocalURL([[NSURL URLWithString:UnusedDecode(value,&safe) relativeToURL:base] absoluteURL],document);if(url.isFileURL)[used addObject:UnusedIdentity(url.path)];};
    NSMutableArray<NSString *> *styles=NSMutableArray.new;
    for(NSDictionary *values in records){for(NSString *name in @[@"src",@"href",@"xlink:href",@"poster",@"data",@"background"])add(values[name]);
        for(NSString *candidate in [values[@"srcset"] componentsSeparatedByString:@","]){NSString *trim=[candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];add([[trim componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] firstObject]);}
        if(values[@"style"])[styles addObject:values[@"style"]];
    }
    NSRegularExpression *styleTags=[NSRegularExpression regularExpressionWithPattern:@"<style\\b[^>]*>([\\s\\S]*?)</style\\s*>" options:NSRegularExpressionCaseInsensitive error:nil];for(NSTextCheckingResult *match in [styleTags matchesInString:html options:0 range:NSMakeRange(0,html.length)])[styles addObject:[html substringWithRange:[match rangeAtIndex:1]]];
    NSRegularExpression *cssComments=[NSRegularExpression regularExpressionWithPattern:@"/\\*[\\s\\S]*?\\*/" options:0 error:nil],*urls=[NSRegularExpression regularExpressionWithPattern:@"url\\(\\s*(?:\"([^\"]*)\"|'([^']*)'|([^)]*?))\\s*\\)" options:NSRegularExpressionCaseInsensitive error:nil];
    for(NSString *raw in styles){BOOL cssSafe=YES;NSString *style=UnusedDecode(raw,&cssSafe);style=[cssComments stringByReplacingMatchesInString:style options:0 range:NSMakeRange(0,style.length) withTemplate:@""];for(NSTextCheckingResult *match in [urls matchesInString:style options:0 range:NSMakeRange(0,style.length)])for(NSUInteger i=1;i<=3;i++)if([match rangeAtIndex:i].location!=NSNotFound){add([style substringWithRange:[match rangeAtIndex:i]]);break;}}
    if(!safe&&error)*error=UnusedError([NSString stringWithFormat:@"Could not safely resolve an HTML entity in %@. No files have been deleted.",path.lastPathComponent]);return safe;
}
NSArray<NSString *> *SINUnusedImagePaths(NSString *folder,NSArray<NSDictionary *> *snapshots,NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;folder=folder.stringByExpandingTildeInPath.stringByStandardizingPath;
    NSDictionary *root=[fm attributesOfItemAtPath:folder error:error];if(!root)return nil;if(![root[NSFileType] isEqual:NSFileTypeDirectory]){if(error)*error=UnusedError(@"Choose a real document folder. Symbolic links are not scanned.");return nil;}
    __block NSError *scanError=nil;NSMutableArray<NSString *> *documents=NSMutableArray.new,*images=NSMutableArray.new;NSArray *imageTypes=@[@"png",@"jpg",@"jpeg",@"gif",@"bmp",@"webp",@"svg",@"tif",@"tiff",@"ico",@"heic"];
    NSDirectoryEnumerator<NSURL *> *enumerator=[fm enumeratorAtURL:[NSURL fileURLWithPath:folder isDirectory:YES] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLIsAliasFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url,NSError *failure){scanError=failure;return NO;}];
    for(NSURL *url in enumerator){NSNumber *link=nil,*alias=nil,*directory=nil;if(![url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:&scanError]||![url getResourceValue:&alias forKey:NSURLIsAliasFileKey error:&scanError]||![url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:&scanError])break;if(link.boolValue||alias.boolValue){if(directory.boolValue)[enumerator skipDescendants];continue;}if(directory.boolValue)continue;
        NSString *extension=url.pathExtension.lowercaseString;if([@[@"html",@"htm"] containsObject:extension])[documents addObject:url.path.stringByStandardizingPath];else if([imageTypes containsObject:extension])[images addObject:url.path.stringByStandardizingPath];}
    if(scanError){if(error)*error=scanError;return nil;}
    NSMutableSet *used=NSMutableSet.new,*open=NSMutableSet.new,*assets=NSMutableSet.new;
    for(NSDictionary *snapshot in snapshots){NSString *path=snapshot[@"path"],*text=snapshot[@"text"]?:snapshot[@"html"];if(![text isKindOfClass:NSString.class])continue;if(![path isKindOfClass:NSString.class])path=@"/Untitled.html";if(!UnusedCollect(text,path,used,error))return nil;[open addObject:UnusedIdentity(path)];}
    for(NSString *path in documents){if(![open containsObject:UnusedIdentity(path)]){SINDocument *document=[SINDocument openPath:path error:error];if(!document||!UnusedCollect(document.text,path,used,error))return nil;}[assets addObject:[path.stringByDeletingPathExtension stringByAppendingString:@"/"]];}
    NSMutableArray *result=NSMutableArray.new;
    for(NSString *path in images){BOOL inAssets=NO;for(NSString *prefix in assets)if([path hasPrefix:prefix]){inAssets=YES;break;}if(inAssets&&![used containsObject:UnusedIdentity(path)])[result addObject:path];}
    return [result sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

BOOL SINFolderContainsReferencedFiles(NSString *folder,NSArray<NSDictionary *> *snapshots,NSError **error) {
    NSDictionary *root=[NSFileManager.defaultManager attributesOfItemAtPath:folder error:error];if(!root)return YES;
    NSMutableSet *used=NSMutableSet.new;
    for(NSDictionary *snapshot in snapshots){NSString *html=snapshot[@"text"]?:snapshot[@"html"],*path=snapshot[@"path"];if(![html isKindOfClass:NSString.class])continue;if(!UnusedCollect(html,[path isKindOfClass:NSString.class]?path:@"/Untitled.html",used,error))return YES;}
    __block NSError *failure=nil;NSDirectoryEnumerator<NSURL *> *files=[NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:folder isDirectory:YES] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] options:0 errorHandler:^BOOL(NSURL *url,NSError *e){failure=e;return NO;}];
    for(NSURL *url in files){NSNumber *directory=nil,*link=nil;if(![url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:&failure]||![url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:&failure])break;if(link.boolValue&&directory.boolValue)[files skipDescendants];if((!directory.boolValue||link.boolValue)&&[used containsObject:UnusedIdentity(url.path)])return YES;}
    if(failure){if(error)*error=failure;return YES;}return NO;
}

#ifndef SIN_UNUSED_IMAGE_SCANNER_ONLY
static const void *UnusedPanelKey=&UnusedPanelKey;
static NSArray<SINWindowController *> *UnusedWindows(SINWindowController *owner) {SINAppDelegate *delegate=(SINAppDelegate *)NSApp.delegate;NSMutableArray *result=NSMutableArray.new;for(SINWindowController *controller in delegate.windows)if(!controller.closing)[result addObject:controller];if(![result containsObject:owner])[result addObject:owner];return result;}
static void UnusedFlush(NSArray<SINEditor *> *editors,NSUInteger index,void(^completion)(void)){if(index>=editors.count){completion();return;}[editors[index] flush:^{UnusedFlush(editors,index+1,completion);}];}
static NSArray *UnusedSnapshots(NSArray<SINWindowController *> *windows){NSMutableArray *snapshots=NSMutableArray.new;for(SINWindowController *window in windows)for(SINDocument *document in window.documents)[snapshots addObject:@{@"path":document.path?:[window.store.directory stringByAppendingPathComponent:@"Untitled.html"],@"text":document.text?:@""}];return snapshots;}
static NSDictionary *UnusedStamp(NSString *path){NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];return a?@{@"identity":UnusedIdentity(path),@"size":a[NSFileSize]?:@0,@"modified":a[NSFileModificationDate]?:NSDate.distantPast}:@{};}

@interface SINUnusedImagesController : NSObject <NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate>
@property(nonatomic,weak) SINWindowController *owner;
@property(nonatomic) NSString *folder;
@property(nonatomic) NSPanel *panel;
@property(nonatomic) NSTableView *table;
@property(nonatomic) NSTextField *status;
@property(nonatomic) NSProgressIndicator *progress;
@property(nonatomic) NSButton *trashButton;
@property(nonatomic) NSButton *rescanButton;
@property(nonatomic) NSButton *closeButton;
@property(nonatomic) NSArray<NSString *> *paths;
@property(nonatomic) NSDictionary<NSString *,NSDictionary *> *stamps;
@property(nonatomic) BOOL running;
- (void)present;
@end
@implementation SINUnusedImagesController
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {NSButton *button=[NSButton buttonWithTitle:title target:self action:action];button.frame=frame;[self.panel.contentView addSubview:button];return button;}
- (void)present {
    self.paths=@[];self.stamps=@{};self.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,860,548) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];self.panel.title=@"Unused Images";self.panel.delegate=self;self.panel.releasedWhenClosed=NO;
    self.status=[NSTextField wrappingLabelWithString:@"Scanning documents and their matching image folders…"];self.status.frame=NSMakeRect(20,481,820,47);[self.panel.contentView addSubview:self.status];
    self.progress=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20,463,820,8)];self.progress.style=NSProgressIndicatorStyleBar;self.progress.indeterminate=YES;[self.panel.contentView addSubview:self.progress];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(20,90,820,359)];scroll.hasVerticalScroller=YES;scroll.hasHorizontalScroller=YES;scroll.borderType=NSBezelBorder;self.table=[[NSTableView alloc] initWithFrame:scroll.bounds];self.table.delegate=self;self.table.dataSource=self;self.table.allowsMultipleSelection=YES;self.table.rowHeight=25;
    NSTableColumn *name=[[NSTableColumn alloc] initWithIdentifier:@"name"];name.title=@"Unused image";name.width=220;[self.table addTableColumn:name];NSTableColumn *location=[[NSTableColumn alloc] initWithIdentifier:@"location"];location.title=@"Location within scanned folder";location.width=590;[self.table addTableColumn:location];scroll.documentView=self.table;[self.panel.contentView addSubview:scroll];
    [self button:@"Select All" frame:NSMakeRect(20,48,98,28) action:@selector(selectAll:)];[self button:@"Reveal in Finder" frame:NSMakeRect(122,48,138,28) action:@selector(reveal:)];self.rescanButton=[self button:@"Rescan" frame:NSMakeRect(268,48,90,28) action:@selector(rescan:)];self.trashButton=[self button:@"Move Selected to Trash…" frame:NSMakeRect(509,48,219,28) action:@selector(trash:)];self.closeButton=[self button:@"Close" frame:NSMakeRect(740,48,100,28) action:@selector(close:)];self.closeButton.keyEquivalent=@"\e";
    NSTextField *hint=[NSTextField labelWithString:@"Open unsaved document edits are included. Select rows with Command or Shift; only image files will be moved."];hint.frame=NSMakeRect(20,17,820,21);hint.font=[NSFont systemFontOfSize:11];hint.textColor=NSColor.secondaryLabelColor;[self.panel.contentView addSubview:hint];
    [self.owner.window beginSheet:self.panel completionHandler:^(NSModalResponse response){[self.panel orderOut:nil];objc_setAssociatedObject(self.owner,UnusedPanelKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}];[self rescan:nil];
}
- (void)setBusy:(BOOL)busy {self.running=busy;self.rescanButton.enabled=!busy;self.closeButton.enabled=!busy;self.trashButton.enabled=!busy&&self.table.numberOfSelectedRows>0;if(busy)[self.progress startAnimation:nil];else[self.progress stopAnimation:nil];self.progress.hidden=!busy;}
- (void)scan:(void(^)(NSArray *,NSArray *,NSError *))completion {
    NSArray *windows=UnusedWindows(self.owner);NSMutableArray *editors=NSMutableArray.new;for(SINWindowController *window in windows)[editors addObjectsFromArray:window.editors.allValues];
    UnusedFlush(editors,0,^{NSArray *snapshots=UnusedSnapshots(windows);dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSArray *paths=SINUnusedImagePaths(self.folder,snapshots,&error);dispatch_async(dispatch_get_main_queue(),^{completion(paths,snapshots,error);});});});
}
- (void)showPaths:(NSArray *)paths {self.paths=paths?:@[];NSMutableDictionary *stamps=NSMutableDictionary.new;for(NSString *path in self.paths)stamps[path]=UnusedStamp(path);self.stamps=stamps;[self.table reloadData];[self.table deselectAll:nil];}
- (void)rescan:(id)sender {if(self.running)return;[self setBusy:YES];self.status.stringValue=@"Scanning HTML documents and matching image folders…";[self scan:^(NSArray *paths,NSArray *snapshots,NSError *error){if(error)self.status.stringValue=[@"Scan stopped: " stringByAppendingString:error.localizedDescription];else{[self showPaths:paths];self.status.stringValue=[NSString stringWithFormat:@"%lu unused images found. Review and select the files to move to the Trash. No files are selected automatically.",(unsigned long)paths.count];}[self setBusy:NO];}];}
- (NSArray<NSString *> *)selection {NSMutableArray *selected=NSMutableArray.new;[self.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index,BOOL *stop){if(index<self.paths.count)[selected addObject:self.paths[index]];}];return selected;}
- (void)selectAll:(id)sender {if(!self.running)[self.table selectAll:nil];}
- (void)reveal:(id)sender {NSArray *selected=self.selection;if(selected.count){NSMutableArray *urls=NSMutableArray.new;for(NSString *path in selected)[urls addObject:[NSURL fileURLWithPath:path]];[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:urls];}}
- (void)trash:(id)sender {
    NSArray *selected=self.selection;if(self.running||!selected.count)return;NSAlert *confirm=NSAlert.new;confirm.messageText=[NSString stringWithFormat:@"Move %lu selected images to the Trash?",(unsigned long)selected.count];confirm.informativeText=@"References and file identities will be checked again. Files that changed or became used will be skipped. Image folders are kept.";[confirm addButtonWithTitle:@"Move to Trash"];[confirm addButtonWithTitle:@"Cancel"];
    [confirm beginSheetModalForWindow:self.panel completionHandler:^(NSModalResponse response){if(response!=NSAlertFirstButtonReturn)return;[self setBusy:YES];self.status.stringValue=@"Rechecking current documents before moving images…";
        [self scan:^(NSArray *unused,NSArray *snapshots,NSError *error){if(error){self.status.stringValue=[@"Cleanup stopped: " stringByAppendingString:error.localizedDescription];[self setBusy:NO];return;}
            NSArray *windows=UnusedWindows(self.owner);NSMutableArray *editors=NSMutableArray.new;for(SINWindowController *window in windows)[editors addObjectsFromArray:window.editors.allValues];
            UnusedFlush(editors,0,^{if(![snapshots isEqual:UnusedSnapshots(windows)]){self.status.stringValue=@"Documents changed during the scan. Nothing was moved. Rescan and review the latest results.";[self setBusy:NO];return;}
                NSSet *safe=[NSSet setWithArray:unused];NSUInteger moved=0,skipped=0;NSError *failure=nil;
                // The main queue cannot accept intervening document edits between
                // this last recheck and these reversible file-only moves.
                for(NSString *path in selected){NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(![safe containsObject:path]||![self.stamps[path] isEqual:UnusedStamp(path)]||![attributes[NSFileType] isEqual:NSFileTypeRegular]){skipped++;continue;}if(![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:&failure])break;moved++;}
                NSMutableArray *remaining=unused.mutableCopy;[remaining filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path,NSDictionary *bindings){return [NSFileManager.defaultManager fileExistsAtPath:path];}]];[self showPaths:remaining];self.status.stringValue=failure?[NSString stringWithFormat:@"Moved %lu images, then stopped: %@",(unsigned long)moved,failure.localizedDescription]:[NSString stringWithFormat:@"Moved %lu images to the Trash. Skipped %lu because their files or references changed.",(unsigned long)moved,(unsigned long)skipped];for(SINWindowController *window in windows)[window.navigator refresh];[self setBusy:NO];
            });
        }];
    }];
}
- (void)close:(id)sender {if(!self.running)[self.owner.window endSheet:self.panel returnCode:NSModalResponseOK];}
- (BOOL)windowShouldClose:(NSWindow *)sender {[self close:nil];return NO;}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {return self.paths.count;}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {NSTextField *field=[tableView makeViewWithIdentifier:column.identifier owner:self];if(!field){field=[NSTextField labelWithString:@""];field.identifier=column.identifier;field.lineBreakMode=NSLineBreakByTruncatingMiddle;}NSString *path=self.paths[row];field.stringValue=[column.identifier isEqual:@"name"]?path.lastPathComponent:[path substringFromIndex:MIN(path.length,self.folder.length+1)];field.toolTip=path;return field;}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {self.trashButton.enabled=!self.running&&self.table.numberOfSelectedRows>0;}
@end

@implementation SINWindowController (UnusedImages)
- (void)scanUnusedImages {
    SINUnusedImagesController *existing=objc_getAssociatedObject(self,UnusedPanelKey);if(existing){[existing.panel makeKeyAndOrderFront:nil];return;}
    NSOpenPanel *picker=NSOpenPanel.openPanel;picker.title=@"Scan Documents for Unused Images";picker.prompt=@"Scan";picker.canChooseFiles=NO;picker.canChooseDirectories=YES;picker.allowsMultipleSelection=NO;if(self.navigator.directory.length)picker.directoryURL=[NSURL fileURLWithPath:self.navigator.directory isDirectory:YES];
    [picker beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSModalResponseOK)return;SINUnusedImagesController *controller=SINUnusedImagesController.new;controller.owner=self;controller.folder=picker.URL.path.stringByStandardizingPath;objc_setAssociatedObject(self,UnusedPanelKey,controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[controller present];}];
}
@end
#endif
