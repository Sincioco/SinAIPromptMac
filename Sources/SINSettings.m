#import "SINWindowController.h"
#import "SINNativeServices.h"
#import "SINAppDelegate.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const void *SINSettingsKey=&SINSettingsKey;
static NSError *SettingsError(NSString *message) { return [NSError errorWithDomain:@"SinAIPrompt" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }


static NSArray<SINWindowController *> *SettingsControllers(SINWindowController *owner) {
    NSMutableArray *result=NSMutableArray.new;SINAppDelegate *delegate=(SINAppDelegate *)NSApp.delegate;
    NSArray *candidates=[delegate isKindOfClass:SINAppDelegate.class]?delegate.windows:@[];
    for(SINWindowController *controller in candidates)if(!controller.closing&&controller.store==owner.store)[result addObject:controller];
    if(![result containsObject:owner])[result addObject:owner];return result;
}
static void FlushSettingsEditors(NSArray<SINEditor *> *editors,NSUInteger index,void(^completion)(void)) {
    if(index>=editors.count){completion();return;}[editors[index] flush:^{FlushSettingsEditors(editors,index+1,completion);}];
}

@interface SINSettingsController : NSObject <NSWindowDelegate>
@property(nonatomic,weak) SINWindowController *owner;
@property(nonatomic,strong) NSPanel *panel;
@property(nonatomic,strong) NSTextField *autosave;
@property(nonatomic,strong) NSTextField *storage;
@property(nonatomic,strong) NSTextField *number;
@property(nonatomic,strong) NSTextField *errorLabel;
@property(nonatomic,strong) NSPopUpButton *images;
@property(nonatomic,strong) NSPopUpButton *theme;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSButton *> *toggles;
@property(nonatomic) BOOL saving;
- (void)present;
@end

@implementation SINSettingsController
- (NSTextField *)label:(NSString *)text y:(CGFloat)y {
    NSTextField *label=[NSTextField labelWithString:text];label.frame=NSMakeRect(24,y,532,22);[self.panel.contentView addSubview:label];return label;
}
- (NSTextField *)folder:(NSString *)value y:(CGFloat)y tag:(NSInteger)tag {
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(24,y,434,26)];field.stringValue=value?:@"";field.placeholderString=tag==1?@"Leave empty to create unnamed drafts":@"Application data folder";[self.panel.contentView addSubview:field];
    NSButton *browse=[NSButton buttonWithTitle:@"Browse…" target:self action:@selector(browse:)];browse.frame=NSMakeRect(466,y-1,90,28);browse.tag=tag;[self.panel.contentView addSubview:browse];return field;
}
- (void)present {
    self.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,580,618) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];self.panel.title=@"Settings";self.panel.delegate=self;self.panel.releasedWhenClosed=NO;
    NSDictionary *settings=self.owner.store.settings;
    NSTextField *title=[self label:@"Documents and application storage" y:577];title.font=[NSFont boldSystemFontOfSize:15];
    [self label:@"New document autosave folder" y:545];self.autosave=[self folder:settings[@"autoSaveDirectory"] y:515 tag:1];
    [self label:@"Application storage folder" y:479];self.storage=[self folder:self.owner.store.directory y:449 tag:2];
    NSTextField *hint=[self label:@"Changing storage copies your profile to an empty folder and retains the original." y:423];hint.font=[NSFont systemFontOfSize:11];hint.textColor=NSColor.secondaryLabelColor;
    [self label:@"Image storage" y:386];self.images=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(170,382,386,28)];[self.images addItemsWithTitles:@[@"Ask each time",@"Inline (Base64)",@"Separate PNG file",@"Reference original image"]];
    NSArray *imageValues=@[@"",@"inline",@"separate",@"reference"];NSUInteger selection=[imageValues indexOfObject:settings[@"imageStorage"]?:@""];[self.images selectItemAtIndex:selection==NSNotFound?0:selection];[self.panel.contentView addSubview:self.images];
    [self label:@"Appearance" y:348];self.theme=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(170,344,386,28)];[self.theme addItemsWithTitles:@[@"System",@"Light",@"Dark"]];NSString *theme=[settings[@"theme"] lowercaseString]?:@"system";selection=[@[@"system",@"light",@"dark"] indexOfObject:theme];[self.theme selectItemAtIndex:selection==NSNotFound?0:selection];[self.panel.contentView addSubview:self.theme];
    self.toggles=[NSMutableDictionary dictionary];NSArray *options=@[@[@"wordWrap",@"Wrap source text"],@[@"lineNumbers",@"Show source line numbers"],@[@"showToolbar",@"Show editor toolbar"],@[@"wrapToolbar",@"Wrap toolbar buttons"],@[@"restoreSession",@"Restore documents at launch"],@[@"autoSaveAllOnClose",@"Save all documents when closing"]];
    for(NSUInteger i=0;i<options.count;i++) { NSArray *option=options[i];NSButton *button=[NSButton checkboxWithTitle:option[1] target:nil action:NULL];button.frame=NSMakeRect(i%2?294:24,304-32*(i/2),270,24);button.state=[settings[option[0]] boolValue]?NSControlStateValueOn:NSControlStateValueOff;self.toggles[option[0]]=button;[self.panel.contentView addSubview:button]; }
    [self label:@"Next document number" y:190];self.number=[[NSTextField alloc] initWithFrame:NSMakeRect(206,187,100,26)];self.number.stringValue=[NSString stringWithFormat:@"%ld",(long)MAX(1,[settings[@"nextDocumentNumber"] integerValue])];[self.panel.contentView addSubview:self.number];
    NSButton *reset=[NSButton buttonWithTitle:@"Reset to 1" target:self action:@selector(resetNumber:)];reset.frame=NSMakeRect(316,186,110,28);[self.panel.contentView addSubview:reset];
    NSTextField *numberHint=[self label:@"Existing files keep their names. New files skip names that are already in use." y:158];numberHint.font=[NSFont systemFontOfSize:11];numberHint.textColor=NSColor.secondaryLabelColor;
    NSButton *association=[NSButton buttonWithTitle:@"Use Sin AI Prompt for .html Files…" target:self action:@selector(setHTMLDefault:)];association.frame=NSMakeRect(24,122,330,28);[self.panel.contentView addSubview:association];
    self.errorLabel=[NSTextField wrappingLabelWithString:@""];self.errorLabel.textColor=NSColor.systemRedColor;self.errorLabel.frame=NSMakeRect(24,66,532,49);[self.panel.contentView addSubview:self.errorLabel];
    NSButton *cancel=[NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];cancel.frame=NSMakeRect(350,20,94,30);cancel.keyEquivalent=@"\e";[self.panel.contentView addSubview:cancel];
    NSButton *save=[NSButton buttonWithTitle:@"Save" target:self action:@selector(save:)];save.frame=NSMakeRect(458,20,98,30);save.keyEquivalent=@"\r";[self.panel.contentView addSubview:save];
    [self.owner.window beginSheet:self.panel completionHandler:^(NSModalResponse response) { [self.panel orderOut:nil];objc_setAssociatedObject(self.owner,SINSettingsKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }];
}
- (void)browse:(NSButton *)sender {
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseDirectories=YES;panel.canChooseFiles=NO;panel.canCreateDirectories=YES;panel.allowsMultipleSelection=NO;panel.prompt=@"Choose";panel.title=sender.tag==1?@"Choose New Document Autosave Folder":@"Choose Application Storage Folder";
    NSTextField *field=sender.tag==1?self.autosave:self.storage;if(field.stringValue.length)panel.directoryURL=[NSURL fileURLWithPath:field.stringValue.stringByExpandingTildeInPath isDirectory:YES];
    [panel beginSheetModalForWindow:self.panel completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK)field.stringValue=panel.URL.path;}];
}
- (void)resetNumber:(id)sender { self.number.stringValue=@"1"; }
- (void)setHTMLDefault:(NSButton *)sender {
    sender.enabled=NO;
    [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:NSBundle.mainBundle.bundleURL toOpenContentType:UTTypeHTML completionHandler:^(NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{sender.enabled=YES;if(error)[self fail:error];else {self.errorLabel.textColor=NSColor.secondaryLabelColor;self.errorLabel.stringValue=@"Sin AI Prompt is now the default application for HTML files.";}});
    }];
}
- (void)cancel:(id)sender { if(!self.saving)[self.owner.window endSheet:self.panel returnCode:NSModalResponseCancel]; }
- (BOOL)windowShouldClose:(NSWindow *)sender { [self cancel:nil];return NO; }
- (void)fail:(NSError *)error { self.errorLabel.textColor=NSColor.systemRedColor;self.errorLabel.stringValue=error.localizedDescription?:@"Settings could not be saved."; }
- (void)save:(NSButton *)sender {
    if(self.saving)return;NSArray<SINWindowController *> *controllers=SettingsControllers(self.owner);
    for(SINWindowController *controller in controllers)if(controller.saving){[self fail:SettingsError(@"Wait for the current document save to finish before changing settings.")];return;}
    self.saving=YES;sender.enabled=NO;NSMutableArray *editors=NSMutableArray.new;
    for(SINWindowController *controller in controllers){controller.saving=YES;[editors addObjectsFromArray:controller.editors.allValues];}
    FlushSettingsEditors(editors,0,^{[self commit:sender];for(SINWindowController *controller in controllers)controller.saving=NO;self.saving=NO;sender.enabled=YES;});
}
- (void)commit:(id)sender {
    NSString *numberText=[self.number.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSScanner *scanner=[NSScanner scannerWithString:numberText];long long number=0;
    if(![scanner scanLongLong:&number]||!scanner.isAtEnd||number<1||number>999999999){[self fail:SettingsError(@"Enter a document number from 1 to 999,999,999.")];return;}
    NSString *autosave=[self.autosave.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].stringByExpandingTildeInPath.stringByStandardizingPath;
    NSString *directory=[self.storage.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].stringByExpandingTildeInPath.stringByStandardizingPath;
    if(!directory.isAbsolutePath){[self fail:SettingsError(@"Choose an absolute application storage folder.")];return;}
    NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
    if(autosave.length) {
        if(!autosave.isAbsolutePath){[self fail:SettingsError(@"Choose an absolute autosave folder, or leave the field empty.")];return;}
        BOOL isDirectory=NO;if([fm fileExistsAtPath:autosave isDirectory:&isDirectory]&&!isDirectory){[self fail:SettingsError(@"The autosave location is a file. Choose a folder.")];return;}
        if(![fm createDirectoryAtPath:autosave withIntermediateDirectories:YES attributes:nil error:&error]){[self fail:error];return;}
        if(![fm isWritableFileAtPath:autosave]){[self fail:SettingsError(@"The autosave folder is not writable.")];return;}
    }
    NSString *oldDirectory=self.owner.store.directory;
    if(![directory isEqual:oldDirectory]) {
        // Flush the current session before copying the profile; originals remain untouched.
        [self.owner persist];
        if(![self.owner.store relocateToDirectory:directory error:&error]){[self fail:error];return;}
        directory=self.owner.store.directory;
        for(SINWindowController *controller in SettingsControllers(self.owner))for(SINEditor *editor in controller.editors.allValues) { SINNativeServices *services=[[SINNativeServices alloc] initWithDataDirectory:directory];services.documentID=editor.document.identifier;services.documentPath=editor.document.path;services.saveAsPath=editor.services.saveAsPath;services.window=controller.window;editor.services=services; }
    }
    NSMutableDictionary *before=[self.owner.store.settings mutableCopy];NSMutableDictionary *settings=self.owner.store.settings;
    settings[@"autoSaveDirectory"]=autosave;settings[@"nextDocumentNumber"]=@(number);settings[@"imageStorage"]=@[@"",@"inline",@"separate",@"reference"][self.images.indexOfSelectedItem];settings[@"theme"]=@[@"system",@"light",@"dark"][self.theme.indexOfSelectedItem];
    for(NSString *key in self.toggles)settings[key]=@(self.toggles[key].state==NSControlStateValueOn);
    if(![self.owner.store saveSettings:&error]){self.owner.store.settings=before;[self fail:error];return;}
    NSString *pointer=[SINStore.defaultDirectory stringByAppendingPathComponent:@"data-location.json"];
    NSData *location=[NSJSONSerialization dataWithJSONObject:@{@"directory":directory} options:NSJSONWritingPrettyPrinted error:&error];
    if(![fm createDirectoryAtPath:pointer.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]||![location writeToFile:pointer options:NSDataWritingAtomic error:&error]){[self fail:error];return;}
    [NSUserDefaults.standardUserDefaults setObject:directory forKey:@"SinAIPromptDataDirectory"];
    NSString *theme=settings[@"theme"];NSAppearance *appearance=[theme isEqual:@"dark"]?[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]:([theme isEqual:@"light"]?[NSAppearance appearanceNamed:NSAppearanceNameAqua]:nil);
    for(SINWindowController *controller in SettingsControllers(self.owner)){controller.window.appearance=appearance;for(SINEditor *editor in controller.editors.allValues){editor.preferences=settings;[editor applyPreferences];}[controller refresh];}
    [self.owner.window endSheet:self.panel returnCode:NSModalResponseOK];
}
@end

@implementation SINWindowController (Settings)
- (void)showSettings {
    for(SINWindowController *owner in SettingsControllers(self)){SINSettingsController *existing=objc_getAssociatedObject(owner,SINSettingsKey);if(existing){[existing.panel makeKeyAndOrderFront:nil];return;}}
    SINSettingsController *controller=[SINSettingsController new];controller.owner=self;objc_setAssociatedObject(self,SINSettingsKey,controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(self.editor)[self.editor flush:^{[controller present];}];else [controller present];
}
@end
