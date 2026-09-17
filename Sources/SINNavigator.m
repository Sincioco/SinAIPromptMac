#import "SINNavigator.h"
#import "SINDocument.h"
@interface SINOutlineView : NSOutlineView
@property(nonatomic,copy) void(^keyAction)(NSString *);
@end
@implementation SINOutlineView
- (void)keyDown:(NSEvent *)event {
    if(event.keyCode==96){if(self.keyAction)self.keyAction(@"refresh");return;}
    if(event.keyCode==120){if(self.keyAction)self.keyAction(@"rename");return;}
    if(event.keyCode==51||event.keyCode==117){if(self.keyAction)self.keyAction(@"trash");return;}
    [super keyDown:event];
}
@end
@interface SINNavigator ()
@property(nonatomic,strong) NSMutableDictionary *children;
@property(nonatomic,strong) NSSegmentedControl *modeControl;
@property(nonatomic,strong) NSButton *foldersButton;
@property(nonatomic) BOOL updating;
@end
@implementation SINNavigator
- (instancetype)init {if((self=[super initWithNibName:nil bundle:nil])){_children=NSMutableDictionary.new;_documents=@[];_headings=@[];_showFolders=YES;_sortMode=@"manual";}return self;}
- (void)loadView {
    self.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,250,600)];
    self.modeControl=[NSSegmentedControl segmentedControlWithLabels:@[@"Explorer",@"Documents",@"Contents"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeMode:)];
    self.modeControl.frame=NSMakeRect(8,563,234,26);self.modeControl.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;self.modeControl.selectedSegment=self.mode;[self.view addSubview:self.modeControl];
    NSButton *folder=[NSButton buttonWithTitle:@"Choose Folder…" target:self action:@selector(chooseFolder:)];folder.frame=NSMakeRect(8,528,140,28);folder.autoresizingMask=NSViewMinYMargin;[self.view addSubview:folder];
    NSButton *new=[NSButton buttonWithTitle:@"+" target:self action:@selector(newDocument:)];new.frame=NSMakeRect(208,528,34,28);new.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;[self.view addSubview:new];
    self.foldersButton=[NSButton checkboxWithTitle:@"Show folders" target:self action:@selector(toggleFolders:)];self.foldersButton.state=self.showFolders?NSControlStateValueOn:NSControlStateValueOff;self.foldersButton.frame=NSMakeRect(10,499,160,24);self.foldersButton.autoresizingMask=NSViewMinYMargin;[self.view addSubview:self.foldersButton];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,250,492)];scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;scroll.hasVerticalScroller=YES;
    self.outline=[[SINOutlineView alloc] initWithFrame:scroll.bounds];__weak typeof(self) weakSelf=self;((SINOutlineView*)self.outline).keyAction=^(NSString *command){SINNavigator *owner=weakSelf;if([command isEqual:@"refresh"]){[owner refresh];return;}id item=[owner.outline itemAtRow:owner.outline.selectedRow];if(!item||[item isKindOfClass:NSDictionary.class])return;if(owner.action)owner.action([item isKindOfClass:NSString.class]?[command stringByAppendingString:@"Path"]:command,item);};NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"name"];column.width=240;[self.outline addTableColumn:column];self.outline.outlineTableColumn=column;self.outline.headerView=nil;self.outline.rowHeight=29;self.outline.style=NSTableViewStyleSourceList;
    self.outline.delegate=self;self.outline.dataSource=self;self.outline.target=self;self.outline.doubleAction=@selector(doubleClick:);self.outline.autosaveExpandedItems=NO;
    [self.outline registerForDraggedTypes:@[@"com.sin.aiprompt.document",NSPasteboardTypeFileURL]];
    NSMenu *menu=NSMenu.new;menu.delegate=self;self.outline.menu=menu;scroll.documentView=self.outline;[self.view addSubview:scroll];
}
- (NSArray *)items:(id)item {
    if(self.mode==1)return item?@[]:self.documents;
    if(self.mode==2)return item?@[]:self.headings;
    NSString *path=item?:self.directory;if(!path.length)return @[];
    if(self.children[path])return self.children[path];
    NSArray<NSURL*> *urls=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey,NSURLCreationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *values=NSMutableArray.new;
    for(NSURL *url in urls){NSNumber *isDirectory,*isLink;[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];[url getResourceValue:&isLink forKey:NSURLIsSymbolicLinkKey error:nil];if(isLink.boolValue)continue;
        if(isDirectory.boolValue){if(self.showFolders)[values addObject:url.path];}
        else if([@[@"html",@"htm",@"txt",@"md",@"png",@"jpg",@"jpeg",@"gif",@"pdf"] containsObject:url.pathExtension.lowercaseString])[values addObject:url.path];
    }
    [values sortUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
        if([self.sortMode isEqual:@"manual"]){NSUInteger ai=[self.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.path isEqual:a];}],bi=[self.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.path isEqual:b];}];if(ai!=bi)return ai<bi?NSOrderedAscending:NSOrderedDescending;}
        NSString *key=[self.sortMode isEqual:@"created"]?NSFileCreationDate:NSFileModificationDate;NSDate *ad=[NSFileManager.defaultManager attributesOfItemAtPath:a error:nil][key],*bd=[NSFileManager.defaultManager attributesOfItemAtPath:b error:nil][key];return [bd compare:ad]?:[a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];self.children[path]=values;return values;
}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item{return[self items:item].count;}
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item{return[self items:item][index];}
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item {if(self.mode!=0||![item isKindOfClass:NSString.class])return NO;BOOL directory=NO;[NSFileManager.defaultManager fileExistsAtPath:item isDirectory:&directory];return directory;}
- (BOOL)unusedImage:(NSString*)path {
    if(![@[@"png",@"jpg",@"jpeg",@"gif"] containsObject:path.pathExtension.lowercaseString])return NO;
    NSString *parent=[path.stringByDeletingLastPathComponent stringByAppendingPathExtension:@"html"];
    NSString *html=nil;for(SINDocument *doc in self.documents)if([doc.path isEqual:parent]){html=doc.text;break;}
    if(!html)html=[NSString stringWithContentsOfFile:parent encoding:NSUTF8StringEncoding error:nil];if(!html)return NO;
    NSString *name=path.lastPathComponent;NSString *escaped=[name stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    return [html rangeOfString:name options:NSCaseInsensitiveSearch].location==NSNotFound&&[html rangeOfString:escaped options:NSCaseInsensitiveSearch].location==NSNotFound;
}
- (NSView *)outlineView:(NSOutlineView *)view viewForTableColumn:(NSTableColumn *)column item:(id)item {
    NSTableCellView *cell=[view makeViewWithIdentifier:@"item" owner:self];
    if(!cell){cell=[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,230,29)];cell.identifier=@"item";NSImageView *icon=[[NSImageView alloc] initWithFrame:NSMakeRect(2,5,18,18)];cell.imageView=icon;[cell addSubview:icon];NSTextField *text=[NSTextField labelWithString:@""];text.frame=NSMakeRect(26,5,198,20);text.autoresizingMask=NSViewWidthSizable;text.lineBreakMode=NSLineBreakByTruncatingMiddle;cell.textField=text;[cell addSubview:text];}
    cell.textField.textColor=NSColor.labelColor;
    if([item isKindOfClass:SINDocument.class]){SINDocument *doc=item;cell.textField.stringValue=[NSString stringWithFormat:@"%@%@%@",doc.readOnly?@"🔒 ":@"",doc.name,doc.modified?@" *":@""];cell.imageView.image=[NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil];cell.toolTip=doc.path;}
    else if([item isKindOfClass:NSDictionary.class]){cell.textField.stringValue=[[@"" stringByPaddingToLength:[item[@"level"] integerValue]*2 withString:@" " startingAtIndex:0] stringByAppendingString:item[@"text"]?:@""];cell.imageView.image=nil;}
    else{cell.textField.stringValue=[item lastPathComponent];cell.imageView.image=[NSWorkspace.sharedWorkspace iconForFile:item];cell.toolTip=item;if([self unusedImage:item])cell.textField.textColor=NSColor.systemRedColor;}
    return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)note {if(self.updating||self.outline.selectedRow<0)return;id item=[self.outline itemAtRow:self.outline.selectedRow];if(![self outlineView:self.outline isItemExpandable:item]&&self.selected)self.selected(item);}
