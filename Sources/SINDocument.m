#import "SINDocument.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>

NSString * const SINErrorDomain = @"SinAIPrompt";
static BOOL Fail(NSError **error, SINErrorCode code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SINErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSString *FullPath(NSString *path) {
    path = path.stringByExpandingTildeInPath.stringByStandardizingPath;
    if (![path isAbsolutePath]) path = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
    return path;
}
static BOOL ReadOnly(NSString *path) {
    struct stat status;
    return lstat(path.fileSystemRepresentation, &status) == 0 && ((status.st_mode & 0222) == 0 || ![NSFileManager.defaultManager isWritableFileAtPath:path]);
}
static BOOL SameFile(NSString *first, NSString *second) {
    struct stat a,b;
    return lstat(first.fileSystemRepresentation,&a)==0 && lstat(second.fileSystemRepresentation,&b)==0 && a.st_dev==b.st_dev && a.st_ino==b.st_ino;
}
BOOL SINPathsReferToSameFile(NSString *first,NSString *second) {
    if(!first||!second)return NO;
    struct stat a,b;
    return stat(first.fileSystemRepresentation,&a)==0 && stat(second.fileSystemRepresentation,&b)==0 && a.st_dev==b.st_dev && a.st_ino==b.st_ino;
}
static BOOL CaseOnlySameFile(NSString *first, NSString *second) { return [first caseInsensitiveCompare:second]==NSOrderedSame && SameFile(first,second); }
static BOOL MoveKeepingCase(NSString *source,NSString *destination,NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    if([source isEqual:destination])return YES;
    if(!CaseOnlySameFile(source,destination))return [fm moveItemAtPath:source toPath:destination error:error];
    NSString *temporary=[source.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".sin-rename-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if(![fm moveItemAtPath:source toPath:temporary error:error])return NO;
    if([fm moveItemAtPath:temporary toPath:destination error:error])return YES;
    [fm moveItemAtPath:temporary toPath:source error:NULL];return NO;
}
BOOL SINMoveFilePreservingCase(NSString *source,NSString *destination,NSError **error) { return MoveKeepingCase(source,destination,error); }
static BOOL AtomicWrite(NSData *data, NSString *path, BOOL backup, BOOL exclusive, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *temporary = [path stringByAppendingFormat:@".%@.tmp", NSUUID.UUID.UUIDString];
    int fd = open(temporary.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0) { if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}]; return NO; }
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    BOOL success = YES;
    while (offset < data.length) {
        ssize_t count = write(fd, bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { success = NO; break; }
        offset += count;
    }
    if (success && fsync(fd) != 0) success = NO;
    int savedErrno = errno;
    struct stat oldStat;
    if (lstat(path.fileSystemRepresentation, &oldStat) == 0) fchmod(fd, oldStat.st_mode & 0777);
    close(fd);
    if (!success && error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:@{NSFilePathErrorKey:path}];
    if (success && backup && [fm fileExistsAtPath:path]) {
        NSData *previous = [NSData dataWithContentsOfFile:path options:0 error:error];
        success = previous && AtomicWrite(previous, [path stringByAppendingString:@".bak"], NO, NO, error);
    }
    if (success) {
        int result = exclusive ? renamex_np(temporary.fileSystemRepresentation, path.fileSystemRepresentation, RENAME_EXCL) : rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation);
        if (result != 0) {
            if (errno == EEXIST) success = Fail(error, SINErrorOccupied, @"The destination already exists. Choose another name.");
            else { success = NO; if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}]; }
        }
    }
    if (success) {
        int directory = open(path.stringByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY);
        if (directory >= 0) { fsync(directory); close(directory); }
    }
    [fm removeItemAtPath:temporary error:NULL];
    return success;
}
BOOL SINAtomicWrite(NSData *data, NSString *path, BOOL backup, NSError **error) { return AtomicWrite(data, path, backup, NO, error); }

