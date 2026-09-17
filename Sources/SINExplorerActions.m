#import "SINWindowController.h"
#import "SINNativeServices.h"

static NSError *ExplorerError(NSString *message) { return [NSError errorWithDomain:SINErrorDomain code:SINErrorStorage userInfo:@{NSLocalizedDescriptionKey:message}]; }
static NSArray<SINWindowController *> *Controllers(SINWindowController *owner) {
    NSMutableArray *result = [NSMutableArray arrayWithObject:owner];
    for (NSWindow *window in NSApp.windows) if ([window.windowController isKindOfClass:SINWindowController.class] && window.windowController != owner) [result addObject:window.windowController];
    return result;
}
static NSString *ParentHTML(NSString *imagePath, BOOL folder) {
    NSString *directory = folder ? imagePath : imagePath.stringByDeletingLastPathComponent;
    while (directory.length > 1) {
        for (NSString *extension in @[@"html",@"htm"]) {
            NSString *candidate = [directory stringByAppendingPathExtension:extension];
            BOOL isDirectory = NO;
            if ([NSFileManager.defaultManager fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) return candidate;
        }
        if (folder) break;
        directory = directory.stringByDeletingLastPathComponent;
    }
    return nil;
}
static void FlushEditors(NSArray<SINEditor *> *editors, NSUInteger index, void (^done)(void)) {
    if (index == editors.count) { done(); return; }
    [editors[index] flush:^{ FlushEditors(editors,index+1,done); }];
}

@implementation SINWindowController (ExplorerActions)
- (void)renameImageAtPath:(NSString *)path {
    if (self.saving) return;
    if (![@[@"png",@"jpg",@"jpeg",@"gif",@"webp",@"tiff",@"tif",@"heic",@"bmp",@"svg"] containsObject:path.pathExtension.lowercaseString]) { [self showError:ExplorerError(@"Only image files can use image rename.")]; return; }
    NSAlert *alert = NSAlert.new; alert.messageText = @"Rename image";
    alert.informativeText = @"The extension is preserved. The parent HTML and its open documents will be updated together.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,360,26)]; field.stringValue = path.lastPathComponent.stringByDeletingPathExtension; alert.accessoryView = field;
    [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSString *name = field.stringValue;
        if (!name.length || ![name.lastPathComponent isEqual:name] || [name containsString:@":"] || [name isEqual:@"."] || [name isEqual:@".."]) { [self showError:ExplorerError(@"Enter an image name without a folder path or colon.")]; return; }
        NSString *destination = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:[name stringByAppendingPathExtension:path.pathExtension]];
        if ([path isEqual:destination]) return;
        BOOL caseOnly=[path caseInsensitiveCompare:destination]==NSOrderedSame && SINPathsReferToSameFile(path,destination);
        if ([NSFileManager.defaultManager fileExistsAtPath:destination] && !caseOnly) { [self showError:ExplorerError(@"An image with that name already exists.")]; return; }
        NSString *parent = ParentHTML(path,NO);
        NSArray<SINWindowController *> *windows = Controllers(self);
        for (SINWindowController *window in windows) if (window.saving) { [self showError:ExplorerError(@"Wait for the current save to finish, then rename the image.")]; return; }
        NSMutableArray<SINDocument *> *documents = [NSMutableArray array];
        NSMutableArray<SINEditor *> *editors = [NSMutableArray array];
        for (SINWindowController *window in windows) {
            window.saving = YES;
            for (SINDocument *document in window.documents) if ([document.path isEqual:parent]) {
                [documents addObject:document]; SINEditor *editor = window.editors[document.identifier]; if (editor && ![editors containsObject:editor]) [editors addObject:editor];
            }
        }
        SINEditor *parser = self.editor;
        if (parser && ![editors containsObject:parser]) [editors addObject:parser];
        void (^finish)(NSError *) = ^(NSError *error) { for (SINWindowController *window in windows) { window.saving = NO; [window refresh]; [window persist]; } if (error) [self showError:error]; };
        FlushEditors(editors,0,^{
            NSError *error = nil;
            if (!parent) { BOOL moved = SINMoveFilePreservingCase(path,destination,&error); finish(moved ? nil : error); return; }
            SINDocument *disk = [SINDocument openPath:parent error:&error];
            if (!disk) { finish(error); return; }
            for (SINDocument *document in documents) if (document.fingerprint && ![document.fingerprint isEqual:disk.fingerprint]) { finish(ExplorerError(@"The parent HTML changed outside Sin AI Prompt. Reload it before renaming this image.")); return; }
            if (!parser) { finish(ExplorerError(@"Open an HTML document before renaming this image.")); return; }
            NSMutableArray *texts = [NSMutableArray arrayWithObject:disk.text];
            for (SINDocument *document in documents) { [texts addObject:document.text]; [texts addObject:document.savedText]; }
            NSNumber *caseSensitive=nil;
            [[NSURL fileURLWithPath:path] getResourceValue:&caseSensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:NULL];
            NSString *script = [NSString stringWithFormat:@"return %@.map(html=>window.editor.renameImageFile(html,%@,%@,%@,%@));", SINJSON(texts), SINJSON([NSURL fileURLWithPath:parent].absoluteString), SINJSON([NSURL fileURLWithPath:path].absoluteString), SINJSON([NSURL fileURLWithPath:destination].absoluteString), SINJSON(caseSensitive ?: @YES)];
            [parser asyncScript:script completion:^(id result, NSError *rewriteError) {
                if (rewriteError || ![result isKindOfClass:NSArray.class] || [result count] != texts.count) { finish(rewriteError ?: ExplorerError(@"Could not update the image references.")); return; }
                for (NSUInteger index=0; index<documents.count; index++) if (![documents[index].text isEqual:texts[1+index*2]]) { finish(ExplorerError(@"The document changed while preparing the rename. Try again.")); return; }
                if ([disk changedOnDisk:NULL]) { finish(ExplorerError(@"The parent HTML changed while preparing the rename. Try again.")); return; }
                NSError *commitError = nil;
                if (!SINMoveFilePreservingCase(path,destination,&commitError)) { finish(commitError); return; }
                disk.text = result[0];
                if (![disk saveToPath:parent overwriteConflict:NO error:&commitError]) {
                    NSError *rollbackError = nil;
                    if (!SINMoveFilePreservingCase(destination,path,&rollbackError)) commitError = ExplorerError([NSString stringWithFormat:@"%@ The image could not be moved back: %@", commitError.localizedDescription, rollbackError.localizedDescription]);
                    finish(commitError); return;
                }
                for (NSUInteger index=0; index<documents.count; index++) {
                    SINDocument *document = documents[index]; document.text = result[1+index*2]; document.savedText = result[2+index*2]; document.fingerprint = disk.fingerprint; document.modifiedDate = disk.modifiedDate;
                    for (SINWindowController *window in windows) { SINEditor *editor = window.editors[document.identifier]; if (editor.showingSource) editor.sourceView.string = document.text; [editor reload]; }
                }
                finish(nil);
            }];
        });
    }];
}
- (void)trashPath:(NSString *)path {
    if (self.saving || !path.length) return;
    NSFileManager *fm = NSFileManager.defaultManager; BOOL directory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&directory]) { [self showError:ExplorerError(@"This file no longer exists.")]; return; }
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:NULL];
    if ([attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) { [self showError:ExplorerError(@"Filesystem links cannot be deleted from Prompt Explorer.")]; return; }
    NSString *parent = directory ? ParentHTML(path,YES) : nil;
    if (directory && !parent) { [self showError:ExplorerError(@"Only a matching HTML image folder can be deleted from Prompt Explorer.")]; return; }
    NSArray<SINWindowController *> *windows = Controllers(self);
    NSMutableArray<SINEditor *> *editors = [NSMutableArray array];
    for (SINWindowController *window in windows) { if (window.saving) { [self showError:ExplorerError(@"Wait for the current save to finish, then try again.")]; return; } [editors addObjectsFromArray:window.editors.allValues]; }
    for (SINWindowController *window in windows) window.saving = YES;
    void (^finish)(NSError *) = ^(NSError *error) { for (SINWindowController *window in windows) { window.saving = NO; [window refresh]; [window persist]; } if (error) [self showError:error]; };
    FlushEditors(editors,0,^{
        NSMutableArray<NSDictionary *> *snapshots = [NSMutableArray array];
        BOOL parentOpen = NO, unsaved = NO;
        for (SINWindowController *window in windows) for (SINDocument *document in window.documents) {
            [snapshots addObject:@{@"text":document.text,@"path":document.path ?: @"/unsaved.html"}];
            if ([document.path isEqual:parent]) parentOpen = YES;
            if ([document.path isEqual:path] && document.modified) unsaved = YES;
        }
        if (directory && !parentOpen) {
            NSError *error = nil; SINDocument *disk = [SINDocument openPath:parent error:&error];
            if (!disk) { finish(error); return; }
            [snapshots addObject:@{@"text":disk.text,@"path":parent}];
        }
        NSError *referenceError=nil;
        if (directory && SINFolderContainsReferencedFiles(path,snapshots,&referenceError)) { finish(referenceError ?: ExplorerError(@"This folder still contains a file referenced by its parent HTML or an open document. Remove those references before deleting it.")); return; }
        NSAlert *alert = NSAlert.new;
        alert.messageText = [NSString stringWithFormat:@"Move %@ to the Trash?", path.lastPathComponent];
        alert.informativeText = unsaved ? @"This file has unsaved edits. Its open documents will close and those edits will be discarded after the file moves to the Trash." : @"You can restore the item from the macOS Trash.";
        [alert addButtonWithTitle:@"Move to Trash"]; [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSAlertFirstButtonReturn) { finish(nil); return; }
            FlushEditors(editors,0,^{
            NSError *error = nil;
            // Other windows can change while the confirmation sheet is open.
            // Recheck fresh buffers immediately before recycling a folder.
            if (directory) {
                NSMutableArray *latest = [NSMutableArray array]; BOOL latestParentOpen = NO;
                for (SINWindowController *window in windows) for (SINDocument *document in window.documents) {
                    [latest addObject:@{@"text":document.text,@"path":document.path ?: @"/unsaved.html"}];
                    if ([document.path isEqual:parent]) latestParentOpen = YES;
                }
                if (!latestParentOpen) {
                    SINDocument *disk = [SINDocument openPath:parent error:&error];
                    if (!disk) { finish(error); return; }
                    [latest addObject:@{@"text":disk.text,@"path":parent}];
                }
                if (SINFolderContainsReferencedFiles(path,latest,&error)) { finish(error ?: ExplorerError(@"This folder is now referenced by a document. Its files have not been deleted.")); return; }
            }
            if (![fm trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:&error]) { finish(error); return; }
            for (SINWindowController *window in windows) {
                BOOL activeRemoved = NO;
                for (SINDocument *document in window.documents.copy) if ([document.path isEqual:path]) {
                    SINEditor *editor = window.editors[document.identifier]; [editor.view removeFromSuperview]; [editor invalidate]; [window.editors removeObjectForKey:document.identifier]; [window.documents removeObject:document];
                    if (window.active == document) { window.active = nil; activeRemoved = YES; }
                }
                if (!window.documents.count) { SINDocument *replacement = [window.store newDocument:&error]; if (replacement) [window.documents addObject:replacement]; }
                if (activeRemoved && window.documents.count) [window activate:window.documents.firstObject];
            }
            finish(error);
            });
        }];
    });
}
@end