- (void)changeMode:(id)sender {self.mode=self.modeControl.selectedSegment;[self refresh];if(self.action)self.action(@"navigationMode",@(self.mode));}
- (void)setMode:(NSInteger)mode {_mode=mode;self.modeControl.selectedSegment=mode;}
- (void)toggleFolders:(id)sender {self.showFolders=self.foldersButton.state==NSControlStateValueOn;[self refresh];if(self.action)self.action(@"showFolders",@(self.showFolders));}
- (void)chooseFolder:(id)sender {if(self.action)self.action(@"chooseFolder",nil);}
- (void)newDocument:(id)sender {if(self.action)self.action(@"new",nil);}
- (void)doubleClick:(id)sender {id item=[self.outline itemAtRow:self.outline.clickedRow];if([item isKindOfClass:NSString.class]&&[@[@"html",@"htm"] containsObject:[item pathExtension].lowercaseString]){NSString *folder=[item stringByDeletingPathExtension];[self.outline expandItem:folder];NSInteger row=[self.outline rowForItem:folder];if(row>=0)[self.outline scrollRowToVisible:row];}}
- (void)refresh {
    if(!self.isViewLoaded)return;NSMutableArray *expanded=NSMutableArray.new;
    id selected=self.outline.selectedRow>=0?[self.outline itemAtRow:self.outline.selectedRow]:nil;
    for(NSInteger i=0;i<self.outline.numberOfRows;i++){id item=[self.outline itemAtRow:i];if([item isKindOfClass:NSString.class]&&[self.outline isItemExpanded:item])[expanded addObject:item];}
    [self.children removeAllObjects];self.updating=YES;[self.outline reloadData];
    for(NSString *path in expanded)[self.outline expandItem:path];
    if(selected){NSInteger row=[self.outline rowForItem:selected];if(row>=0)[self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];}
    self.updating=NO;
}
- (void)selectDocument:(SINDocument *)document {if(self.mode!=1)return;NSInteger row=[self.documents indexOfObject:document];if(row!=NSNotFound){self.updating=YES;[self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];self.updating=NO;}}
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];NSInteger row=self.outline.clickedRow>=0?self.outline.clickedRow:self.outline.selectedRow;if(row<0)return;id item=[self.outline itemAtRow:row];
    NSArray *entries=[item isKindOfClass:SINDocument.class]?@[@[@"Pin / Unpin",@"pin"],@[@"Rename…",@"rename"],@[@"Duplicate",@"duplicate"],@[@"Close",@"close"],@[@"Copy Full Path",@"copyPath"],@[@"Show in Finder",@"reveal"],@[@"Open Containing Folder",@"openFolder"],@[@"Move to Trash…",@"trash"]]:@[@[@"Rename…",@"renamePath"],@[@"Show in Finder",@"revealPath"],@[@"Open Containing Folder",@"openFolderPath"],@[@"Move to Trash…",@"trashPath"]];
    if([item isKindOfClass:NSDictionary.class])return;
    for(NSArray *entry in entries){NSMenuItem *mi=[[NSMenuItem alloc] initWithTitle:entry[0] action:@selector(contextAction:) keyEquivalent:@""];mi.target=self;mi.representedObject=@{@"command":entry[1],@"item":item};[menu addItem:mi];}
}
- (void)contextAction:(NSMenuItem *)item {if(self.action)self.action(item.representedObject[@"command"],item.representedObject[@"item"]);}
- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)view pasteboardWriterForItem:(id)item {if(![item isKindOfClass:SINDocument.class])return nil;NSPasteboardItem *pb=NSPasteboardItem.new;[pb setString:[item identifier] forType:@"com.sin.aiprompt.document"];return pb;}
- (NSDragOperation)outlineView:(NSOutlineView*)view validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {if([info.draggingPasteboard.types containsObject:NSPasteboardTypeFileURL])return NSDragOperationCopy;return self.mode==1&&!item?NSDragOperationMove:NSDragOperationNone;}
- (BOOL)outlineView:(NSOutlineView*)view acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
    NSArray<NSURL*> *urls=[info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];if(urls.count){if(self.action)self.action(@"openDropped",[urls valueForKey:@"path"]);return YES;}
    NSString *identifier=[info.draggingPasteboard stringForType:@"com.sin.aiprompt.document"];NSMutableArray *docs=self.documents.mutableCopy;NSUInteger from=[docs indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.identifier isEqual:identifier];}];if(from==NSNotFound)return NO;
    SINDocument *doc=docs[from];[docs removeObjectAtIndex:from];if(index>(NSInteger)from)index--;[docs insertObject:doc atIndex:MIN(MAX(index,0),(NSInteger)docs.count)];self.documents=docs;[self refresh];if(self.reordered)self.reordered(docs);return YES;
}
@end