static NSString *Normalize(NSString *text) { return [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"]; }
static NSString *DetectNewline(NSString *text) {
    NSUInteger crlf = 0, lf = 0, cr = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character == '\r') { if (index + 1 < text.length && [text characterAtIndex:index+1] == '\n') { crlf++; index++; } else cr++; }
        else if (character == '\n') lf++;
    }
    if (!crlf && !cr && !lf) return @"\n";
    return crlf >= lf && crlf >= cr ? @"\r\n" : lf >= cr ? @"\n" : @"\r";
}
static NSStringEncoding Encoding(NSString *name) {
    if ([name isEqual:@"UTF-16 LE"]) return NSUTF16LittleEndianStringEncoding;
    if ([name isEqual:@"UTF-16 BE"]) return NSUTF16BigEndianStringEncoding;
    if ([name isEqual:@"UTF-32 LE"]) return NSUTF32LittleEndianStringEncoding;
    if ([name isEqual:@"UTF-32 BE"]) return NSUTF32BigEndianStringEncoding;
    if ([name isEqual:@"ANSI"] || [name isEqual:@"Windows-1252"]) return NSWindowsCP1252StringEncoding;
    if ([name isEqual:@"Mac Roman"]) return NSMacOSRomanStringEncoding;
    if ([name isEqual:@"ISO-8859-1"]) return NSISOLatin1StringEncoding;
    return NSUTF8StringEncoding;
}
static NSData *Encode(NSString *text, NSString *name, NSString *newline, NSError **error) {
    NSData *body = [[Normalize(text) stringByReplacingOccurrencesOfString:@"\n" withString:newline] dataUsingEncoding:Encoding(name) allowLossyConversion:NO];
    if (!body) { Fail(error, SINErrorEncoding, @"The selected encoding cannot represent all characters. Choose UTF-8 to keep them."); return nil; }
    NSMutableData *result = [NSMutableData data];
    if ([name isEqual:@"UTF-8 with BOM"]) { const unsigned char bom[] = {0xEF,0xBB,0xBF}; [result appendBytes:bom length:3]; }
    if ([name isEqual:@"UTF-16 LE"]) { const unsigned char bom[] = {0xFF,0xFE}; [result appendBytes:bom length:2]; }
    if ([name isEqual:@"UTF-16 BE"]) { const unsigned char bom[] = {0xFE,0xFF}; [result appendBytes:bom length:2]; }
    if ([name isEqual:@"UTF-32 LE"]) { const unsigned char bom[] = {0xFF,0xFE,0,0}; [result appendBytes:bom length:4]; }
    if ([name isEqual:@"UTF-32 BE"]) { const unsigned char bom[] = {0,0,0xFE,0xFF}; [result appendBytes:bom length:4]; }
    [result appendData:body]; return result;
}
static void RollbackCreatedAssets(NSArray<NSDictionary *> *created) {
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSDictionary *item in created.reverseObjectEnumerator) {
        NSString *path=item[@"path"];
        if([item[@"directory"] boolValue]) { rmdir(path.fileSystemRepresentation); continue; }
        NSDictionary *attributes=[fm attributesOfItemAtPath:path error:NULL];
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular])continue;
        NSData *bytes=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        if(bytes && [[SINDocument fingerprintForData:bytes] isEqual:item[@"fingerprint"]]) [fm removeItemAtPath:path error:NULL];
    }
}
static BOOL MergeAssets(NSString *source,NSString *destination,BOOL merge,NSMutableArray *created,NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    source=source.stringByResolvingSymlinksInPath;
    NSDictionary *destinationAttributes=[fm attributesOfItemAtPath:destination error:NULL];
    if(destinationAttributes && (!merge || ![destinationAttributes[NSFileType] isEqual:NSFileTypeDirectory])) return Fail(error,SINErrorOccupied,@"The destination image folder already exists or is a filesystem link. Choose another filename.");
    NSMutableArray<NSDictionary *> *plan=[NSMutableArray array];
    if(!destinationAttributes)[plan addObject:@{@"path":destination,@"directory":@YES}];
    __block NSError *enumerationError=nil;
    NSString *canonicalSource=[[NSURL fileURLWithPath:source isDirectory:YES] URLByResolvingSymlinksInPath].path;
    NSDirectoryEnumerator<NSURL *> *enumerator=[fm enumeratorAtURL:[NSURL fileURLWithPath:canonicalSource isDirectory:YES] includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url,NSError *failure){(void)url;enumerationError=failure;return NO;}];
    for(NSURL *url in enumerator) {
        NSString *relative=[[url.pathComponents subarrayWithRange:NSMakeRange(url.pathComponents.count-enumerator.level,enumerator.level)] componentsJoinedByString:@"/"],*target=[destination stringByAppendingPathComponent:relative];
        NSDictionary *attributes=[fm attributesOfItemAtPath:url.path error:error];
        if(!attributes)return NO;
        BOOL directory=[attributes[NSFileType] isEqual:NSFileTypeDirectory];
        if(!directory && ![attributes[NSFileType] isEqual:NSFileTypeRegular])return Fail(error,SINErrorStorage,@"Image folders containing filesystem links cannot be merged. Use a new filename or ordinary image files.");
        NSDictionary *existing=[fm attributesOfItemAtPath:target error:NULL];
        if(existing) {
            if(directory && [existing[NSFileType] isEqual:NSFileTypeDirectory])continue;
            if(!directory && [existing[NSFileType] isEqual:NSFileTypeRegular]) {
                NSData *first=[NSData dataWithContentsOfFile:url.path options:NSDataReadingMappedIfSafe error:error],*second=[NSData dataWithContentsOfFile:target options:NSDataReadingMappedIfSafe error:error];
                if(!first||!second)return NO;
                if([first isEqualToData:second])continue;
            }
            return Fail(error,SINErrorOccupied,[NSString stringWithFormat:@"The destination image folder already contains a different %@. No existing files were replaced. Choose another filename.",relative]);
        }
        NSMutableDictionary *operation=[@{@"path":target,@"source":url.path,@"directory":@(directory)} mutableCopy];
        if(!directory){NSData *bytes=[NSData dataWithContentsOfFile:url.path options:NSDataReadingMappedIfSafe error:error];if(!bytes)return NO;operation[@"fingerprint"]=[SINDocument fingerprintForData:bytes];}
        [plan addObject:operation];
    }
    if(enumerationError){if(error)*error=enumerationError;return NO;}
    for(NSDictionary *item in plan) {
        NSString *target=item[@"path"];
        if([item[@"directory"] boolValue]) {
            if(mkdir(target.fileSystemRepresentation,0700)!=0){if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:target}];return NO;}
            [created addObject:item];
        } else {
            if(![fm copyItemAtPath:item[@"source"] toPath:target error:error])return NO;
            [created addObject:@{@"path":target,@"fingerprint":item[@"fingerprint"]}];
            NSData *bytes=[NSData dataWithContentsOfFile:target options:NSDataReadingMappedIfSafe error:error];
            if(!bytes)return NO;
            if(![[SINDocument fingerprintForData:bytes] isEqual:item[@"fingerprint"]])return Fail(error,SINErrorConflict,@"An image changed while preparing Save As. No document was replaced. Review the image files and try again.");
        }
    }
    return YES;
}

