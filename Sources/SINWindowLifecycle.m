#import "SINWindowController.h"
@implementation SINWindowController (Lifecycle)
- (void)prepareToClose:(void (^)(BOOL))completion {
    if(self.annotating||self.saving){completion(NO);return;}
    [self.editor flush:^{[self prepareDocuments:self.documents.copy index:0 completion:completion];}];
}
- (void)prepareDocuments:(NSArray<SINDocument*>*)documents index:(NSUInteger)index completion:(void(^)(BOOL))completion {
    if(index>=documents.count){completion(YES);return;}
    SINDocument *document=documents[index];
    void(^next)(void)=^{[self prepareDocuments:documents index:index+1 completion:completion];};
    if(!document.modified){next();return;}
    if(document.path&&!document.readOnly&&[self.store.settings[@"autoSaveAllOnClose"] boolValue]){
        [self saveDocument:document saveAs:NO completion:^(BOOL saved){if(saved)next();else completion(NO);}];return;
    }
    if([self.store.settings[@"restoreSession"] boolValue]){next();return;}
    NSAlert *alert=NSAlert.new;alert.messageText=[NSString stringWithFormat:@"Save changes to %@?",document.name];
    alert.informativeText=@"Session recovery is turned off. Save this document to keep your changes.";
    [alert addButtonWithTitle:@"Save"];[alert addButtonWithTitle:@"Discard"];[alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response==NSAlertFirstButtonReturn)[self saveDocument:document saveAs:document.readOnly completion:^(BOOL saved){if(saved)next();else completion(NO);}];
        else if(response==NSAlertSecondButtonReturn)next();else completion(NO);
    }];
}
@end
