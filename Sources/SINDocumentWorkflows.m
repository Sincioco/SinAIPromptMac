#import "SINWindowController.h"
#import "SINAppDelegate.h"
#import "SINNativeServices.h"

@interface SINEditor (WorkflowReady)
- (void)afterReady:(void (^)(void))block;
@end
static void WorkflowScript(SINEditor *editor,NSString *script,void(^completion)(id,NSError *)) {
    [editor afterReady:^{[editor asyncScript:[@"await window.editor.ready();" stringByAppendingString:script] completion:completion];}];
}

static NSError *WorkflowError(NSString *message){return [NSError errorWithDomain:SINErrorDomain code:SINErrorStorage userInfo:@{NSLocalizedDescriptionKey:message}];}
static NSArray<SINWindowController *> *WorkflowWindows(SINWindowController *owner){
    NSMutableArray *windows=[((SINAppDelegate *)NSApp.delegate).windows mutableCopy]?:NSMutableArray.new;
    if(![windows containsObject:owner])[windows addObject:owner];return windows;
}
static void FlushWorkflow(NSArray<SINEditor *> *editors,NSUInteger index,void(^completion)(void)){
    if(index==editors.count){completion();return;}[editors[index] flush:^{FlushWorkflow(editors,index+1,completion);}];
}
static NSString *Timestamp(NSDate *date){NSDateFormatter *format=NSDateFormatter.new;format.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];format.dateFormat=@"yyyy-MM-dd HHmm";return [format stringFromDate:date];}
static NSString *AvailableName(NSString *stem,NSString *folder,NSArray<SINDocument *> *documents){
    NSMutableSet *names=NSMutableSet.new;for(SINDocument *doc in documents)[names addObject:doc.name.lowercaseString];
    for(NSUInteger n=1;;n++){NSString *name=[[stem stringByAppendingString:n==1?@"":[NSString stringWithFormat:@" %lu",n]] stringByAppendingPathExtension:@"html"];
        NSString *path=[folder stringByAppendingPathComponent:name];if(![names containsObject:name.lowercaseString]&&(!folder.length||(![NSFileManager.defaultManager fileExistsAtPath:path]&&![NSFileManager.defaultManager fileExistsAtPath:path.stringByDeletingPathExtension])))return name;}
}

