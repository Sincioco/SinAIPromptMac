#import "SINNavigator.h"
#import "SINDocument.h"
#import "SINProjects.h"
extern NSArray<NSString *> *SINUnusedImagePaths(NSString *,NSArray<NSDictionary *> *,NSError **);
@interface SINOutlineView : NSOutlineView
@property(nonatomic,copy) void(^keyAction)(NSString *);
@end
@implementation SINOutlineView
- (NSMenu *)menuForEvent:(NSEvent *)event {
    if(event.type==NSEventTypeRightMouseDown||(event.type==NSEventTypeLeftMouseDown&&(event.modifierFlags&NSEventModifierFlagControl))){
        NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];if([self rowAtPoint:point]<0)return nil;
    }
    return [super menuForEvent:event];
}
- (void)keyDown:(NSEvent *)event {
    if(event.keyCode==96){if(self.keyAction)self.keyAction(@"refresh");return;}
    if(event.keyCode==120){if(self.keyAction)self.keyAction(@"rename");return;}
    if(event.keyCode==51||event.keyCode==117){if(self.keyAction)self.keyAction(@"trash");return;}
    [super keyDown:event];
}
@end
@interface SINNavigatorCell : NSTableCellView
@property(nonatomic,strong) NSButton *selectionBox;
@end
@implementation SINNavigatorCell
- (void)layout {
    [super layout];
    CGFloat offset=self.selectionBox.hidden?0:38;self.selectionBox.frame=NSMakeRect(0,3,36,23);
    self.imageView.frame=NSMakeRect(offset+2,5,18,18);
    self.textField.frame=NSMakeRect(offset+26,5,MAX(0,self.bounds.size.width-offset-30),20);
}
@end
@interface SINNavigator ()
@property(nonatomic,strong) NSMutableDictionary *children;
@property(nonatomic,strong) NSMutableDictionary *loadedChildren;
@property(nonatomic,strong) NSSegmentedControl *modeControl;
@property(nonatomic,strong) NSButton *foldersButton;
@property(nonatomic) BOOL updating;
@property(nonatomic,strong) NSMutableArray *documentSelection;
@property(nonatomic,strong) NSMutableArray *explorerSelection;
@property(nonatomic,strong) NSSearchField *filterInput;
@property(nonatomic,strong) NSMutableDictionary *unusedFolders;
@property(nonatomic,strong) NSMutableDictionary *unusedRequests;
@property(nonatomic,strong) NSMutableSet *unusedPending;
@property(nonatomic) NSUInteger unusedGeneration;
@end
@implementation SINNavigator
- (instancetype)init {if((self=[super initWithNibName:nil bundle:nil])){_children=NSMutableDictionary.new;_loadedChildren=NSMutableDictionary.new;_documents=@[];_headings=@[];_showFolders=YES;_sortMode=@"manual";_filterText=@"";_documentSelection=NSMutableArray.new;_explorerSelection=NSMutableArray.new;_unusedFolders=NSMutableDictionary.new;_unusedRequests=NSMutableDictionary.new;_unusedPending=NSMutableSet.new;}return self;}
- (void)loadView {
    self.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,250,600)];
    self.modeControl=[NSSegmentedControl segmentedControlWithLabels:@[@"Explorer",@"Documents"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeMode:)];
    self.modeControl.frame=NSMakeRect(8,563,234,26);self.modeControl.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;self.modeControl.selectedSegment=self.contentsOnly?-1:MIN(1,MAX(0,self.mode));[self.view addSubview:self.modeControl];
    NSButton *folder=[NSButton buttonWithTitle:@"Choose Folder…" target:self action:@selector(chooseFolder:)];folder.frame=NSMakeRect(8,528,140,28);folder.autoresizingMask=NSViewMinYMargin;[self.view addSubview:folder];
    NSButton *new=[NSButton buttonWithTitle:@"+" target:self action:@selector(newDocument:)];new.frame=NSMakeRect(208,528,34,28);new.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;[self.view addSubview:new];
    self.foldersButton=[NSButton checkboxWithTitle:@"Show folders" target:self action:@selector(toggleFolders:)];self.foldersButton.state=self.showFolders?NSControlStateValueOn:NSControlStateValueOff;self.foldersButton.frame=NSMakeRect(10,499,160,24);self.foldersButton.autoresizingMask=NSViewMinYMargin;[self.view addSubview:self.foldersButton];
    self.filterInput=[[NSSearchField alloc] initWithFrame:NSMakeRect(8,468,234,26)];self.filterInput.placeholderString=@"Filter filenames";self.filterInput.target=self;self.filterInput.action=@selector(filterChanged:);self.filterInput.delegate=self;self.filterInput.sendsSearchStringImmediately=YES;self.filterInput.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;[self.view addSubview:self.filterInput];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,250,460)];scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;scroll.hasVerticalScroller=YES;
    self.outline=[[SINOutlineView alloc] initWithFrame:scroll.bounds];__weak typeof(self) weakSelf=self;((SINOutlineView*)self.outline).keyAction=^(NSString *command){
        SINNavigator *owner=weakSelf;if([command isEqual:@"refresh"]){[owner refresh];return;}
        if(owner.outline.selectedRow<0)return;id item=[owner.outline itemAtRow:owner.outline.selectedRow];
        NSString *action=[command isEqual:@"trash"]?([owner selectionIncludingItem:item].count>1?@"deleteSelection":([item isKindOfClass:NSString.class]?@"trashPath":@"trash")):([item isKindOfClass:NSString.class]?[command stringByAppendingString:@"Path"]:command);
        for(NSMenuItem *entry in [owner contextMenuForItem:item].itemArray)if(entry.enabled&&[entry.representedObject[@"command"] isEqual:action]){[NSApp sendAction:entry.action to:entry.target from:entry];break;}
    };NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"name"];column.width=240;column.minWidth=40;column.resizingMask=NSTableColumnAutoresizingMask;[self.outline addTableColumn:column];self.outline.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;self.outline.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.outline.outlineTableColumn=column;self.outline.headerView=nil;self.outline.rowHeight=29;self.outline.style=NSTableViewStyleSourceList;
    self.outline.delegate=self;self.outline.dataSource=self;self.outline.target=self;self.outline.doubleAction=@selector(doubleClick:);self.outline.autosaveExpandedItems=NO;
    [self.outline registerForDraggedTypes:@[@"com.sin.aiprompt.document",NSPasteboardTypeFileURL]];
    NSMenu *menu=NSMenu.new;menu.delegate=self;self.outline.menu=menu;scroll.documentView=self.outline;[self.view addSubview:scroll];
    if(self.contentsOnly){for(NSView *view in self.view.subviews)if(view!=scroll)view.hidden=YES;scroll.frame=self.view.bounds;self.mode=2;}
}
- (void)viewDidLayout {[super viewDidLayout];[self.outline sizeLastColumnToFit];}
- (void)setHiddenPaths:(NSSet<NSString *> *)paths {NSMutableSet *resolved=NSMutableSet.new;for(NSString *path in paths)[resolved addObject:path.stringByStandardizingPath.stringByResolvingSymlinksInPath];_hiddenPaths=resolved.copy;}
- (BOOL)isHiddenPath:(NSString *)path {if(!self.hiddenPaths.count)return NO;NSString *resolved=path.stringByStandardizingPath.stringByResolvingSymlinksInPath;for(NSString *hidden in self.hiddenPaths)if([resolved isEqual:hidden]||[resolved hasPrefix:[hidden stringByAppendingString:@"/"]]||SINPathsReferToSameFile(resolved,hidden))return YES;return NO;}
- (BOOL)loadedPathMatchesFilter:(NSString *)path {
    if([self isHiddenPath:path])return NO;
    if(![NSFileManager.defaultManager fileExistsAtPath:path])return NO;
    if([path.lastPathComponent localizedCaseInsensitiveContainsString:self.filterText])return YES;
    for(NSString *child in self.loadedChildren[path])if([self loadedPathMatchesFilter:child])return YES;
    return NO;
}
- (NSArray *)filteredPaths:(NSArray *)paths parent:(NSString *)parent {
    if(!self.filterText.length)return paths;
    // Keep children of a matching loaded ancestor, including HTML asset folders.
    for(NSString *ancestor=parent;ancestor.length&&![ancestor isEqual:self.directory];ancestor=ancestor.stringByDeletingLastPathComponent){
        if([ancestor.lastPathComponent localizedCaseInsensitiveContainsString:self.filterText])return paths;
        for(NSString *ext in @[@"html",@"htm"]){NSString *html=[ancestor stringByAppendingPathExtension:ext];if([NSFileManager.defaultManager fileExistsAtPath:html]&&[html.lastPathComponent localizedCaseInsensitiveContainsString:self.filterText])return paths;}
        if([ancestor isEqual:ancestor.stringByDeletingLastPathComponent])break;
    }
    return [paths filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path,NSDictionary *bindings){return [self loadedPathMatchesFilter:path];}]];
}
- (NSArray *)items:(id)item {
    if(self.mode==1)return item?@[]:[self.documents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SINDocument *doc,NSDictionary *bindings){return !self.filterText.length||[doc.name localizedCaseInsensitiveContainsString:self.filterText];}]];
    if(self.mode==2)return item?@[]:self.headings;
    NSString *path=item?:self.directory;if(!path.length)return @[];
    if(self.children[path])return [self filteredPaths:self.children[path] parent:path];
    if([@[@"html",@"htm"] containsObject:path.pathExtension.lowercaseString]){NSString *folder=path.stringByDeletingPathExtension;BOOL directory=NO;NSArray *values=[NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&directory]&&directory?@[folder]:@[];self.children[path]=values;self.loadedChildren[path]=values;return [self filteredPaths:values parent:path];}
    NSArray<NSURL*> *urls=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey,NSURLCreationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *values=NSMutableArray.new;
    for(NSURL *url in urls){NSNumber *isDirectory,*isLink;[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];[url getResourceValue:&isLink forKey:NSURLIsSymbolicLinkKey error:nil];if(isLink.boolValue)continue;
        if([self isHiddenPath:url.path])continue;
        if(isDirectory.boolValue){BOOL companion=NO;for(NSString *extension in @[@"html",@"htm"])if([NSFileManager.defaultManager fileExistsAtPath:[url.path stringByAppendingPathExtension:extension]])companion=YES;if(self.showFolders&&!companion)[values addObject:url.path];}
        else if([@[@"html",@"htm",@"txt",@"md",@"png",@"jpg",@"jpeg",@"gif",@"pdf"] containsObject:url.pathExtension.lowercaseString])[values addObject:url.path];
    }
    [values sortUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
        if([self.sortMode isEqual:@"manual"]){NSUInteger ai=[self.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.path isEqual:a];}],bi=[self.documents indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.path isEqual:b];}];if(ai!=bi)return ai<bi?NSOrderedAscending:NSOrderedDescending;}
        NSString *key=[self.sortMode isEqual:@"created"]?NSFileCreationDate:NSFileModificationDate;NSDate *ad=[NSFileManager.defaultManager attributesOfItemAtPath:a error:nil][key],*bd=[NSFileManager.defaultManager attributesOfItemAtPath:b error:nil][key];return [bd compare:ad]?:[a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];self.children[path]=values;self.loadedChildren[path]=values;return [self filteredPaths:values parent:path];
}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item{return[self items:item].count;}
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item{return[self items:item][index];}
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item {if(self.mode!=0||![item isKindOfClass:NSString.class])return NO;BOOL directory=NO;[NSFileManager.defaultManager fileExistsAtPath:item isDirectory:&directory];if(directory)return YES;if([@[@"html",@"htm"] containsObject:[item pathExtension].lowercaseString])[NSFileManager.defaultManager fileExistsAtPath:[item stringByDeletingPathExtension] isDirectory:&directory];return directory;}
- (BOOL)unusedImage:(NSString*)path {
    if(![@[@"png",@"jpg",@"jpeg",@"gif"] containsObject:path.pathExtension.lowercaseString])return NO;
    NSString *folder=path.stringByDeletingLastPathComponent;
    NSUInteger generation=self.unusedGeneration;
    if(![self.unusedRequests[folder] isEqual:@(generation)]&&![self.unusedPending containsObject:folder]){
        [self.unusedPending addObject:folder];self.unusedRequests[folder]=@(generation);NSMutableArray *snapshots=NSMutableArray.new;for(SINDocument *doc in self.allDocuments?:self.documents)if(doc.path)[snapshots addObject:@{@"path":doc.path,@"text":doc.text}];NSArray *snapshot=snapshots.copy;__weak typeof(self) weakSelf=self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;NSArray *unused=SINUnusedImagePaths(folder,snapshot,&error);NSSet *result=[NSSet setWithArray:error?@[]:(unused?:@[])];
            dispatch_async(dispatch_get_main_queue(),^{SINNavigator *owner=weakSelf;if(!owner)return;[owner.unusedPending removeObject:folder];if(owner.unusedGeneration==generation)owner.unusedFolders[folder]=result;NSMutableIndexSet *rows=NSMutableIndexSet.new;for(NSInteger row=0;row<owner.outline.numberOfRows;row++){id item=[owner.outline itemAtRow:row];if([item isKindOfClass:NSString.class]&&[[item stringByDeletingLastPathComponent] isEqual:folder])[rows addIndex:row];}if(rows.count)[owner.outline reloadDataForRowIndexes:rows columnIndexes:[NSIndexSet indexSetWithIndex:0]];});
        });
    }
    return [self.unusedFolders[folder] containsObject:path];
}
- (NSView *)outlineView:(NSOutlineView *)view viewForTableColumn:(NSTableColumn *)column item:(id)item {
    NSTableCellView *cell=[view makeViewWithIdentifier:@"item" owner:self];
    if(!cell){cell=[[SINNavigatorCell alloc] initWithFrame:NSMakeRect(0,0,column.width,29)];cell.identifier=@"item";NSImageView *icon=[[NSImageView alloc] initWithFrame:NSMakeRect(2,5,18,18)];cell.imageView=icon;[cell addSubview:icon];NSTextField *text=[NSTextField labelWithString:@""];text.frame=NSMakeRect(26,5,MAX(0,column.width-30),20);text.autoresizingMask=NSViewWidthSizable;text.lineBreakMode=NSLineBreakByTruncatingMiddle;cell.textField=text;[cell addSubview:text];NSButton *box=[NSButton checkboxWithTitle:@"" target:self action:@selector(toggleChecked:)];((SINNavigatorCell *)cell).selectionBox=box;[cell addSubview:box];}
    cell.objectValue=item;NSButton *box=((SINNavigatorCell *)cell).selectionBox;BOOL folder=NO;if([item isKindOfClass:NSString.class])[NSFileManager.defaultManager fileExistsAtPath:item isDirectory:&folder];box.hidden=!self.multiSelection||self.mode==2||folder;NSUInteger selected=[self.checkedItems indexOfObject:item];box.state=selected==NSNotFound?NSControlStateValueOff:NSControlStateValueOn;box.title=selected==NSNotFound?@"":[NSString stringWithFormat:@"%lu",selected+1];
    cell.textField.textColor=NSColor.labelColor;
    if([item isKindOfClass:SINDocument.class]){SINDocument *doc=item;cell.textField.stringValue=[NSString stringWithFormat:@"%@%@%@%@%@",doc.emoji.length?[doc.emoji stringByAppendingString:@" "]:@"",doc.pinned?@"📌 ":@"",doc.readOnly?@"🔒 ":@"",doc.name,doc.modified?@" *":@""];cell.imageView.image=[NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil];cell.toolTip=doc.path;}
    else if([item isKindOfClass:NSDictionary.class]){cell.textField.stringValue=[[@"" stringByPaddingToLength:[item[@"level"] integerValue]*2 withString:@" " startingAtIndex:0] stringByAppendingString:item[@"text"]?:@""];cell.imageView.image=nil;}
    else{NSString *emoji=self.emojis[item];cell.textField.stringValue=[NSString stringWithFormat:@"%@%@",emoji.length?[emoji stringByAppendingString:@" "]:@"",[item lastPathComponent]];cell.imageView.image=[NSWorkspace.sharedWorkspace iconForFile:item];cell.toolTip=item;if([self unusedImage:item])cell.textField.textColor=NSColor.systemRedColor;}
    NSString *path=[item isKindOfClass:SINDocument.class]?[item path]:([item isKindOfClass:NSString.class]?item:nil);NSString *suffix=[SINProjects displaySuffixForDocumentPath:path];if(suffix.length){NSMutableAttributedString *title=[[NSMutableAttributedString alloc] initWithString:cell.textField.stringValue];[title appendAttributedString:[[NSAttributedString alloc] initWithString:suffix attributes:@{NSForegroundColorAttributeName:NSColor.secondaryLabelColor}]];cell.textField.attributedStringValue=title;}
    [cell setNeedsLayout:YES];
    return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)note {if(self.updating||self.outline.selectedRow<0)return;id item=[self.outline itemAtRow:self.outline.selectedRow];BOOL folder=NO;if([item isKindOfClass:NSString.class])[NSFileManager.defaultManager fileExistsAtPath:item isDirectory:&folder];if(!folder&&self.selected)self.selected(item);}