@implementation SINDocument
- (instancetype)init {
    if ((self = [super init])) {
        _identifier = NSUUID.UUID.UUIDString; _text = @""; _savedText = @"";
        _encodingName = @"UTF-8"; _savedEncoding = @"UTF-8"; _newline = @"\n"; _savedNewline = @"\n";
        _untitledNumber = 1; _zoom = 100; _createdDate = NSDate.date; _modifiedDate = NSDate.date;
    }
    return self;
}
- (NSString *)name { return self.path ? self.path.lastPathComponent : self.draftName ?: [NSString stringWithFormat:@"Prompt %ld", (long)self.untitledNumber]; }
- (BOOL)modified { return ![self.text isEqual:self.savedText] || ![self.encodingName isEqual:self.savedEncoding] || ![self.newline isEqual:self.savedNewline]; }
+ (NSArray<NSString *> *)encodingNames { return @[@"UTF-8", @"UTF-8 with BOM", @"UTF-16 LE", @"UTF-16 BE", @"UTF-32 LE", @"UTF-32 BE", @"ANSI", @"Mac Roman", @"ISO-8859-1"]; }
+ (NSString *)fingerprintForData:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) { CC_LONG length = (CC_LONG)MIN(data.length - offset, UINT32_MAX); CC_SHA256_Update(&context, bytes + offset, length); offset += length; }
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString stringWithCapacity:64];
    for (NSInteger index=0; index<CC_SHA256_DIGEST_LENGTH; index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}
