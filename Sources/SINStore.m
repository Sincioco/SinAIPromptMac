#import "SINStore.h"

static BOOL StoreError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SINErrorDomain code:SINErrorStorage userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static id ReadJSON(NSString *path, Class expectedClass, NSError **error) {
    NSError *lastError = nil;
    BOOL found = NO;
    for (NSString *suffix in @[@"", @".bak"]) {
        NSString *candidate = [path stringByAppendingString:suffix];
        if (![NSFileManager.defaultManager fileExistsAtPath:candidate]) continue;
        found = YES;
        NSData *data = [NSData dataWithContentsOfFile:candidate options:0 error:&lastError];
        id result = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&lastError] : nil;
        if ([result isKindOfClass:expectedClass]) return result;
        if (result) StoreError(&lastError, [NSString stringWithFormat:@"Invalid JSON profile structure in %@.", candidate.lastPathComponent]);
    }
    if (found && error) *error = lastError;
    return nil;
}
static BOOL WriteJSON(id value, NSString *path, NSError **error) {
    if (![NSJSONSerialization isValidJSONObject:value]) return StoreError(error, @"The profile contains values that cannot be saved as JSON.");
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    return data && SINAtomicWrite(data, path, YES, error);
}
@interface SINStore ()
@property(nonatomic, copy, readwrite) NSString *directory;
@end
@implementation SINStore
+ (NSString *)defaultDirectory {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Sin AI Prompt"];
}
- (instancetype)initWithDirectory:(NSString *)directory error:(NSError **)error {
    if ((self = [super init])) {
        directory = directory.stringByExpandingTildeInPath.stringByStandardizingPath;
        if (![directory isAbsolutePath]) directory = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:directory];
        if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
        _directory = directory;
        _settings = [@{@"theme":@"System", @"nextDocumentNumber":@1, @"autoSaveDirectory":@"", @"wordWrap":@YES, @"statusBar":@YES, @"showToolbar":@YES, @"wrapToolbar":@YES, @"showTabs":@NO, @"imageStorage":@"", @"recentColors":@[], @"lineNumbers":@YES, @"restoreSession":@YES, @"autoSaveAllOnClose":@YES, @"openInNewWindow":@NO, @"recentFiles":@YES, @"documentList":@NO, @"explorerMode":@YES, @"contentView":@NO, @"contentWidth":@220, @"explorerShowFolders":@YES, @"explorerDirectory":@"", @"documentSort":@"newest", @"listWidth":@250, @"dateTimeFormat":@0, @"recent":@[]} mutableCopy];
        NSError *readError = nil;
        NSDictionary *loaded = ReadJSON([directory stringByAppendingPathComponent:@"settings.json"], NSDictionary.class, &readError);
        if (!loaded && readError) { if (error) *error = readError; return nil; }
        if (loaded) [_settings addEntriesFromDictionary:loaded];
        _templates = ReadJSON([directory stringByAppendingPathComponent:@"templates.json"], NSArray.class, &readError);
        if (!_templates && readError) { if (error) *error = readError; return nil; }
        if (!_templates) _templates = [NSMutableArray array];
    }
    return self;
}
- (SINDocument *)newDocument:(NSError **)error {
    NSInteger number = MAX(1, [self.settings[@"nextDocumentNumber"] integerValue]);
    NSString *autosaveFolder = self.settings[@"autoSaveDirectory"];
    if (![autosaveFolder isKindOfClass:NSString.class]) autosaveFolder = @"";
    if (autosaveFolder.length && ![NSFileManager.defaultManager createDirectoryAtPath:autosaveFolder.stringByExpandingTildeInPath withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    while (YES) {
        SINDocument *document = [SINDocument new];
        document.untitledNumber = number++;
        document.text = @"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body><p><br></p></body></html>";
        document.savedText = document.text;
        if (autosaveFolder.length) {
            NSDateFormatter *formatter = [NSDateFormatter new]; formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; formatter.dateFormat = @"yyyy-MM-dd HHmm";
            NSString *filename = [NSString stringWithFormat:@"%@ - %@.html", [formatter stringFromDate:NSDate.date], document.name];
            NSString *path = [autosaveFolder.stringByExpandingTildeInPath stringByAppendingPathComponent:filename];
            NSError *saveError = nil;
            if (![document saveToPath:path overwriteConflict:NO error:&saveError]) {
                if ([saveError.domain isEqual:SINErrorDomain] && saveError.code == SINErrorOccupied) continue;
                if (error) *error = saveError;
                return nil;
            }
            document.autosave = YES;
        }
        self.settings[@"nextDocumentNumber"] = @(number);
        if (![self saveSettings:error]) return nil;
        return document;
    }
}
- (NSArray<SINDocument *> *)restoreDocuments:(NSError **)error {
    if (![self.settings[@"restoreSession"] boolValue]) return @[];
    NSDictionary *session = ReadJSON([self.directory stringByAppendingPathComponent:@"session.json"], NSDictionary.class, error);
    if (!session) return @[];
    if ([session[@"activeIdentifier"] isKindOfClass:NSString.class]) self.activeIdentifier = session[@"activeIdentifier"];
    NSMutableArray *result = [NSMutableArray array];
    NSArray *documents = session[@"documents"];
    if (![documents isKindOfClass:NSArray.class]) { StoreError(error, @"The session file has no valid document collection."); return @[]; }
    NSMutableSet *identifiers = [NSMutableSet set];
    NSInteger nextNumber = MAX(1, [self.settings[@"nextDocumentNumber"] integerValue]);
    for (id value in documents) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        SINDocument *document = [SINDocument documentFromDictionary:value];
        if ([identifiers containsObject:document.identifier]) document.identifier = NSUUID.UUID.UUIDString;
        [identifiers addObject:document.identifier];
        nextNumber = MAX(nextNumber, document.untitledNumber + 1);
        // Saved text is retained even if the file disappeared. A subsequent save
        // detects the mismatch instead of silently replacing outside edits.
        if (document.path && !document.modified) {
            SINDocument *disk = [SINDocument openPath:document.path error:NULL];
            if (disk) {
                document.text = disk.text; document.savedText = disk.savedText;
                document.encodingName = disk.encodingName; document.savedEncoding = disk.savedEncoding;
                document.newline = disk.newline; document.savedNewline = disk.savedNewline;
                document.fingerprint = disk.fingerprint; document.readOnly = disk.readOnly;
                document.modifiedDate = disk.modifiedDate;
            }
        }
        [result addObject:document];
    }
    self.settings[@"nextDocumentNumber"] = @(nextNumber);
    return result;
}
- (BOOL)saveSessionDocuments:(NSArray<SINDocument *> *)documents activeIdentifier:(NSString *)identifier error:(NSError **)error {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:documents.count];
    if ([self.settings[@"restoreSession"] boolValue]) for (SINDocument *document in documents) [values addObject:document.dictionaryRepresentation];
    NSMutableDictionary *session = [@{@"version":@1, @"documents":values, @"savedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
    if (identifier) session[@"activeIdentifier"] = identifier;
    if (!WriteJSON(session, [self.directory stringByAppendingPathComponent:@"session.json"], error)) return NO;
    self.activeIdentifier = identifier;
    return [self saveSettings:error] && [self saveTemplates:error];
}
- (BOOL)saveSettings:(NSError **)error { return WriteJSON(self.settings, [self.directory stringByAppendingPathComponent:@"settings.json"], error); }
- (BOOL)saveTemplates:(NSError **)error { return WriteJSON(self.templates, [self.directory stringByAppendingPathComponent:@"templates.json"], error); }
- (void)addRecentPath:(NSString *)path {
    NSMutableArray *recent = [self.settings[@"recent"] isKindOfClass:NSArray.class] ? [self.settings[@"recent"] mutableCopy] : [NSMutableArray array];
    [recent removeObject:path]; [recent insertObject:path atIndex:0];
    while (recent.count > 10) [recent removeLastObject];
    self.settings[@"recent"] = recent;
}
- (BOOL)relocateToDirectory:(NSString *)directory error:(NSError **)error {
    directory = directory.stringByExpandingTildeInPath.stringByStandardizingPath;
    if (![directory isAbsolutePath]) directory = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:directory];
    if ([directory isEqual:self.directory]) return YES;
    if ([directory hasPrefix:[self.directory stringByAppendingString:@"/"]] || [self.directory hasPrefix:[directory stringByAppendingString:@"/"]]) return StoreError(error, @"Choose a separate storage folder, not a parent or child of the existing profile.");
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO, exists = [fm fileExistsAtPath:directory isDirectory:&isDirectory];
    if (exists && (!isDirectory || [fm contentsOfDirectoryAtPath:directory error:error].count)) return StoreError(error, @"The destination is occupied. Choose an empty folder to avoid replacing another profile.");
    if (![self saveSettings:error] || ![self saveTemplates:error]) return NO;
    if (!exists && ![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSArray *files = [fm contentsOfDirectoryAtPath:self.directory error:error];
    if (!files) return NO;
    NSMutableArray *copied = [NSMutableArray array];
    for (NSString *name in files) {
        NSString *target = [directory stringByAppendingPathComponent:name];
        if (![fm copyItemAtPath:[self.directory stringByAppendingPathComponent:name] toPath:target error:error]) {
            for (NSString *rollback in copied) [fm removeItemAtPath:rollback error:NULL];
            if (!exists) [fm removeItemAtPath:directory error:NULL];
            return NO;
        }
        [copied addObject:target];
    }
    self.directory = directory;
    [NSUserDefaults.standardUserDefaults setObject:directory forKey:@"SinAIPromptDataDirectory"];
    return YES;
}
@end
