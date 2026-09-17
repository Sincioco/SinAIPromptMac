#import "SINWindowController.h"
#import "SINNativeServices.h"
#import "SINAppDelegate.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSError *FileActionError(NSString *message) { return [NSError errorWithDomain:SINErrorDomain code:SINErrorStorage userInfo:@{NSLocalizedDescriptionKey:message}]; }

@interface SINWindowController (FileActionsPrivate)
- (void)finishSavingDocument:(SINDocument *)document editor:(SINEditor *)editor completion:(void (^)(BOOL))completion;
- (void)resolveSaveConflict:(SINDocument *)document editor:(SINEditor *)editor completion:(void (^)(BOOL))completion;
- (BOOL)reloadDocumentFromDisk:(SINDocument *)document;
- (void)removeOpenDocument:(SINDocument *)document;
@end

@implementation SINWindowController (FileActions)
- (void)saveDocument:(SINDocument *)document saveAs:(BOOL)saveAs completion:(void (^)(BOOL))completion {
    if (!document || self.saving) { if (completion) completion(NO); return; }
    self.saving = YES;
    SINEditor *editor = self.editors[document.identifier];
    void (^save)(void) = ^{
        if (document.path && !saveAs) {
            NSError *error = nil;
            if ([document saveToPath:document.path overwriteConflict:NO error:&error]) [self finishSavingDocument:document editor:editor completion:completion];
            else if ([error.domain isEqual:SINErrorDomain] && error.code == SINErrorConflict) [self resolveSaveConflict:document editor:editor completion:completion];
            else { self.saving = NO; [self showError:error]; if (completion) completion(NO); }
            return;
        }
        NSSavePanel *panel = NSSavePanel.savePanel;
        panel.allowedContentTypes = @[UTTypeHTML]; panel.canCreateDirectories = YES;
        panel.title = saveAs ? @"Save HTML As" : @"Save HTML";
        panel.nameFieldStringValue = document.path || document.name.pathExtension.length ? document.name : [document.name stringByAppendingPathExtension:@"html"];
        if (document.path) panel.directoryURL = [NSURL fileURLWithPath:document.path.stringByDeletingLastPathComponent isDirectory:YES];
        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK) { self.saving = NO; if (completion) completion(NO); return; }
            NSError *error = nil;
            NSString *path = panel.URL.path;
            NSMutableArray *windows=[((SINAppDelegate *)NSApp.delegate).windows mutableCopy] ?: [NSMutableArray array];
            if(![windows containsObject:self])[windows addObject:self];
            for(SINWindowController *window in windows) for(SINDocument *open in window.documents) if((open!=document||window!=self) && ([open.path isEqual:path]||SINPathsReferToSameFile(open.path,path))) {
                self.saving = NO; [self showError:FileActionError(@"That destination is already open in another document or window. Choose another name.")]; if (completion) completion(NO); return;
            }
            // NSSavePanel returns OK only after its Replace confirmation for an
            // occupied destination. Other model callers keep no-overwrite defaults.
            if ([document saveAsToPath:path replaceExisting:YES error:&error]) [self finishSavingDocument:document editor:editor completion:completion];
            else { self.saving = NO; [self showError:error]; if (completion) completion(NO); }
        }];
    };
    if (editor) [editor flush:save]; else save();
}
- (void)finishSavingDocument:(SINDocument *)document editor:(SINEditor *)editor completion:(void (^)(BOOL))completion {
    NSString *previousPath = editor.services.documentPath;
    [self.store addRecentPath:document.path];
    editor.services.documentPath = document.path;
    void (^finish)(void) = ^{ self.saving = NO; [self refresh]; [self persist]; if (completion) completion(YES); };
    if ([previousPath isEqual:document.path]) { finish(); return; }
    if (editor.showingSource) editor.sourceView.string = document.text;
    if (!previousPath && editor && !editor.showingSource) {
        // Initial save often happens inside image insertion. Preserve its pending
        // selection while changing the local-file mapping.
        [editor asyncScript:@"await window.editor.setBase('sin-asset://document/');return true;" completion:^(id result, NSError *error) {
            if (error) [self showError:error];
            finish();
        }];
    } else {
        // Save As may have rewritten sources to a different asset directory.
        [editor reload]; finish();
    }
}
- (void)resolveSaveConflict:(SINDocument *)document editor:(SINEditor *)editor completion:(void (^)(BOOL))completion {
    NSAlert *alert = NSAlert.new;
    alert.messageText = @"This file changed outside Sin AI Prompt.";
    alert.informativeText = @"Save a copy to retain both versions. Reload replaces your editor contents with the version on disk. Overwrite replaces the disk file with your current document.";
    [alert addButtonWithTitle:@"Save a Copy"]; [alert addButtonWithTitle:@"Reload"]; [alert addButtonWithTitle:@"Overwrite"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) { self.saving = NO; [self saveDocument:document saveAs:YES completion:completion]; }
        else if (response == NSAlertSecondButtonReturn) { self.saving = NO; BOOL loaded = [self reloadDocumentFromDisk:document]; if (completion) completion(loaded); }
        else if (response == NSAlertThirdButtonReturn) {
            NSError *error = nil;
            if ([document saveToPath:document.path overwriteConflict:YES error:&error]) [self finishSavingDocument:document editor:editor completion:completion];
            else { self.saving = NO; [self showError:error]; if (completion) completion(NO); }
        } else { self.saving = NO; if (completion) completion(NO); }
    }];
}
- (BOOL)reloadDocumentFromDisk:(SINDocument *)document {
    NSError *error = nil;
    SINDocument *disk = [SINDocument openPath:document.path error:&error];
    if (!disk) { [self showError:error]; return NO; }
    document.text = disk.text; document.savedText = disk.savedText;
    document.encodingName = disk.encodingName; document.savedEncoding = disk.savedEncoding;
    document.newline = disk.newline; document.savedNewline = disk.savedNewline;
    document.fingerprint = disk.fingerprint; document.readOnly = disk.readOnly;
    document.modifiedDate = disk.modifiedDate;
    SINEditor *editor = self.editors[document.identifier];
    if (editor.showingSource) editor.sourceView.string = document.text;
    [editor reload]; [self refresh]; [self persist];
    return YES;
}
- (void)closeDocument:(SINDocument *)document {
    if (!document || self.saving) return;
    SINEditor *editor = self.editors[document.identifier];
    void (^close)(void) = ^{
        if (!document.modified) { [self removeOpenDocument:document]; return; }
        NSAlert *alert = NSAlert.new;
        alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", document.name];
        alert.informativeText = @"Your unsaved changes will be lost if you close this document without saving.";
        [alert addButtonWithTitle:@"Save"]; [alert addButtonWithTitle:@"Discard"]; [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) [self saveDocument:document saveAs:NO completion:^(BOOL saved) { if (saved) [self removeOpenDocument:document]; }];
            else if (response == NSAlertSecondButtonReturn) [self removeOpenDocument:document];
        }];
    };
    if (editor) [editor flush:close]; else close();
}
- (void)removeOpenDocument:(SINDocument *)document {
    NSUInteger index = [self.documents indexOfObject:document];
    if (index == NSNotFound) return;
    SINEditor *editor = self.editors[document.identifier];
    [editor.view removeFromSuperview]; [editor invalidate];
    [self.editors removeObjectForKey:document.identifier]; [self.documents removeObject:document];
    if (!self.documents.count) {
        NSError *error = nil; SINDocument *replacement = [self.store newDocument:&error];
        if (replacement) [self.documents addObject:replacement]; else [self showError:error];
    }
    if (self.active == document) {
        self.active = nil;
        if (self.documents.count) [self activate:self.documents[MIN(index,self.documents.count-1)]];
    } else [self refresh];
    [self persist];
}
- (void)renameDocument:(SINDocument *)document {
    if (!document || self.saving) return;
    NSAlert *alert = NSAlert.new;
    alert.messageText = @"Rename document";
    alert.informativeText = document.path ? @"The HTML file and its matching image folder move together. Pending edits remain unsaved." : @"Choose a name for this unsaved document.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,360,26)];
    field.stringValue = document.name; alert.accessoryView = field;
    [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSString *name = field.stringValue;
        if (document.path && ![name.pathExtension isEqualToString:document.path.pathExtension]) name = [name stringByAppendingPathExtension:document.path.pathExtension];
        self.saving = YES;
        SINEditor *editor = self.editors[document.identifier];
        void (^rename)(void) = ^{
            NSError *error = nil; NSString *oldPath = document.path;
            if ([document renameToFilename:name error:&error]) {
                if (oldPath) {
                    NSMutableArray *recent = [self.store.settings[@"recent"] mutableCopy]; [recent removeObject:oldPath]; self.store.settings[@"recent"] = recent ?: @[];
                    [self.store addRecentPath:document.path];
                }
                editor.services.documentPath = document.path;
                if (editor.showingSource) editor.sourceView.string = document.text;
                [editor reload]; [self refresh]; [self persist];
            } else [self showError:error];
            self.saving = NO;
        };
        if (editor) [editor flush:rename]; else rename();
    }];
}
- (void)exportDocument:(BOOL)markdown {
    if (!self.active || self.saving) return;
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.title = markdown ? @"Export Markdown" : @"Export Standalone HTML";
    panel.allowedContentTypes = markdown ? @[[UTType typeWithFilenameExtension:@"md"] ?: UTTypePlainText] : @[UTTypeHTML];
    panel.canCreateDirectories = YES;
    panel.nameFieldStringValue = [[self.active.name.stringByDeletingPathExtension stringByAppendingString:markdown ? @"" : @"-standalone"] stringByAppendingPathExtension:markdown ? @"md" : @"html"];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        [self exportDocument:markdown toPath:panel.URL.path completion:^(NSError *error) { if (error) [self showError:error]; }];
    }];
}
- (void)exportDocument:(BOOL)markdown toPath:(NSString *)path completion:(void (^)(NSError *))completion {
    if (!self.active || self.saving) { completion(FileActionError(@"Wait for the current file operation to finish.")); return; }
    NSFileManager *fm = NSFileManager.defaultManager;
    path = path.stringByStandardizingPath;
    NSMutableArray *windows = [((SINAppDelegate *)NSApp.delegate).windows mutableCopy] ?: NSMutableArray.new;
    if (![windows containsObject:self]) [windows addObject:self];
    for (SINWindowController *window in windows) for (SINDocument *document in window.documents) {
        if ([document.path isEqual:path] || SINPathsReferToSameFile(document.path,path)) { completion(FileActionError(@"Choose an export destination that is not open in an editor window.")); return; }
    }
    NSError *error = nil;
    BOOL existed = [fm fileExistsAtPath:path];
    NSData *previous = existed ? [NSData dataWithContentsOfFile:path options:0 error:&error] : nil;
    if (existed && !previous) { completion(error); return; }
    NSString *fingerprint = previous ? [SINDocument fingerprintForData:previous] : nil;
    NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"SinAI-export-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:&error]) { completion(error); return; }
    NSString *stagedPath = [staging stringByAppendingPathComponent:path.lastPathComponent];
    SINEditor *editor = self.editor;
    self.saving = YES; editor.services.saveAsPath = stagedPath;
    [editor exportKind:markdown ? @"markdown" : @"portable" completion:^(NSString *text, NSError *failure) {
        editor.services.saveAsPath = nil;
        NSError *writeError = failure;
        if (text) {
            NSData *current = [NSData dataWithContentsOfFile:path];
            BOOL changed = existed ? !current || ![fingerprint isEqual:[SINDocument fingerprintForData:current]] : [fm fileExistsAtPath:path];
            if (changed) writeError = FileActionError(@"The export destination changed while generating the export. Export again to review the current file.");
            else {
                // The staging document uses the final basename, so generated
                // Markdown references already match the destination asset folder.
                // Save As merges only identical or new assets and atomically
                // replaces the explicitly confirmed output file.
                SINDocument *output = SINDocument.new; output.text = text;
                if ([output saveToPath:stagedPath overwriteConflict:NO error:&writeError])
                    [output saveAsToPath:path replaceExisting:existed error:&writeError];
            }
        } else if (!writeError) writeError = FileActionError(@"The export did not produce any text.");
        [fm removeItemAtPath:staging error:NULL];
        if (!writeError) self.status.stringValue = [@"Exported " stringByAppendingString:path];
        self.saving = NO; completion(writeError);
    }];
}
- (void)checkExternalChange {
    if (self.testMode || self.saving || self.annotating || self.window.attachedSheet || !self.active.path) return;
    SINDocument *document = self.active;
    NSData *bytes = [NSData dataWithContentsOfFile:document.path];
    NSString *current = bytes ? [SINDocument fingerprintForData:bytes] : @"missing";
    if ([current isEqual:document.fingerprint]) return;
    static NSMutableDictionary<NSString *,NSString *> *noticed;
    if (!noticed) noticed = NSMutableDictionary.new;
    if ([noticed[document.identifier] isEqual:current]) return;
    noticed[document.identifier] = current;
    NSAlert *alert = NSAlert.new;
    alert.messageText = bytes ? @"The open file changed on disk." : @"The open file is no longer available.";
    alert.informativeText = bytes ? @"Reload reads the latest file and discards current editor changes. Keep preserves your text; saving will ask how to resolve the conflict." : @"Your editor contents are retained. Save a copy to a new location to keep them.";
    [alert addButtonWithTitle:@"Keep Editing"]; [alert addButtonWithTitle:bytes ? @"Reload" : @"Save a Copy"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertSecondButtonReturn) return;
        if (bytes) [self reloadDocumentFromDisk:document]; else [self saveDocument:document saveAs:YES completion:nil];
    }];
}
@end