+ (instancetype)openPath:(NSString *)path error:(NSError **)error {
    path = FullPath(path);
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    const unsigned char *bytes = data.bytes;
    NSString *name = @"UTF-8"; NSUInteger skip = 0;
    if (data.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && !bytes[2] && !bytes[3]) { name = @"UTF-32 LE"; skip = 4; }
    else if (data.length >= 4 && !bytes[0] && !bytes[1] && bytes[2] == 0xFE && bytes[3] == 0xFF) { name = @"UTF-32 BE"; skip = 4; }
    else if (data.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) { name = @"UTF-8 with BOM"; skip = 3; }
    else if (data.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) { name = @"UTF-16 LE"; skip = 2; }
    else if (data.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) { name = @"UTF-16 BE"; skip = 2; }
    NSData *body = [data subdataWithRange:NSMakeRange(skip, data.length - skip)];
    NSString *raw = [[NSString alloc] initWithData:body encoding:Encoding(name)];
    if (!raw && !skip) { name = @"ANSI"; raw = [[NSString alloc] initWithData:data encoding:Encoding(name)]; }
    if (!raw || [raw rangeOfString:[NSString stringWithCharacters:(unichar[]){0} length:1]].location != NSNotFound) { Fail(error, SINErrorEncoding, @"This file contains binary data or an unsupported text encoding."); return nil; }
    SINDocument *document = [self new];
    document.path = path; document.text = Normalize(raw); document.savedText = document.text;
    document.encodingName = name; document.savedEncoding = name; document.newline = DetectNewline(raw); document.savedNewline = document.newline;
    document.fingerprint = [self fingerprintForData:data]; document.readOnly = ReadOnly(path);
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    document.createdDate = attributes[NSFileCreationDate] ?: NSDate.date; document.modifiedDate = attributes[NSFileModificationDate] ?: NSDate.date;
    return document;
}
- (BOOL)changedOnDisk:(NSError **)error {
    if (!self.path || !self.fingerprint) return NO;
    NSData *data = [NSData dataWithContentsOfFile:self.path options:0 error:error];
    return !data || ![[SINDocument fingerprintForData:data] isEqual:self.fingerprint];
}
- (BOOL)saveToPath:(NSString *)path overwriteConflict:(BOOL)overwrite error:(NSError **)error {
    path = FullPath(path);
    BOOL same = [path isEqual:self.path];
    if ((!same && [NSFileManager.defaultManager fileExistsAtPath:path])) return Fail(error, SINErrorOccupied, @"The destination already exists. Choose another name.");
    if ((same && self.readOnly) || ReadOnly(path)) {
        if (same && !self.modified) return YES;
        return Fail(error, SINErrorReadOnly, @"This file is read-only. Unlock it before saving changes.");
    }
    BOOL changed = same && [self changedOnDisk:NULL];
    if (changed && !overwrite) return Fail(error, SINErrorConflict, @"The file changed outside Sin AI Prompt. Reload it, save a copy, or explicitly overwrite it.");
    NSData *bytes = nil;
    if (!self.modified && self.path && ![self changedOnDisk:NULL]) bytes = [NSData dataWithContentsOfFile:self.path options:0 error:NULL];
    if (!bytes) bytes = Encode(self.text, self.encodingName, self.newline, error);
    if (!bytes || !AtomicWrite(bytes, path, NO, !same, error)) return NO;
    self.path = path; self.savedText = self.text; self.savedEncoding = self.encodingName; self.savedNewline = self.newline;
    self.fingerprint = [SINDocument fingerprintForData:bytes]; self.draftName = nil; self.readOnly = ReadOnly(path);
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    self.modifiedDate = attributes[NSFileModificationDate] ?: NSDate.date;
    return YES;
}
- (BOOL)saveAsToPath:(NSString *)path error:(NSError **)error { return [self saveAsToPath:path replaceExisting:NO error:error]; }
- (BOOL)saveAsToPath:(NSString *)path replaceExisting:(BOOL)replace error:(NSError **)error {
    path = FullPath(path);
    if ([path isEqual:self.path] && !replace) return [self saveToPath:path overwriteConflict:NO error:error];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *targetAttributes=[fm attributesOfItemAtPath:path error:NULL];
    BOOL occupied=targetAttributes!=nil;
    if(occupied && (!replace || ![targetAttributes[NSFileType] isEqual:NSFileTypeRegular])) return Fail(error,SINErrorOccupied,@"The destination already exists. Choose another name or explicitly approve replacing an ordinary file.");
    if(ReadOnly(path))return Fail(error,SINErrorReadOnly,@"The destination file is read-only. Unlock it before replacing it.");
    NSData *destinationBytes=occupied?[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error]:nil;
    if(occupied&&!destinationBytes)return NO;
    NSString *destinationFingerprint=destinationBytes?[SINDocument fingerprintForData:destinationBytes]:nil;
    NSString *oldFolder = self.path.stringByDeletingPathExtension;
    NSString *newFolder = path.stringByDeletingPathExtension;
    BOOL isDirectory = NO;
    BOOL copyFolder = oldFolder && ![oldFolder isEqual:newFolder] && [fm fileExistsAtPath:oldFolder isDirectory:&isDirectory] && isDirectory;
    if(copyFolder && ![[fm attributesOfItemAtPath:oldFolder error:NULL][NSFileType] isEqual:NSFileTypeDirectory])return Fail(error,SINErrorStorage,@"The source image folder is a filesystem link. Use ordinary image files before copying it.");
    NSMutableArray *created=[NSMutableArray array];
    if(copyFolder && !MergeAssets(oldFolder,newFolder,replace,created,error)){RollbackCreatedAssets(created);return NO;}
    NSString *original = self.text;
    if (self.path) self.text = [SINDocument rebaseHTML:self.text fromPath:self.path toPath:path assetFolderMoved:copyFolder];
    NSData *bytes=nil;
    if(!self.modified && self.path && ![self changedOnDisk:NULL])bytes=[NSData dataWithContentsOfFile:self.path options:0 error:NULL];
    if(!bytes)bytes=Encode(self.text,self.encodingName,self.newline,error);
    BOOL unchanged=NO;
    if(occupied){NSData *now=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];unchanged=now&&[[SINDocument fingerprintForData:now] isEqual:destinationFingerprint];}
    else unchanged=![fm fileExistsAtPath:path];
    if(!unchanged)Fail(error,SINErrorConflict,@"The destination changed while preparing Save As. No document was replaced. Try again after reviewing it.");
    if (!bytes || !unchanged || !AtomicWrite(bytes,path,NO,!occupied,error)) {
        self.text = original;
        RollbackCreatedAssets(created);
        return NO;
    }
    self.path=path;self.savedText=self.text;self.savedEncoding=self.encodingName;self.savedNewline=self.newline;
    self.fingerprint=[SINDocument fingerprintForData:bytes];self.draftName=nil;self.readOnly=ReadOnly(path);
    self.modifiedDate=[fm attributesOfItemAtPath:path error:NULL][NSFileModificationDate] ?: NSDate.date;
    return YES;
}
- (BOOL)renameToFilename:(NSString *)filename error:(NSError **)error {
    if (!filename.length || filename.length > 255 || ![filename.lastPathComponent isEqual:filename] || [filename isEqual:@"."] || [filename isEqual:@".."] || [filename rangeOfString:@":"].location != NSNotFound || ![filename stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return Fail(error, SINErrorInvalidName, @"Enter a filename without a folder path or colon.");
    if (!self.path) { self.draftName = filename; return YES; }
    if (self.readOnly || ReadOnly(self.path)) return Fail(error, SINErrorReadOnly, @"Unlock the document before renaming it.");
    NSString *originalPath = self.path, *destination = [originalPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:filename];
    if ([destination isEqual:originalPath]) return YES;
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:destination] && !CaseOnlySameFile(originalPath,destination)) return Fail(error, SINErrorOccupied, @"The new filename already exists.");
    if ([self changedOnDisk:NULL]) return Fail(error, SINErrorConflict, @"The file changed outside Sin AI Prompt. Reload it before renaming.");
    SINDocument *disk = [SINDocument openPath:originalPath error:error];
    if (!disk) return NO;
    NSString *oldFolder = originalPath.stringByDeletingPathExtension, *newFolder = destination.stringByDeletingPathExtension;
    BOOL directory = NO;
    BOOL moveFolder = ![oldFolder isEqual:newFolder] && [fm fileExistsAtPath:oldFolder isDirectory:&directory] && directory;
    if (moveFolder && [fm fileExistsAtPath:newFolder] && !CaseOnlySameFile(oldFolder,newFolder)) return Fail(error, SINErrorOccupied, @"The new image folder already exists.");
    NSString *rewrittenDisk = [SINDocument rebaseHTML:disk.text fromPath:originalPath toPath:destination assetFolderMoved:moveFolder];
    NSData *bytes = Encode(rewrittenDisk, disk.encodingName, disk.newline, error);
    if (!bytes) return NO;
    // Everything needed for rewriting is prepared before either item moves.
    if (!MoveKeepingCase(originalPath,destination,error)) return NO;
    BOOL moved = NO;
    if (moveFolder) {
        if (!MoveKeepingCase(oldFolder,newFolder,error)) { MoveKeepingCase(destination,originalPath,NULL); return NO; }
        moved = YES;
    }
    if (![rewrittenDisk isEqual:disk.text] && !AtomicWrite(bytes, destination, NO, NO, error)) {
        if (moved) MoveKeepingCase(newFolder,oldFolder,NULL);
        MoveKeepingCase(destination,originalPath,NULL);
        return NO;
    }
    self.text = [SINDocument rebaseHTML:self.text fromPath:originalPath toPath:destination assetFolderMoved:moveFolder];
    self.savedText = [SINDocument rebaseHTML:self.savedText fromPath:originalPath toPath:destination assetFolderMoved:moveFolder];
    self.path = destination;
    self.fingerprint = [SINDocument fingerprintForData:[NSData dataWithContentsOfFile:destination]];
    return YES;
}
- (BOOL)setFileReadOnly:(BOOL)readOnly error:(NSError **)error {
    if (self.path) {
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:self.path error:error];
        if (!attributes) return NO;
        NSUInteger mode = [attributes[NSFilePosixPermissions] unsignedIntegerValue];
        mode = readOnly ? mode & ~0222 : mode | 0200;
        if (![NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@(mode)} ofItemAtPath:self.path error:error]) return NO;
    }
    self.readOnly = readOnly; return YES;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *value = [@{@"identifier":self.identifier, @"text":self.text, @"savedText":self.savedText, @"encodingName":self.encodingName, @"savedEncoding":self.savedEncoding, @"newline":self.newline, @"savedNewline":self.savedNewline, @"untitledNumber":@(self.untitledNumber), @"autosave":@(self.autosave), @"pinned":@(self.pinned), @"readOnly":@(self.readOnly), @"zoom":@(self.zoom), @"selectionLocation":@(self.selection.location), @"selectionLength":@(self.selection.length), @"scroll":@(self.scroll), @"createdDate":@(self.createdDate.timeIntervalSince1970), @"modifiedDate":@(self.modifiedDate.timeIntervalSince1970)} mutableCopy];
    if (self.path) value[@"path"] = self.path;
    if (self.draftName) value[@"draftName"] = self.draftName;
    if (self.fingerprint) value[@"fingerprint"] = self.fingerprint;
    return value;
}
+ (instancetype)documentFromDictionary:(NSDictionary *)dictionary {
    SINDocument *doc = [self new];
    for (NSString *key in @[@"identifier", @"path", @"draftName", @"text", @"savedText", @"encodingName", @"savedEncoding", @"newline", @"savedNewline", @"fingerprint"]) if ([dictionary[key] isKindOfClass:NSString.class]) [doc setValue:dictionary[key] forKey:key];
    for (NSString *key in @[@"untitledNumber", @"autosave", @"pinned", @"readOnly", @"zoom", @"scroll"]) if ([dictionary[key] isKindOfClass:NSNumber.class]) [doc setValue:dictionary[key] forKey:key];
    if ([dictionary[@"createdDate"] isKindOfClass:NSNumber.class]) doc.createdDate = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"createdDate"] doubleValue]];
    if ([dictionary[@"modifiedDate"] isKindOfClass:NSNumber.class]) doc.modifiedDate = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"modifiedDate"] doubleValue]];
    NSUInteger location = MIN([dictionary[@"selectionLocation"] unsignedIntegerValue], doc.text.length);
    doc.selection = NSMakeRange(location, MIN([dictionary[@"selectionLength"] unsignedIntegerValue], doc.text.length-location));
    doc.zoom = MAX(10, MIN(500, doc.zoom));
    return doc;
}
@end

