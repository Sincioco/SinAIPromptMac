#import "SINWindowController.h"

@implementation SINWindowController (ContextMenus)
- (NSMenu *)documentContextMenu:(SINDocument *)document {
    NSMenu *menu=NSMenu.new;menu.autoenablesItems=NO;
    if(!document||![self.documents containsObject:document])return menu;
    BOOL hasPath=document.path.length>0,isDirectory=NO;
    BOOL exists=hasPath&&[NSFileManager.defaultManager fileExistsAtPath:document.path isDirectory:&isDirectory]&&!isDirectory;
    BOOL available=!self.annotating&&!self.saving&&!self.window.attachedSheet;
    void(^add)(NSString *,NSString *,BOOL,BOOL)=^(NSString *title,NSString *command,BOOL needsPath,BOOL needsFile){
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:@selector(contextDocumentAction:) keyEquivalent:@""];
        item.target=self;item.representedObject=@{@"command":command,@"item":document};
        item.enabled=available&&(!needsPath||hasPath)&&(!needsFile||exists);
        item.toolTip=!hasPath&&needsPath?@"Save this document first.":(needsFile&&!exists?@"The file is no longer at this path.":document.path);
        [menu addItem:item];
    };
    add(@"Rename…",@"rename",NO,hasPath);
    add(@"Duplicate",@"duplicate",NO,NO);
    add(document.pinned?@"Unpin":@"Pin To Top",@"pin",NO,NO);
    add(document.readOnly?@"Unlock Document":@"Lock Document",document.readOnly?@"unlock":@"lock",NO,NO);
    add(@"Delete…",@"trash",YES,YES);
    [menu addItem:NSMenuItem.separatorItem];
    add(@"Copy Full Path",@"copyPath",YES,NO);
    add(@"Copy for AI Use",@"copyAI",NO,NO);
    add(@"Open Containing Folder",@"openFolder",YES,NO);
    [menu addItem:NSMenuItem.separatorItem];
    add(@"Revert To Last Saved…",@"revert",YES,YES);
    add(@"Close",@"close",NO,NO);
    menu.itemArray.lastObject.keyEquivalent=@"w";
    menu.itemArray.lastObject.keyEquivalentModifierMask=NSEventModifierFlagCommand;
    return menu;
}
- (void)contextDocumentAction:(NSMenuItem *)sender {
    if(!sender.enabled)return;
    SINDocument *document=sender.representedObject[@"item"];
    if(![self.documents containsObject:document])return;
    [self navigateAction:sender.representedObject[@"command"] item:document];
}
@end