- (void)changeMode:(id)sender {self.mode=self.modeControl.selectedSegment;[self refresh];if(self.action)self.action(@"navigationMode",@(self.mode));}
- (void)setMode:(NSInteger)mode {_mode=self.contentsOnly?2:MIN(1,MAX(0,mode));self.modeControl.selectedSegment=self.contentsOnly?-1:_mode;}
- (void)setDirectory:(NSString *)directory {NSString *resolved=directory.stringByStandardizingPath.stringByResolvingSymlinksInPath;if(![_directory isEqual:resolved]){_directory=[resolved copy];[self.children removeAllObjects];[self.loadedChildren removeAllObjects];[self.unusedFolders removeAllObjects];self.unusedGeneration++;}}
- (void)toggleFolders:(id)sender {self.showFolders=self.foldersButton.state==NSControlStateValueOn;[self refresh];if(self.action)self.action(@"showFolders",@(self.showFolders));}
- (void)chooseFolder:(id)sender {if(self.action)self.action(@"chooseFolder",nil);}
- (void)newDocument:(id)sender {if(self.action)self.action(@"new",nil);}
- (id)loadedItemEqualTo:(id)item {for(NSInteger row=0;row<self.outline.numberOfRows;row++){id loaded=[self.outline itemAtRow:row];if([loaded isEqual:item])return loaded;}return nil;}
- (void)doubleClick:(id)sender {id item=[self.outline itemAtRow:self.outline.clickedRow];if([item isKindOfClass:NSString.class]&&[@[@"html",@"htm"] containsObject:[item pathExtension].lowercaseString]){[self.outline expandItem:item];id folder=[self loadedItemEqualTo:[item stringByDeletingPathExtension]];if(folder){[self.outline expandItem:folder];NSInteger row=[self.outline rowForItem:folder];if(row>=0)[self.outline scrollRowToVisible:row];}}}
- (void)refresh {
    if(!self.isViewLoaded)return;NSMutableArray *expanded=NSMutableArray.new;
    id selected=self.outline.selectedRow>=0?[self.outline itemAtRow:self.outline.selectedRow]:nil;
    for(NSInteger i=0;i<self.outline.numberOfRows;i++){id item=[self.outline itemAtRow:i];if([item isKindOfClass:NSString.class]&&[self.outline isItemExpanded:item])[expanded addObject:item];}
    [self.children removeAllObjects];self.unusedGeneration++;self.updating=YES;[self.outline reloadData];
    for(NSString *path in expanded){id loaded=[self loadedItemEqualTo:path];if(loaded)[self.outline expandItem:loaded];}
    if(selected){id loaded=[self loadedItemEqualTo:selected];NSInteger row=loaded?[self.outline rowForItem:loaded]:-1;if(row>=0)[self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];}
    self.updating=NO;
}
- (void)selectDocument:(SINDocument *)document {if(self.mode!=1)return;NSInteger row=[self.outline rowForItem:document];if(row>=0){self.updating=YES;[self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];self.updating=NO;}}
- (NSArray *)checkedItems {return [((self.mode==0)?self.explorerSelection:self.documentSelection) copy];}
- (void)setMultiSelection:(BOOL)value {_multiSelection=value;if(!value){[self.documentSelection removeAllObjects];[self.explorerSelection removeAllObjects];}[self refresh];}
- (void)clearSelection {[self.documentSelection removeAllObjects];[self.explorerSelection removeAllObjects];[self refresh];}
- (void)removeCheckedItems:(NSArray *)items {[self.documentSelection removeObjectsInArray:items];[self.explorerSelection removeObjectsInArray:items];}
- (NSArray *)selectionIncludingItem:(id)item {NSArray *selection=[item isKindOfClass:SINDocument.class]?self.documentSelection:self.explorerSelection;return self.multiSelection&&[selection containsObject:item]?selection.copy:(item?@[item]:@[]);}
- (BOOL)isItemChecked:(id)item {return self.multiSelection&&[([item isKindOfClass:SINDocument.class]?self.documentSelection:self.explorerSelection) containsObject:item];}
- (void)toggleChecked:(NSButton *)sender {id item=((NSTableCellView *)sender.superview).objectValue;NSMutableArray *selection=self.mode==0?self.explorerSelection:self.documentSelection;if(sender.state==NSControlStateValueOn){if(![selection containsObject:item])[selection addObject:item];}else [selection removeObject:item];[self.outline reloadData];}
- (void)filterChanged:(id)sender {[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyFilter) object:nil];[self performSelector:@selector(applyFilter) withObject:nil afterDelay:.25];}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if(control!=self.filterInput||command!=@selector(cancelOperation:))return NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyFilter) object:nil];self.filterInput.stringValue=@"";[self applyFilter];[self.view.window makeFirstResponder:self.outline];return YES;
}
- (void)applyFilter {self.filterText=[self.filterInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[self refresh];self.filterInput.toolTip=self.outline.numberOfRows?[NSString stringWithFormat:@"%ld matching items",self.outline.numberOfRows]:@"No matching files";}
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];NSInteger row=self.outline.clickedRow>=0?self.outline.clickedRow:self.outline.selectedRow;if(row<0)return;id item=[self.outline itemAtRow:row];
    NSMenu *built=[self contextMenuForItem:item];menu.autoenablesItems=NO;
    for(NSMenuItem *entry in built.itemArray.copy){[built removeItem:entry];[menu addItem:entry];}
}
- (NSMenu *)contextMenuForItem:(id)item {
    if([item isKindOfClass:SINDocument.class])return self.documentMenu?self.documentMenu(item):NSMenu.new;
    NSMenu *menu=NSMenu.new;menu.autoenablesItems=NO;
    if(![item isKindOfClass:NSString.class])return menu;
    NSString *path=item;BOOL directory=NO;BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory];
    BOOL imageFolder=NO;
    if(directory)for(NSString *extension in @[@"html",@"htm"]){BOOL folder=NO;if([NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathExtension:extension] isDirectory:&folder]&&!folder){imageFolder=YES;break;}}
    BOOL available=exists&&(!self.contextActionsEnabled||self.contextActionsEnabled());
    void(^add)(NSString *,NSString *,NSString *)=^(NSString *title,NSString *command,NSString *key){
        NSMenuItem *entry=[[NSMenuItem alloc] initWithTitle:title action:@selector(contextAction:) keyEquivalent:key];entry.keyEquivalentModifierMask=0;
        entry.target=self;entry.enabled=available;entry.representedObject=@{@"command":command,@"item":path};[menu addItem:entry];
    };
    if(!directory&&[@[@"html",@"htm",@"png",@"jpg",@"jpeg",@"gif"] containsObject:path.pathExtension.lowercaseString])add(@"Rename…",@"renamePath",[NSString stringWithFormat:@"%C",(unichar)NSF2FunctionKey]);
    NSArray *selection=[self selectionIncludingItem:item];if(selection.count>1)add(@"Combine Selected Documents…",@"combineSelection",@"");
    if([@[@"html",@"htm"] containsObject:path.pathExtension.lowercaseString]&&self.projectMenu)[menu addItem:self.projectMenu(selection)];
    if(!directory||imageFolder)add(selection.count>1?@"Delete Selected Files…":@"Delete to Trash…",selection.count>1?@"deleteSelection":@"trashPath",[NSString stringWithFormat:@"%C",(unichar)NSDeleteCharacter]);
    if(menu.numberOfItems)[menu addItem:NSMenuItem.separatorItem];
    add(@"Show in Finder",@"revealPath",@"");add(@"Open Containing Folder",@"openFolderPath",@"");
    return menu;
}
- (void)contextAction:(NSMenuItem *)item {if(item.enabled&&self.action)self.action(item.representedObject[@"command"],item.representedObject[@"item"]);}
- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)view pasteboardWriterForItem:(id)item {if(![item isKindOfClass:SINDocument.class])return nil;NSPasteboardItem *pb=NSPasteboardItem.new;[pb setString:[item identifier] forType:@"com.sin.aiprompt.document"];return pb;}
- (NSDragOperation)outlineView:(NSOutlineView*)view validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {if([info.draggingPasteboard.types containsObject:NSPasteboardTypeFileURL])return NSDragOperationCopy;return self.mode==1&&!item?NSDragOperationMove:NSDragOperationNone;}
- (BOOL)outlineView:(NSOutlineView*)view acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
    NSArray<NSURL*> *urls=[info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];if(urls.count){if(self.action)self.action(@"openDropped",[urls valueForKey:@"path"]);return YES;}
    NSString *identifier=[info.draggingPasteboard stringForType:@"com.sin.aiprompt.document"];NSMutableArray *docs=self.documents.mutableCopy;NSUInteger from=[docs indexOfObjectPassingTest:^BOOL(SINDocument *d,NSUInteger i,BOOL *stop){return[d.identifier isEqual:identifier];}];if(from==NSNotFound)return NO;
    SINDocument *doc=docs[from];[docs removeObjectAtIndex:from];if(index>(NSInteger)from)index--;[docs insertObject:doc atIndex:MIN(MAX(index,0),(NSInteger)docs.count)];self.documents=docs;[self refresh];if(self.reordered)self.reordered(docs);return YES;
}
@end