static NSString *RelativePath(NSString *file, NSString *folder) {
    NSArray *a = folder.stringByStandardizingPath.pathComponents, *b = file.stringByStandardizingPath.pathComponents;
    NSUInteger common = 0;
    while (common < a.count && common < b.count && [a[common] isEqual:b[common]]) common++;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger index = common; index < a.count; index++) [parts addObject:@".."];
    for (NSUInteger index = common; index < b.count; index++) [parts addObject:b[index]];
    return [parts componentsJoinedByString:@"/"];
}
static NSDictionary *VolumeProperties(NSString *path) {
    NSFileManager *fm=NSFileManager.defaultManager;
    while(path.length>1 && ![fm fileExistsAtPath:path]) path=path.stringByDeletingLastPathComponent;
    return [[NSURL fileURLWithPath:path] resourceValuesForKeys:@[NSURLVolumeSupportsCaseSensitiveNamesKey,NSURLVolumeIdentifierKey] error:NULL];
}
static NSRange AssetFolderPrefix(NSString *path, NSString *folder) {
    NSString *prefix=[folder stringByAppendingString:@"/"];
    NSRange exact=[path rangeOfString:prefix options:NSAnchoredSearch];
    if(exact.location!=NSNotFound)return exact;
    NSRange folded=[path rangeOfString:prefix options:NSAnchoredSearch|NSCaseInsensitiveSearch];
    if(folded.location==NSNotFound)return folded;
    // Query an existing parent because the source folder has already moved
    // when the open unsaved buffer is rewritten after committing a rename.
    NSDictionary *original=VolumeProperties(folder.stringByDeletingLastPathComponent),*source=VolumeProperties(path);
    NSNumber *caseSensitive=original[NSURLVolumeSupportsCaseSensitiveNamesKey];
    if(caseSensitive && !caseSensitive.boolValue && original[NSURLVolumeIdentifierKey] && [original[NSURLVolumeIdentifierKey] isEqual:source[NSURLVolumeIdentifierKey]])return folded;
    return NSMakeRange(NSNotFound,0);
}
static NSString *RebaseURL(NSString *source, NSURL *oldBase, NSURL *newBase, NSString *oldFolder, NSString *newFolder, BOOL moved) {
    NSString *value = [source stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    if (!value.length || [value hasPrefix:@"#"]) return source;
    NSURL *url = [[NSURL URLWithString:value relativeToURL:oldBase] absoluteURL];
    if (!url.isFileURL) return source;
    NSString *path = url.path.stringByStandardizingPath;
    NSRange prefix=moved ? AssetFolderPrefix(path,oldFolder) : NSMakeRange(NSNotFound,0);
    BOOL matched = prefix.location!=NSNotFound;
    if (matched) path = [newFolder stringByAppendingPathComponent:[path substringFromIndex:NSMaxRange(prefix)]];
    BOOL absolute = [[NSURL URLWithString:value] scheme].length > 0 || [value hasPrefix:@"/"];
    if (!matched && absolute) return source;
    NSString *result;
    if (absolute || !newBase.isFileURL) result = [NSURL fileURLWithPath:path].absoluteString;
    else result = [RelativePath(path, newBase.hasDirectoryPath ? newBase.path : newBase.path.stringByDeletingLastPathComponent) stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    if (url.query.length) result = [result stringByAppendingFormat:@"?%@", url.query];
    if (url.fragment.length) result = [result stringByAppendingFormat:@"#%@", url.fragment];
    return [result stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
}
static NSString *RebaseCSS(NSString *css, NSURL *oldBase, NSURL *newBase, NSString *oldFolder, NSString *newFolder, BOOL moved) {
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"url\\(\\s*(?:([\"'])(.*?)\\1|([^)'\"]*?))\\s*\\)" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSMutableString *result = css.mutableCopy;
    for (NSTextCheckingResult *match in [[expression matchesInString:css options:0 range:NSMakeRange(0,css.length)] reverseObjectEnumerator]) {
        NSRange range = [match rangeAtIndex:2]; if (range.location == NSNotFound) range = [match rangeAtIndex:3];
        [result replaceCharactersInRange:range withString:RebaseURL([css substringWithRange:range], oldBase, newBase, oldFolder, newFolder, moved)];
    }
    return result;
}
@implementation SINDocument (Rebase)
+ (NSString *)rebaseHTML:(NSString *)html fromPath:(NSString *)oldPath toPath:(NSString *)newPath assetFolderMoved:(BOOL)moved {
    NSURL *oldBase = [NSURL fileURLWithPath:oldPath], *newBase = [NSURL fileURLWithPath:newPath];
    NSRegularExpression *baseExpression = [NSRegularExpression regularExpressionWithPattern:@"<base\\b[^>]*\\bhref\\s*=\\s*(['\"])(.*?)\\1" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *baseMatch = [baseExpression firstMatchInString:html options:0 range:NSMakeRange(0,html.length)];
    if (baseMatch) {
        NSString *base = [html substringWithRange:[baseMatch rangeAtIndex:2]];
        oldBase = [[NSURL URLWithString:base relativeToURL:oldBase] absoluteURL] ?: oldBase;
        newBase = [[NSURL URLWithString:base relativeToURL:newBase] absoluteURL] ?: newBase;
    }
    // Match complete comments/scripts so attribute-like source text is never edited.
    NSRegularExpression *tags = [NSRegularExpression regularExpressionWithPattern:@"<!--[\\s\\S]*?-->|<(?:script|style)\\b[\\s\\S]*?</(?:script|style)\\s*>|<(?:[^>\"']|\"[^\"]*\"|'[^']*')+>" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSRegularExpression *sources = [NSRegularExpression regularExpressionWithPattern:@"([\\w:-]+)\\s*=\\s*(?:([\"'])(.*?)\\2|([^\\s>]+))" options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:NULL];
    NSMutableString *result = html.mutableCopy;
    for (NSTextCheckingResult *tagMatch in [[tags matchesInString:html options:0 range:NSMakeRange(0,html.length)] reverseObjectEnumerator]) {
        NSString *tag = [html substringWithRange:tagMatch.range];
        NSString *lower = tag.lowercaseString;
        if ([lower hasPrefix:@"<!--"] || [lower hasPrefix:@"<script"]) continue;
        NSMutableString *replacement = tag.mutableCopy;
        if ([lower hasPrefix:@"<style"]) {
            NSRange start = [tag rangeOfString:@">"], end = [tag rangeOfString:@"</style" options:NSCaseInsensitiveSearch | NSBackwardsSearch];
            if (start.location != NSNotFound && end.location != NSNotFound && end.location > NSMaxRange(start)) {
                NSRange body = NSMakeRange(NSMaxRange(start), end.location - NSMaxRange(start));
                [replacement replaceCharactersInRange:body withString:RebaseCSS([tag substringWithRange:body], oldBase, newBase, oldPath.stringByDeletingPathExtension, newPath.stringByDeletingPathExtension, moved)];
            }
            [result replaceCharactersInRange:tagMatch.range withString:replacement];
            continue;
        }
        for (NSTextCheckingResult *match in [[sources matchesInString:tag options:0 range:NSMakeRange(0,tag.length)] reverseObjectEnumerator]) {
            NSString *attribute = [tag substringWithRange:[match rangeAtIndex:1]].lowercaseString;
            if (![@[@"src", @"poster", @"background", @"style"] containsObject:attribute] && !([attribute isEqual:@"href"] && [lower hasPrefix:@"<link"])) continue;
            NSRange range = [match rangeAtIndex:3]; if (range.location == NSNotFound) range = [match rangeAtIndex:4];
            NSString *value = [tag substringWithRange:range];
            NSString *updated = [attribute isEqual:@"style"] ? RebaseCSS(value, oldBase, newBase, oldPath.stringByDeletingPathExtension, newPath.stringByDeletingPathExtension, moved) : RebaseURL(value, oldBase, newBase, oldPath.stringByDeletingPathExtension, newPath.stringByDeletingPathExtension, moved);
            [replacement replaceCharactersInRange:range withString:updated];
        }
        [result replaceCharactersInRange:tagMatch.range withString:replacement];
    }
    return result;
}
@end