@implementation SINWindowController (DocumentWorkflows)
- (NSArray<SINDocument *> *)visibleDocuments {
    if(![self.store.settings[@"showPrivateDocuments"] isEqual:@NO])return self.documents;
    return [self.documents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SINDocument *doc,NSDictionary *bindings){return !doc.privateDocument;}]];
}
- (void)sortDocuments {
    NSString *mode=self.store.settings[@"documentSort"]?:@"newest";
    [self.documents sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(SINDocument *a,SINDocument *b){if(a.pinned!=b.pinned)return a.pinned?NSOrderedAscending:NSOrderedDescending;return [mode isEqual:@"manual"]?NSOrderedSame:([mode isEqual:@"created"]?[b.createdDate compare:a.createdDate]:[b.modifiedDate compare:a.modifiedDate]);}];
}
- (void)refreshPrivacy {
    NSMutableSet *paths=NSMutableSet.new;
    if([self.store.settings[@"showPrivateDocuments"] isEqual:@NO])for(SINDocument *doc in self.documents)if(doc.privateDocument&&doc.path){[paths addObject:doc.path];[paths addObject:doc.path.stringByDeletingPathExtension];}
    self.navigator.hiddenPaths=paths;[self.navigator clearSelection];
    if(self.active.privateDocument&&[self.store.settings[@"showPrivateDocuments"] isEqual:@NO]){
        SINDocument *next=self.visibleDocuments.firstObject;NSError *error=nil;if(!next){next=[self.store newDocument:&error];if(next)[self.documents addObject:next];}
        if(next)[self activate:next];else [self showError:error];
    }else [self refresh];
    [self.navigator refresh];[self persist];
}
- (void)chooseEmoji:(SINDocument *)document {
    if(!document||self.saving||self.annotating)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"Choose Document Emoji";alert.informativeText=@"Choose one emoji or select a recent label. The label is stored with the document, not inside its HTML.";
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,380,76)];
    NSComboBox *input=[[NSComboBox alloc] initWithFrame:NSMakeRect(0,40,380,30)];input.font=[NSFont systemFontOfSize:22];input.stringValue=document.emoji;[input addItemsWithObjectValues:self.store.settings[@"recentEmojis"]?:@[]];[view addSubview:input];
    NSButton *palette=[NSButton buttonWithTitle:@"Open Emoji & Symbols" target:NSApp action:@selector(orderFrontCharacterPalette:)];palette.frame=NSMakeRect(0,0,210,30);[view addSubview:palette];alert.accessoryView=view;
    [alert addButtonWithTitle:@"Apply"];[alert addButtonWithTitle:@"Remove Emoji"];[alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSAlertFirstButtonReturn&&response!=NSAlertSecondButtonReturn)return;
        NSString *value=response==NSAlertSecondButtonReturn?@"":[input.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        __block NSUInteger count=0;[value enumerateSubstringsInRange:NSMakeRange(0,value.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange r,NSRange all,BOOL *stop){count++;}];
        if(value.length&&(count!=1||[value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)){[self showError:WorkflowError(@"Choose one emoji or remove the current label.")];return;}
        document.emoji=value;[self.store rememberDocumentEmoji:document oldPath:nil];
        if(value.length){NSMutableArray *recent=[self.store.settings[@"recentEmojis"] mutableCopy]?:NSMutableArray.new;[recent removeObject:value];[recent insertObject:value atIndex:0];while(recent.count>20)[recent removeLastObject];self.store.settings[@"recentEmojis"]=recent;}
        [self refresh];[self.navigator refresh];[self persist];
    }];[self.window.attachedSheet makeFirstResponder:input];
}
- (NSString *)referenceDirectory {
    NSString *folder=self.store.settings[@"explorerDirectory"];if(!folder.length)folder=self.store.settings[@"autoSaveDirectory"];return folder.length?folder:[self.store.directory stringByAppendingPathComponent:@"Reference Documents"];
}
- (SINDocument *)referenceDocument:(NSString *)name numbered:(BOOL)numbered error:(NSError **)error {
    if(![@[@"2026-09-16 1025 - AI Instructions.html",@"AI Prompt - Output Formatting.html"] containsObject:name])return nil;
    NSString *folder=[self referenceDirectory];if(![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSArray *open=[WorkflowWindows(self) valueForKeyPath:@"@unionOfArrays.documents"];
    NSString *filename=numbered?AvailableName(name.stringByDeletingPathExtension,folder,open):name;
    NSString *path=[folder stringByAppendingPathComponent:filename];
    if(![NSFileManager.defaultManager fileExistsAtPath:path]){
        NSString *source=[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:name];
        // Copy publishes without replacing an existing user-owned reference.
        if(![NSFileManager.defaultManager copyItemAtPath:source toPath:path error:error])return nil;
    }
    SINDocument *doc=[SINDocument openPath:path error:error];doc.pinned=YES;[self.store restoreDocumentMetadata:doc];return doc;
}
- (void)ensureBundledDocuments {
    for(NSString *name in @[@"2026-09-16 1025 - AI Instructions.html",@"AI Prompt - Output Formatting.html"]){
        BOOL found=NO;for(SINWindowController *window in WorkflowWindows(self))for(SINDocument *doc in window.documents)if(doc.path&&[doc.name caseInsensitiveCompare:name]==NSOrderedSame){
            found=YES;NSError *error=nil;
            if(![NSFileManager.defaultManager fileExistsAtPath:doc.path]){
                NSString *source=[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:name];
                if(![NSFileManager.defaultManager createDirectoryAtPath:doc.path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]||![NSFileManager.defaultManager copyItemAtPath:source toPath:doc.path error:&error]){
                    if(![NSFileManager.defaultManager fileExistsAtPath:doc.path])[self showError:error];
                }
            }doc.pinned=YES;
        }
        if(found)continue;NSError *error=nil;SINDocument *doc=[self referenceDocument:name numbered:NO error:&error];if(doc)[self.documents addObject:doc];else [self showError:error];
    }[self sortDocuments];[self refresh];[self persist];
}
- (void)addBundledDocument:(NSString *)name {if(self.annotating||self.saving)return;NSError *error=nil;SINDocument *doc=[self referenceDocument:name numbered:YES error:&error];if(!doc){[self showError:error];return;}[self.documents addObject:doc];[self.store addRecentPath:doc.path];self.navigator.mode=1;self.navigator.view.hidden=NO;[self sortDocuments];[self activate:doc];}
- (void)resolveFirstSave:(SINDocument *)document completion:(void (^)(NSString *,NSString *))completion {
    SINEditor *editor=self.editors[document.identifier];if(document.path||!editor){completion(nil,nil);return;}
    WorkflowScript(editor,[NSString stringWithFormat:@"return window.editor.documentTitle(%@);",SINJSON(document.text)],^(id result,NSError *error){
        if(error||![result isKindOfClass:NSString.class]||![result length]){completion(nil,nil);return;}
        NSMutableString *title=[result mutableCopy];NSCharacterSet *invalid=[NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r\t"];
        for(NSUInteger i=0;i<title.length;i++)if([invalid characterIsMember:[title characterAtIndex:i]])[title replaceCharactersInRange:NSMakeRange(i,1) withString:@"-"];
        NSArray *parts=[title componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];title=[[[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "] mutableCopy];
        while([title hasSuffix:@"."]||[title hasSuffix:@" "])[title deleteCharactersInRange:NSMakeRange(title.length-1,1)];if(!title.length){completion(nil,nil);return;}if(title.length>210)[title deleteCharactersInRange:NSMakeRange(210,title.length-210)];
        NSString *prefix=Timestamp(document.createdDate);if(document.name.length>=18&&[[document.name substringWithRange:NSMakeRange(15,3)] isEqual:@" - "])prefix=[document.name substringToIndex:15];
        NSString *folder=self.navigator.directory;BOOL directory=NO;if(![NSFileManager.defaultManager fileExistsAtPath:folder?:@"" isDirectory:&directory]||!directory)folder=self.store.settings[@"autoSaveDirectory"];
        if(![NSFileManager.defaultManager fileExistsAtPath:folder?:@"" isDirectory:&directory]||!directory)folder=nil;
        NSString *name=AvailableName([NSString stringWithFormat:@"%@ - %@",prefix,title],folder,self.documents);completion(name,folder.length?[folder stringByAppendingPathComponent:name]:nil);
    });
}
- (void)combineItems:(NSArray *)items {
    if(self.saving||self.annotating)return;if(items.count<2){[self showError:WorkflowError(@"Check at least two HTML documents. The numbers show their combination order.")];return;}
    NSMutableArray *documents=NSMutableArray.new,*editors=NSMutableArray.new;NSArray *windows=WorkflowWindows(self);
    for(id item in items){SINDocument *doc=[item isKindOfClass:SINDocument.class]?item:nil;NSError *error=nil;
        if(!doc&&[item isKindOfClass:NSString.class]&&[@[@"html",@"htm"] containsObject:[item pathExtension].lowercaseString]){for(SINWindowController *window in windows)for(SINDocument *open in window.documents)if(open.path&&SINPathsReferToSameFile(open.path,item)&&(!doc||open.modified))doc=open;if(!doc){doc=[SINDocument openPath:item error:&error];if(doc)[self.store restoreDocumentMetadata:doc];}}
        if(!doc){[self showError:error?:WorkflowError(@"Combine supports HTML documents and open drafts. Uncheck other file types.")];return;}[documents addObject:doc];for(SINWindowController *window in windows){SINEditor *editor=window.editors[doc.identifier];if(editor&&![editors containsObject:editor])[editors addObject:editor];}
    }
    self.saving=YES;FlushWorkflow(editors,0,^{
        NSMutableArray *sources=NSMutableArray.new;for(SINDocument *doc in documents)[sources addObject:@{@"html":doc.text,@"base":[NSURL fileURLWithPath:doc.path?:[self.store.directory stringByAppendingPathComponent:@"Untitled.html"]].absoluteString}];
        WorkflowScript(self.editor,[NSString stringWithFormat:@"const m=await import('./document-combine.js');return await m.combineDocuments(%@);",SINJSON(sources)],^(id result,NSError *error){
            self.saving=NO;if(error||![result isKindOfClass:NSString.class]){[self showError:error?:WorkflowError(@"The documents could not be combined.")];return;}
            NSString *folder=self.navigator.mode==0?self.navigator.directory:self.store.settings[@"autoSaveDirectory"];
            NSString *name=AvailableName([Timestamp(NSDate.date) stringByAppendingString:@" - Combined"],folder,self.documents);SINDocument *copy=SINDocument.new;copy.draftName=name;copy.text=result;
            if(folder.length&&(![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]||![copy saveToPath:[folder stringByAppendingPathComponent:name] overwriteConflict:NO error:&error])){[self showError:error];return;}copy.autosave=copy.path!=nil;
            for(SINDocument *doc in documents)if(!doc.emoji.length){doc.emoji=@"❌";[self.store rememberDocumentEmoji:doc oldPath:nil];}
            [self.documents addObject:copy];[self.navigator clearSelection];[self sortDocuments];[self activate:copy];
        });
    });
}
- (void)deleteItems:(NSArray *)items {
    if(self.saving||self.annotating||!items.count)return;
    NSMutableArray *paths=NSMutableArray.new,*drafts=NSMutableArray.new;
    for(id item in items){SINDocument *doc=[item isKindOfClass:SINDocument.class]?item:nil;NSString *path=doc?doc.path:([item isKindOfClass:NSString.class]?item:nil);if(doc&&!path){[drafts addObject:doc];continue;}BOOL directory=NO;if(path&&[NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]&&directory){if(items.count==1)[self trashPath:path];else [self showError:WorkflowError(@"Select files, not folders, for batch deletion.")];return;}if(path&&![paths containsObject:path])[paths addObject:path];}
    NSArray *windows=WorkflowWindows(self);NSMutableArray *editors=NSMutableArray.new;for(SINWindowController *window in windows){if(window.saving||window.annotating||window.window.attachedSheet){[self showError:WorkflowError(@"Finish the current file operation, image annotation or dialog before deleting files.")];return;}[editors addObjectsFromArray:window.editors.allValues];}
    for(SINWindowController *window in windows)window.saving=YES;
    void(^finish)(NSError *)=^(NSError *error){for(SINWindowController *window in windows){window.saving=NO;[window.navigator refresh];[window refresh];[window persist];}if(error)[self showError:error];};
    FlushWorkflow(editors,0,^{NSAlert *alert=NSAlert.new;alert.messageText=[NSString stringWithFormat:@"Delete %lu selected item%@?",paths.count+drafts.count,paths.count+drafts.count==1?@"":@"s"];
        alert.informativeText=@"Saved files move to the Trash. Selected unsaved documents close. Any unsaved changes to these files will be discarded.";[alert addButtonWithTitle:@"Delete"];[alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSAlertFirstButtonReturn){finish(nil);return;}
            NSError *error=nil;for(NSString *path in paths){NSMutableArray *matches=NSMutableArray.new;for(SINWindowController *window in windows)for(SINDocument *doc in window.documents)if(doc.path&&SINPathsReferToSameFile(doc.path,path))[matches addObject:@{@"window":window,@"document":doc}];
                if(![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:&error]){finish(error);return;}
                for(SINWindowController *window in windows)[window.navigator removeCheckedItems:@[path]];for(NSDictionary *match in matches){SINWindowController *window=match[@"window"];SINDocument *doc=match[@"document"];[window.navigator removeCheckedItems:@[doc]];[window removeOpenDocument:doc];}
                NSMutableArray *recent=[self.store.settings[@"recent"] mutableCopy];[recent removeObject:path];self.store.settings[@"recent"]=recent?:@[];
            }for(SINDocument *doc in drafts)if([self.documents containsObject:doc]&&!doc.path){[self.navigator removeCheckedItems:@[doc]];[self removeOpenDocument:doc];}finish(nil);
        }];
    });
}
- (void)importMarkdown:(NSString *)path completion:(void (^)(SINDocument *,NSError *))completion {
    NSError *error=nil;NSString *markdown=[NSString stringWithContentsOfFile:path usedEncoding:NULL error:&error];if(!markdown){completion(nil,error);return;}
    NSString *folder=[self.store.directory stringByAppendingPathComponent:@"Markdown Imports"];
    if(![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]){completion(nil,error);return;}
    NSString *stem=[path.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@" - Converted"];
    NSString *base=[NSURL fileURLWithPath:path].absoluteString;
    WorkflowScript(self.editor,[NSString stringWithFormat:@"const m=await import('./markdown.js');return m.markdownDocument(%@,%@);",SINJSON(markdown),SINJSON(base)],^(id result,NSError *failure){
        if(failure||![result isKindOfClass:NSString.class]){completion(nil,failure?:WorkflowError(@"Markdown conversion failed."));return;}
        SINDocument *doc=SINDocument.new;doc.text=result;NSError *saveError=nil;
        for(NSUInteger number=1;;number++){NSString *name=[[stem stringByAppendingString:number==1?@"":[NSString stringWithFormat:@" (%lu)",number]] stringByAppendingPathExtension:@"html"];NSString *destination=[folder stringByAppendingPathComponent:name];if([NSFileManager.defaultManager fileExistsAtPath:destination])continue;
            if([doc saveToPath:destination overwriteConflict:NO error:&saveError])break;
            if([NSFileManager.defaultManager fileExistsAtPath:destination])continue;completion(nil,saveError);return;
        }doc.autosave=YES;completion(doc,nil);
    });
}
@end
