#import "SINAppDelegate.h"
#import "SINWindowController.h"
@implementation SINAppDelegate
- (NSMenuItem *)add:(NSMenu *)menu title:(NSString *)title command:(NSString *)command key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:@selector(menuAction:) keyEquivalent:key];item.target=self;item.representedObject=command;item.keyEquivalentModifierMask=modifiers;[menu addItem:item];return item;
}
- (NSMenu *)submenu:(NSMenu *)parent title:(NSString *)title {NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];NSMenu *menu=[[NSMenu alloc] initWithTitle:title];item.submenu=menu;[parent addItem:item];return menu;}
- (void)buildMenu {
    NSEventModifierFlags cmd=NSEventModifierFlagCommand,shift=cmd|NSEventModifierFlagShift,option=cmd|NSEventModifierFlagOption;
    NSMenu *bar=NSMenu.new;NSApp.mainMenu=bar;
    NSMenu *app=[self submenu:bar title:@"Sin AI Prompt"];
    [self add:app title:@"About Sin — AI Prompt" command:@"about" key:@"" modifiers:0];[app addItem:NSMenuItem.separatorItem];
    [self add:app title:@"Settings…" command:@"settings" key:@"," modifiers:cmd];[app addItem:NSMenuItem.separatorItem];
    NSMenuItem *hide=[[NSMenuItem alloc] initWithTitle:@"Hide Sin — AI Prompt" action:@selector(hide:) keyEquivalent:@"h"];[app addItem:hide];
    [self add:app title:@"Quit Sin — AI Prompt" command:@"quit" key:@"q" modifiers:cmd];
    NSMenu *file=[self submenu:bar title:@"File"];
    [self add:file title:@"New" command:@"new" key:@"n" modifiers:cmd];[self add:file title:@"New Window" command:@"newWindow" key:@"n" modifiers:shift];[self add:file title:@"Open…" command:@"open" key:@"o" modifiers:cmd];
    NSMenu *recent=[self submenu:file title:@"Open Recent"];recent.delegate=self;[file addItem:NSMenuItem.separatorItem];
    [self add:file title:@"Save" command:@"save" key:@"s" modifiers:cmd];[self add:file title:@"Save As…" command:@"saveAs" key:@"s" modifiers:shift];[self add:file title:@"Save All" command:@"saveAll" key:@"s" modifiers:option];
    [self add:file title:@"Scan for Unused Images…" command:@"scanUnused" key:@"" modifiers:0];
    [self add:file title:@"Rename…" command:@"rename" key:@"" modifiers:0];[self add:file title:@"Duplicate" command:@"duplicate" key:@"" modifiers:0];
    [self add:file title:@"Export as Markdown…" command:@"exportMarkdown" key:@"" modifiers:0];[self add:file title:@"Export as Standalone HTML…" command:@"exportHTML" key:@"" modifiers:0];[file addItem:NSMenuItem.separatorItem];
    [self add:file title:@"Close Document" command:@"close" key:@"w" modifiers:cmd];[self add:file title:@"Close Window" command:@"closeWindow" key:@"w" modifiers:shift];
    NSMenu *edit=[self submenu:bar title:@"Edit"];
    NSArray *edits=@[@[@"Undo",@"undo",@"z"],@[@"Redo",@"redo",@"z"],@[@"Cut",@"cut",@"x"],@[@"Copy",@"copy",@"c"],@[@"Paste",@"paste",@"v"],@[@"Select All",@"selectAll",@"a"]];
    for(NSArray *entry in edits)[self add:edit title:entry[0] command:entry[1] key:entry[2] modifiers:[entry[1] isEqual:@"redo"]?shift:cmd];[edit addItem:NSMenuItem.separatorItem];
    [self add:edit title:@"Find…" command:@"find" key:@"f" modifiers:cmd];[self add:edit title:@"Replace…" command:@"replace" key:@"f" modifiers:option];[self add:edit title:@"Find Next" command:@"findNext" key:@"g" modifiers:cmd];[self add:edit title:@"Find Previous" command:@"findPrevious" key:@"g" modifiers:shift];[self add:edit title:@"Go to Line…" command:@"goTo" key:@"l" modifiers:option];
    NSMenu *date=[self submenu:edit title:@"Date / Time"];
    [self add:date title:@"Short Date and Time" command:@"date" key:[NSString stringWithFormat:@"%C",(unichar)NSF5FunctionKey] modifiers:0];[self add:date title:@"Long Date and Time" command:@"longDate" key:@"d" modifiers:cmd];
    for(NSString *format in @[@"EEEE, MMMM d, yyyy 'at' h:mm a",@"M/d/yyyy",@"M/d/yyyy h:mm a",@"yyyyMMddHHmm",@"yyyy-MM-dd HHmm",@"yyyy-MM-dd' - 'HHmm"])[self add:date title:format command:[@"dateFormat:" stringByAppendingString:format] key:@"" modifiers:0];
    [self add:edit title:@"Insert Separator (80 Underscores)" command:@"separator" key:@"l" modifiers:cmd];[self add:edit title:@"Insert Date / Time and Separator" command:@"dateSeparator" key:@"" modifiers:0];
    NSMenu *format=[self submenu:bar title:@"Format"];
    [self add:format title:@"Bold" command:@"bold" key:@"b" modifiers:cmd];[self add:format title:@"Italic" command:@"italic" key:@"i" modifiers:cmd];[self add:format title:@"Underline" command:@"underline" key:@"u" modifiers:cmd];
    [self add:format title:@"Text Encoding…" command:@"encoding" key:@"" modifiers:0];[self add:format title:@"Toggle LF / CRLF" command:@"newline" key:@"" modifiers:0];
    NSMenu *view=[self submenu:bar title:@"View"];
    [self add:view title:@"Visual Editor / HTML Source" command:@"source" key:@"u" modifiers:shift];[self add:view title:@"Navigation Pane" command:@"documentList" key:@"l" modifiers:shift];[self add:view title:@"Content View" command:@"contentView" key:@"" modifiers:0];
    for(NSArray *entry in @[@[@"Tab Bar",@"tabBar"],@[@"Status Bar",@"statusBar"],@[@"Source Line Numbers",@"lineNumbers"],@[@"Source Word Wrap",@"wordWrap"],@[@"Formatting Toolbar",@"showToolbar"],@[@"Wrap Toolbar / Ribbon",@"wrapToolbar"]])[self add:view title:entry[0] command:entry[1] key:@"" modifiers:0];
    NSMenu *sort=[self submenu:view title:@"Sort Documents"];for(NSArray *entry in @[@[@"Newest First",@"newest"],@[@"Date Created",@"created"],@[@"Manual Order",@"manual"]])[self add:sort title:entry[0] command:[@"sort:" stringByAppendingString:entry[1]] key:@"" modifiers:0];
    [view addItem:NSMenuItem.separatorItem];[self add:view title:@"Zoom In" command:@"zoomIn" key:@"+" modifiers:cmd];[self add:view title:@"Zoom Out" command:@"zoomOut" key:@"-" modifiers:cmd];[self add:view title:@"Actual Size" command:@"zoomReset" key:@"0" modifiers:cmd];[self add:view title:@"Refresh Explorer" command:@"refresh" key:[NSString stringWithFormat:@"%C",(unichar)NSF5FunctionKey] modifiers:cmd];
    NSMenu *window=[self submenu:bar title:@"Window"];NSApp.windowsMenu=window;[self add:window title:@"Next Document" command:@"next" key:@"]" modifiers:shift];[self add:window title:@"Previous Document" command:@"previous" key:@"[" modifiers:shift];[self add:window title:@"Minimize" command:@"minimize" key:@"m" modifiers:cmd];
    NSMenu *help=[self submenu:bar title:@"Help"];[self add:help title:@"Mac Feature Parity" command:@"help" key:@"" modifiers:0];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.windows=NSMutableArray.new;NSArray *args=NSProcessInfo.processInfo.arguments;self.selfTest=[args containsObject:@"--self-test"];
    NSString *directory=SINStore.defaultDirectory;NSUInteger index=[args indexOfObject:@"--data-dir"];if(index!=NSNotFound&&index+1<args.count)directory=args[index+1];
    else {NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"data-location.json"]];NSDictionary *location=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if([location[@"directory"] isKindOfClass:NSString.class])directory=location[@"directory"];else if([NSUserDefaults.standardUserDefaults stringForKey:@"SinAIPromptDataDirectory"].length)directory=[NSUserDefaults.standardUserDefaults stringForKey:@"SinAIPromptDataDirectory"];}
    if(self.selfTest)directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SinAIPrompt-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *error=nil;self.store=[[SINStore alloc] initWithDirectory:directory error:&error];if(!self.store){[[NSAlert alertWithError:error] runModal];[NSApp terminate:nil];return;}
    [self buildMenu];
    NSArray *savedGroups=[self.store.settings[@"sessionWindows"] copy]?:@[];
    NSArray *restored=self.selfTest?@[]:[self.store restoreDocuments:&error];
    if(error)NSLog(@"Recovery: %@",error.localizedDescription);
    SINWindowController *controller=nil;
    if(savedGroups.count&&restored.count){
        NSMutableSet *assigned=NSMutableSet.new;
        for(NSDictionary *group in savedGroups){NSMutableArray *members=NSMutableArray.new;for(NSString *identifier in group[@"documents"])for(SINDocument *doc in restored)if([doc.identifier isEqual:identifier]&&![assigned containsObject:identifier]){[members addObject:doc];[assigned addObject:identifier];}
            if(!members.count)continue;SINWindowController *window=[[SINWindowController alloc] initWithStore:self.store documents:members activeIdentifier:group[@"active"]];[self.windows addObject:window];if([group[@"frame"] isKindOfClass:NSString.class]){NSRect frame=NSRectFromString(group[@"frame"]);BOOL visible=NO;for(NSScreen *screen in NSScreen.screens)if(NSIntersectsRect(screen.visibleFrame,frame))visible=YES;if(visible)[window.window setFrame:frame display:NO];}[window showWindow:nil];if(!controller)controller=window;
        }
        for(SINDocument *doc in restored)if(![assigned containsObject:doc.identifier])[controller.documents addObject:doc];
    }
    if(!controller){controller=[[SINWindowController alloc] initWithStore:self.store documents:restored activeIdentifier:self.store.activeIdentifier];[self.windows addObject:controller];[controller showWindow:nil];}
    controller.testMode=self.selfTest;[NSApp activateIgnoringOtherApps:YES];
    if(self.selfTest){[controller runSelfTests];return;}
    NSMutableArray *paths=NSMutableArray.new;for(NSUInteger i=1;i<args.count;i++){if([args[i] isEqual:@"--data-dir"]){i++;continue;}if(![args[i] hasPrefix:@"-"]&&[NSFileManager.defaultManager fileExistsAtPath:args[i]])[paths addObject:args[i]];}[controller openPaths:paths];
}
- (SINWindowController *)current {for(SINWindowController *controller in self.windows)if(controller.window==NSApp.keyWindow||controller.window==NSApp.mainWindow)return controller;return self.windows.lastObject;}
- (void)menuAction:(NSMenuItem *)sender {
    NSString *command=sender.representedObject;SINWindowController *controller=self.current;
    if([command isEqual:@"quit"]){[NSApp terminate:nil];return;}
    if([command isEqual:@"about"]){[NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionApplicationName:@"Sin — AI Prompt for Mac",NSAboutPanelOptionApplicationVersion:@"1.0",NSAboutPanelOptionCredits:[[NSAttributedString alloc] initWithString:@"Objective-C + AppKit + WKWebView\nBased on Sincioco/SinAIPrompt\nNo third-party runtime dependencies"]}];return;}
    if([command isEqual:@"newWindow"]){SINWindowController *next=[[SINWindowController alloc] initWithStore:self.store restore:NO];[self.windows addObject:next];[next showWindow:nil];return;}
    if([command isEqual:@"closeWindow"]){[controller.window performClose:nil];return;}
    if([command isEqual:@"minimize"]){[controller.window miniaturize:nil];return;}
    if([command isEqual:@"help"]){[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"PARITY.md"]]];return;}
    if([command hasPrefix:@"recent:"]){[controller openPaths:@[[command substringFromIndex:7]]];return;}
    // Text fields in native sheets and source view must keep standard editing behavior.
    NSDictionary *actions=@{@"cut":@"cut:",@"copy":@"copy:",@"paste":@"paste:",@"selectAll":@"selectAll:",@"undo":@"undo:",@"redo":@"redo:"};
    NSResponder *responder=NSApp.keyWindow.firstResponder;
    if(actions[command]&&[responder isKindOfClass:NSTextView.class]){[NSApp sendAction:NSSelectorFromString(actions[command]) to:nil from:sender];return;}
    if([command hasPrefix:@"dateFormat:"]){NSDateFormatter *formatter=NSDateFormatter.new;formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];formatter.AMSymbol=@"am";formatter.PMSymbol=@"pm";formatter.dateFormat=[command substringFromIndex:11];NSArray *formats=@[@"EEEE, MMMM d, yyyy 'at' h:mm a",@"M/d/yyyy",@"M/d/yyyy h:mm a",@"yyyyMMddHHmm",@"yyyy-MM-dd HHmm",@"yyyy-MM-dd' - 'HHmm"];NSUInteger index=[formats indexOfObject:formatter.dateFormat];if(index!=NSNotFound)self.store.settings[@"dateTimeFormat"]=@(index);[controller.editor editCommand:@"insertText" value:[formatter stringFromDate:NSDate.date]];return;}
    if(controller.annotating&&actions[command]){[controller.editor editCommand:command value:nil];return;}
    if([command isEqual:@"date"]&&responder==controller.navigator.outline)command=@"refresh";
    [controller handleCommand:command];
}
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];NSArray *paths=self.store.settings[@"recent"]?:@[];
    for(NSString *path in paths)[self add:menu title:path.lastPathComponent command:[@"recent:" stringByAppendingString:path] key:@"" modifiers:0];
    if(!paths.count){NSMenuItem *empty=[[NSMenuItem alloc] initWithTitle:@"No Recent Documents" action:nil keyEquivalent:@""];[menu addItem:empty];}
}
- (void)application:(NSApplication *)app openFiles:(NSArray<NSString*>*)filenames {if(!self.windows.count){[app replyToOpenOrPrint:NSApplicationDelegateReplyFailure];return;}[self.current openPaths:filenames];[app replyToOpenOrPrint:NSApplicationDelegateReplySuccess];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {if(!visible){SINWindowController *window=self.current;if(window.closing){[self.windows removeAllObjects];window=[[SINWindowController alloc] initWithStore:self.store restore:YES];[self.windows addObject:window];}[window showWindow:nil];}return YES;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if(self.selfTest)return NSTerminateNow;
    SINWindowController *current=self.current;
    [self prepareWindows:self.windows.copy index:0 completion:^(BOOL ready){
        if(!ready){[NSApp replyToApplicationShouldTerminate:NO];return;}
        [self flushWindows:self.windows.copy index:0 completion:^{
            [current persist];if(current.recoveryError){[current showError:current.recoveryError];[NSApp replyToApplicationShouldTerminate:NO];}else [NSApp replyToApplicationShouldTerminate:YES];
        }];
    }];return NSTerminateLater;
}
- (void)prepareWindows:(NSArray<SINWindowController*>*)windows index:(NSUInteger)index completion:(void(^)(BOOL))completion {
    if(index>=windows.count){completion(YES);return;}SINWindowController *window=windows[index];
    if(window.closing){[self prepareWindows:windows index:index+1 completion:completion];return;}
    [window prepareToClose:^(BOOL ready){if(ready)[self prepareWindows:windows index:index+1 completion:completion];else completion(NO);}];
}
- (void)flushWindows:(NSArray<SINWindowController*>*)windows index:(NSUInteger)index completion:(void(^)(void))completion {
    if(index>=windows.count){completion();return;}SINWindowController *window=windows[index];
    if(window.closing||!window.editor){[self flushWindows:windows index:index+1 completion:completion];return;}
    [window.editor flush:^{[self flushWindows:windows index:index+1 completion:completion];}];
}
@end
