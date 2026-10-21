#import "SINProjects.h"
#import "SINDocument.h"
#import <sys/stat.h>
#import <stdio.h>
#import <unistd.h>

static BOOL ProjectFail(NSError **error, SINErrorCode code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SINErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static BOOL ProjectPOSIX(NSError **error, NSString *path) {
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}];
    return NO;
}
static NSString *ProjectPath(NSString *path) {
    path=path.stringByExpandingTildeInPath.stringByStandardizingPath;
    return path.isAbsolutePath ? path : [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
}
static BOOL ProjectHTML(NSString *path) { return [@[@"html",@"htm"] containsObject:path.pathExtension.lowercaseString]; }
static BOOL ProjectExists(NSString *path) { struct stat s; return lstat(path.fileSystemRepresentation,&s)==0; }
static NSString *ProjectHash(NSString *path,NSError **error) {
    NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    return data?[SINDocument fingerprintForData:data]:nil;
}
static NSString *ProjectNormalize(NSString *html) { return [[html stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"]; }
static BOOL ProjectRename(NSString *source,NSString *destination,NSError **error) {
    if(renamex_np(source.fileSystemRepresentation,destination.fileSystemRepresentation,RENAME_EXCL)==0)return YES;
    return ProjectPOSIX(error,destination);
}
static NSDictionary *ProjectIdentity(NSString *path,NSError **error) {
    struct stat s;
    if(lstat(path.fileSystemRepresentation,&s)!=0){ProjectPOSIX(error,path);return nil;}
    if(!S_ISREG(s.st_mode)&&!S_ISDIR(s.st_mode)) { ProjectFail(error,SINErrorStorage,[NSString stringWithFormat:@"Linked or special files cannot be moved with a project: %@",path]);return nil; }
    return @{@"directory":@(S_ISDIR(s.st_mode)),@"mode":@(s.st_mode&07777),@"flags":@(s.st_flags),@"device":@(s.st_dev),@"inode":@(s.st_ino)};
}
static BOOL ProjectTreeVisit(NSString *root,NSString *relative,NSMutableDictionary *manifest,NSError **error) {
    NSString *path=relative.length?[root stringByAppendingPathComponent:relative]:root;
    NSDictionary *identity=ProjectIdentity(path,error);if(!identity)return NO;
    NSMutableDictionary *entry=[@{@"directory":identity[@"directory"],@"mode":identity[@"mode"],@"flags":identity[@"flags"]} mutableCopy];
    BOOL directory=[identity[@"directory"] boolValue];
    if(!directory){NSString *hash=ProjectHash(path,error);if(!hash)return NO;entry[@"fingerprint"]=hash;}
    manifest[relative]=entry;
    if(directory) {
        NSArray *children=[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:error];if(!children)return NO;
        for(NSString *child in children)if(!ProjectTreeVisit(root,relative.length?[relative stringByAppendingPathComponent:child]:child,manifest,error))return NO;
    }
    return YES;
}
static NSDictionary *ProjectTree(NSString *root,NSError **error) {
    NSMutableDictionary *manifest=[NSMutableDictionary dictionary];
    return ProjectTreeVisit(root,@"",manifest,error)?manifest:nil;
}
static BOOL ProjectVerifyTree(NSString *path,NSDictionary *expected,NSError **error) {
    NSDictionary *actual=ProjectTree(path,error);if(!actual)return NO;
    return [actual isEqual:expected] || ProjectFail(error,SINErrorConflict,[NSString stringWithFormat:@"An image folder changed while preparing the project move: %@",path]);
}
static NSString *ProjectCanonical(NSString *path) { return ProjectPath(path).stringByResolvingSymlinksInPath; }
static BOOL ProjectOverlap(NSString *a,NSString *b) {
    a=ProjectCanonical(a);b=ProjectCanonical(b);
    if(![SINProjects caseSensitiveAtPath:a] && ![SINProjects caseSensitiveAtPath:b]) { a=a.lowercaseString;b=b.lowercaseString; }
    return [a isEqual:b]||[a hasPrefix:[b stringByAppendingString:@"/"]]||[b hasPrefix:[a stringByAppendingString:@"/"]];
}

@interface SINProjectMoveSnapshot ()
@property(nonatomic,copy,readwrite) NSString *sourcePath,*destinationPath,*sourceAssets,*destinationAssets,*fingerprint,*encodingName,*newline;
@property(nonatomic,copy) NSDictionary *documentState,*identity,*attributes,*assetManifest;
@end
@implementation SINProjectMoveSnapshot
+ (instancetype)readPath:(NSString *)path destinationFolder:(NSString *)folder error:(NSError **)error {
    path=ProjectPath(path);folder=ProjectPath(folder);
    if(!ProjectHTML(path)){ProjectFail(error,SINErrorInvalidName,@"Only saved HTML documents can be moved into a project.");return nil;}
    NSDictionary *identity=ProjectIdentity(path,error);if(!identity)return nil;
    if([identity[@"directory"] boolValue]){ProjectFail(error,SINErrorStorage,@"Choose an HTML file, not a folder.");return nil;}
    SINDocument *disk=[SINDocument openPath:path error:error];if(!disk)return nil;
    SINProjectMoveSnapshot *snapshot=[self new];snapshot.sourcePath=path;snapshot.destinationPath=[folder stringByAppendingPathComponent:path.lastPathComponent];
    snapshot.html=disk.text;snapshot.fingerprint=disk.fingerprint;snapshot.encodingName=disk.encodingName;snapshot.newline=disk.newline;
    snapshot.documentState=disk.dictionaryRepresentation;snapshot.identity=identity;
    snapshot.attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:error];if(!snapshot.attributes)return nil;
    NSString *assets=path.stringByDeletingPathExtension;
    if(ProjectExists(assets)) {
        NSDictionary *assetIdentity=ProjectIdentity(assets,error);if(!assetIdentity)return nil;
        if([assetIdentity[@"directory"] boolValue]) {
            snapshot.sourceAssets=assets;snapshot.destinationAssets=snapshot.destinationPath.stringByDeletingPathExtension;
            snapshot.assetManifest=ProjectTree(assets,error);if(!snapshot.assetManifest)return nil;
        }
    }
    return snapshot;
}
@end

@interface SINProjectMoveResult ()
@property(nonatomic,copy,readwrite) NSString *sourcePath,*destinationPath,*html,*fingerprint,*cleanupWarning;
@property(nonatomic,strong,readwrite) NSDate *createdDate,*modifiedDate;
@property(nonatomic,readwrite) BOOL readOnly;
@end
@implementation SINProjectMoveResult
@end

@interface SINProjectPrepared : NSObject
@property(nonatomic,strong) SINProjectMoveSnapshot *snapshot;
@property(nonatomic,strong) SINProjectMoveResult *result;
@property(nonatomic,copy) NSString *stage,*recovery;
@property(nonatomic) BOOL htmlReserved,assetsReserved,htmlPublished,assetsPublished;
@end
@implementation SINProjectPrepared
@end

static NSString *ProjectStagedHTML(SINProjectPrepared *item) { return [item.stage stringByAppendingPathComponent:@"document.html"]; }
static NSString *ProjectStagedAssets(SINProjectPrepared *item) { return [item.stage stringByAppendingPathComponent:@"assets"]; }
static NSString *ProjectOriginalHTML(SINProjectPrepared *item) { return [item.recovery stringByAppendingPathComponent:@"document.html"]; }
static NSString *ProjectOriginalAssets(SINProjectPrepared *item) { return [item.recovery stringByAppendingPathComponent:@"assets"]; }
static BOOL ProjectVerifySource(SINProjectMoveSnapshot *snapshot,NSString *path,NSError **error) {
    NSDictionary *identity=ProjectIdentity(path,error);if(!identity)return NO;
    if(![identity isEqual:snapshot.identity])return ProjectFail(error,SINErrorConflict,[NSString stringWithFormat:@"The document's identity or file permissions changed while preparing the project move: %@",snapshot.sourcePath]);
    NSString *hash=ProjectHash(path,error);if(!hash)return NO;
    return [hash isEqual:snapshot.fingerprint] || ProjectFail(error,SINErrorConflict,[NSString stringWithFormat:@"The document changed outside Sin AI Prompt: %@",snapshot.sourcePath]);
}
static BOOL ProjectPreflight(NSArray<SINProjectMoveSnapshot *> *snapshots,NSError **error) {
    NSMutableArray *sources=[NSMutableArray array],*targets=[NSMutableArray array];
    for(SINProjectMoveSnapshot *snapshot in snapshots) {
        if(!ProjectHTML(snapshot.sourcePath)||![snapshot.sourcePath.lastPathComponent isEqual:snapshot.destinationPath.lastPathComponent])return ProjectFail(error,SINErrorInvalidName,@"A project move must keep the HTML filename.");
        BOOL directory=NO;
        if(![NSFileManager.defaultManager fileExistsAtPath:snapshot.destinationPath.stringByDeletingLastPathComponent isDirectory:&directory]||!directory)return ProjectFail(error,SINErrorStorage,@"The destination project folder no longer exists.");
        NSString *assets=snapshot.sourcePath.stringByDeletingPathExtension;
        NSDictionary *assetIdentity=ProjectExists(assets)?ProjectIdentity(assets,error):nil;
        if(ProjectExists(assets)&&!assetIdentity)return NO;
        BOOL hasAssets=[assetIdentity[@"directory"] boolValue];
        if(hasAssets != (snapshot.sourceAssets!=nil) || (hasAssets && (![snapshot.sourceAssets isEqual:assets]||![snapshot.destinationAssets isEqual:snapshot.destinationPath.stringByDeletingPathExtension])))return ProjectFail(error,SINErrorConflict,@"The document's corresponding image folder changed while preparing the move.");
        for(NSString *target in @[snapshot.destinationPath,snapshot.destinationPath.stringByDeletingPathExtension]) {
            if(ProjectExists(target))return ProjectFail(error,SINErrorOccupied,[NSString stringWithFormat:@"The project already contains this file or its corresponding image folder: %@",target]);
            [targets addObject:target];
        }
        [sources addObject:snapshot.sourcePath];
        if(snapshot.sourceAssets){[sources addObject:snapshot.sourceAssets];if(!ProjectVerifyTree(snapshot.sourceAssets,snapshot.assetManifest,error))return NO;}
        if(!ProjectVerifySource(snapshot,snapshot.sourcePath,error))return NO;
    }
    for(NSArray *paths in @[sources,targets])for(NSUInteger i=0;i<paths.count;i++)for(NSUInteger j=i+1;j<paths.count;j++)
        if(ProjectOverlap(paths[i],paths[j])||SINPathsReferToSameFile(paths[i],paths[j]))return ProjectFail(error,SINErrorOccupied,@"The selected documents or image folders overlap or share a destination name. Choose separate documents.");
    for(NSString *source in sources)for(NSString *target in targets)if(ProjectOverlap(source,target))return ProjectFail(error,SINErrorOccupied,@"A project destination cannot overlap a selected document or image folder.");
    return YES;
}
static BOOL ProjectStage(SINProjectPrepared *item,NSError **error) {
    SINProjectMoveSnapshot *snapshot=item.snapshot;NSFileManager *fm=NSFileManager.defaultManager;
    if(mkdir(item.stage.fileSystemRepresentation,0700)!=0)return ProjectPOSIX(error,item.stage);
    if(mkdir(item.recovery.fileSystemRepresentation,0700)!=0)return ProjectPOSIX(error,item.recovery);
    if(!ProjectVerifySource(snapshot,snapshot.sourcePath,error))return NO;
    SINDocument *copy=[SINDocument documentFromDictionary:snapshot.documentState];copy.text=ProjectNormalize(snapshot.html);copy.readOnly=NO;
    if(![copy saveToPath:ProjectStagedHTML(item) overwriteConflict:NO error:error])return NO;
    NSMutableDictionary *attributes=[NSMutableDictionary dictionary];
    for(NSString *key in @[NSFilePosixPermissions,NSFileCreationDate,NSFileModificationDate,NSFileExtensionHidden])if(snapshot.attributes[key])attributes[key]=snapshot.attributes[key];
    if(![fm setAttributes:attributes ofItemAtPath:ProjectStagedHTML(item) error:error])return NO;
    if(chflags(ProjectStagedHTML(item).fileSystemRepresentation,[snapshot.identity[@"flags"] unsignedIntValue])!=0)return ProjectPOSIX(error,ProjectStagedHTML(item));
    if(![ProjectHash(ProjectStagedHTML(item),error) isEqual:copy.fingerprint])return ProjectFail(error,SINErrorStorage,@"The staged project HTML could not be verified.");
    if(snapshot.sourceAssets && (![fm copyItemAtPath:snapshot.sourceAssets toPath:ProjectStagedAssets(item) error:error]||!ProjectVerifyTree(ProjectStagedAssets(item),snapshot.assetManifest,error)))return NO;
    SINProjectMoveResult *result=[SINProjectMoveResult new];result.sourcePath=snapshot.sourcePath;result.destinationPath=snapshot.destinationPath;result.html=copy.text;result.fingerprint=copy.fingerprint;
    result.createdDate=snapshot.attributes[NSFileCreationDate]?:NSDate.date;result.modifiedDate=snapshot.attributes[NSFileModificationDate]?:NSDate.date;
    result.readOnly=([snapshot.identity[@"mode"] unsignedIntegerValue]&0222)==0;
    item.result=result;return YES;
}
static void ProjectRecordFailure(NSMutableArray *failures,NSString *path,NSError *error) { [failures addObject:[NSString stringWithFormat:@"%@: %@",path,error.localizedDescription?:@"The operation failed."]]; }
// Only called for private stage/recovery directories. Clear copied read-only
// flags so cleanup works without changing the published files' locks.
static BOOL ProjectDeletePrivateTree(NSString *path,NSError **error) {
    struct stat s;if(lstat(path.fileSystemRepresentation,&s)!=0)return errno==ENOENT?YES:ProjectPOSIX(error,path);
    if(S_ISDIR(s.st_mode)) {
        if((s.st_flags&(UF_IMMUTABLE|UF_APPEND))&&chflags(path.fileSystemRepresentation,s.st_flags&~(UF_IMMUTABLE|UF_APPEND))!=0)return ProjectPOSIX(error,path);
        if(chmod(path.fileSystemRepresentation,(s.st_mode&07777)|0700)!=0)return ProjectPOSIX(error,path);
        NSArray *children=[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:error];if(!children)return NO;
        for(NSString *child in children)if(!ProjectDeletePrivateTree([path stringByAppendingPathComponent:child],error))return NO;
        if(rmdir(path.fileSystemRepresentation)!=0)return ProjectPOSIX(error,path);
    } else {
        if(!S_ISLNK(s.st_mode)&&(s.st_flags&(UF_IMMUTABLE|UF_APPEND))&&chflags(path.fileSystemRepresentation,s.st_flags&~(UF_IMMUTABLE|UF_APPEND))!=0)return ProjectPOSIX(error,path);
        if(unlink(path.fileSystemRepresentation)!=0)return ProjectPOSIX(error,path);
    }
    return YES;
}
static void ProjectCleanup(NSString *path,NSMutableArray *failures) {
    NSError *error=nil;if(!ProjectDeletePrivateTree(path,&error))ProjectRecordFailure(failures,path,error);
}
static void ProjectRollback(SINProjectPrepared *item,NSMutableArray *failures) {
    NSError *error=nil;BOOL changed=NO;SINProjectMoveSnapshot *snapshot=item.snapshot;
    if(item.htmlPublished && ![ProjectHash(snapshot.destinationPath,&error) isEqual:item.result.fingerprint])changed=YES;
    if(item.assetsPublished && !ProjectVerifyTree(snapshot.destinationAssets,snapshot.assetManifest,&error))changed=YES;
    if(changed)ProjectRecordFailure(failures,snapshot.destinationPath,error?:[NSError errorWithDomain:SINErrorDomain code:SINErrorConflict userInfo:@{NSLocalizedDescriptionKey:@"The published pair changed externally and has been retained."}]);
    if(!changed&&item.htmlPublished&&!ProjectRename(snapshot.destinationPath,ProjectStagedHTML(item),&error))ProjectRecordFailure(failures,snapshot.destinationPath,error);
    if(!changed&&item.assetsPublished&&!ProjectRename(snapshot.destinationAssets,ProjectStagedAssets(item),&error))ProjectRecordFailure(failures,snapshot.destinationAssets,error);
    if(item.htmlReserved&&!ProjectRename(ProjectOriginalHTML(item),snapshot.sourcePath,&error))ProjectRecordFailure(failures,ProjectOriginalHTML(item),error);
    if(item.assetsReserved&&!ProjectRename(ProjectOriginalAssets(item),snapshot.sourceAssets,&error))ProjectRecordFailure(failures,ProjectOriginalAssets(item),error);
}

@implementation SINProjects
+ (BOOL)caseSensitiveAtPath:(NSString *)path {
    path=ProjectPath(path);
    while(!ProjectExists(path)&&path.length>1)path=path.stringByDeletingLastPathComponent;
    NSNumber *sensitive=nil;[[NSURL fileURLWithPath:path] getResourceValue:&sensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:NULL];
    return sensitive?sensitive.boolValue:YES;
}
+ (NSString *)displaySuffixForDocumentPath:(NSString *)path {
    if(!path||!ProjectHTML(path))return @"";
    NSString *folder=ProjectPath(path).stringByDeletingLastPathComponent;
    while(folder.length>1) {
        NSString *name=folder.lastPathComponent;
        if([name rangeOfString:@"Project - " options:NSCaseInsensitiveSearch|NSAnchoredSearch].location==0) {
            NSString *project=[[name substringFromIndex:10] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if(project.length)return [NSString stringWithFormat:@" (%@)",project];
        }
        folder=folder.stringByDeletingLastPathComponent;
    }
    return @"";
}
+ (NSString *)createProjectInDirectory:(NSString *)directory name:(NSString *)name error:(NSError **)error {
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!name.length||[name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]].location!=NSNotFound||[name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound||[name isEqual:@"."]||[name isEqual:@".."]) { ProjectFail(error,SINErrorInvalidName,@"Enter a project name without slashes, colons or control characters.");return nil; }
    directory=ProjectPath(directory);BOOL isDirectory=NO;
    if(![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory]||!isDirectory){ProjectFail(error,SINErrorStorage,@"The parent folder no longer exists.");return nil;}
    NSString *path=[directory stringByAppendingPathComponent:[@"Project - " stringByAppendingString:name]];
    if(mkdir(path.fileSystemRepresentation,0755)!=0){if(errno==EEXIST)ProjectFail(error,SINErrorOccupied,@"A project with that name already exists in this folder.");else ProjectPOSIX(error,path);return nil;}
    return path;
}
+ (BOOL)rememberProjectFolder:(NSString *)folder settings:(NSMutableDictionary *)settings error:(NSError **)error {
    folder=ProjectCanonical(folder);BOOL directory=NO;
    if(![NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&directory]||!directory)return ProjectFail(error,SINErrorStorage,@"The project folder no longer exists.");
    NSMutableArray *known=[NSMutableArray array];id stored=settings[@"projectFolders"];
    if([stored isKindOfClass:NSArray.class])for(id path in stored)if([path isKindOfClass:NSString.class])[known addObject:path];
    for(NSString *path in known)if([ProjectCanonical(path) isEqual:folder]||SINPathsReferToSameFile(path,folder))return YES;
    [known addObject:folder];settings[@"projectFolders"]=known;return YES;
}
+ (NSArray<NSString *> *)knownProjectFoldersInSettings:(NSDictionary *)settings {
    NSMutableArray *known=[NSMutableArray array];id stored=settings[@"projectFolders"];
    if([stored isKindOfClass:NSArray.class])for(id value in stored) {
        if(![value isKindOfClass:NSString.class])continue;
        NSString *path=ProjectCanonical(value);BOOL directory=NO;
        if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]||!directory)continue;
        BOOL duplicate=NO;for(NSString *other in known)if([path isEqual:other]||SINPathsReferToSameFile(path,other)){duplicate=YES;break;}
        if(!duplicate)[known addObject:path];
    }
    return [known sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){NSComparisonResult result=[a.lastPathComponent localizedStandardCompare:b.lastPathComponent];return result==NSOrderedSame?[a compare:b]:result;}];
}
+ (NSArray<NSDictionary *> *)referenceMovesForSnapshots:(NSArray<SINProjectMoveSnapshot *> *)snapshots {
    NSMutableArray *moves=[NSMutableArray array];
    for(SINProjectMoveSnapshot *snapshot in snapshots) {
        BOOL sourceCaseSensitive=[self caseSensitiveAtPath:snapshot.sourcePath];
        [moves addObject:@{@"oldUrl":[NSURL fileURLWithPath:snapshot.sourcePath].absoluteString,@"newUrl":[NSURL fileURLWithPath:snapshot.destinationPath].absoluteString,@"directory":@NO,@"caseSensitive":@(sourceCaseSensitive)}];
        if(snapshot.sourceAssets) {
            [moves addObject:@{@"oldUrl":[NSURL fileURLWithPath:snapshot.sourceAssets isDirectory:YES].absoluteString,@"newUrl":[NSURL fileURLWithPath:snapshot.destinationAssets isDirectory:YES].absoluteString,@"directory":@YES,@"caseSensitive":@(sourceCaseSensitive)}];
            // An insensitive source can legally use different filename casing in
            // HTML. Preserve the actual directory-entry spelling on a sensitive
            // destination, including each image and every nested folder.
            if(!sourceCaseSensitive&&[self caseSensitiveAtPath:snapshot.destinationPath])for(NSString *relative in [snapshot.assetManifest.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                if(!relative.length)continue;
                BOOL directory=[snapshot.assetManifest[relative][@"directory"] boolValue];
                [moves addObject:@{@"oldUrl":[NSURL fileURLWithPath:[snapshot.sourceAssets stringByAppendingPathComponent:relative] isDirectory:directory].absoluteString,@"newUrl":[NSURL fileURLWithPath:[snapshot.destinationAssets stringByAppendingPathComponent:relative] isDirectory:directory].absoluteString,@"directory":@(directory),@"caseSensitive":@NO}];
            }
        }
    }
    return moves;
}
+ (NSArray<SINProjectMoveResult *> *)commitSnapshots:(NSArray<SINProjectMoveSnapshot *> *)snapshots progress:(void (^)(NSUInteger,NSUInteger))progress error:(NSError **)error {
    NSError *failure=nil;if(!ProjectPreflight(snapshots,&failure)){if(error)*error=failure;return nil;}
    NSMutableArray<SINProjectPrepared *> *prepared=[NSMutableArray array];BOOL success=YES;
    for(SINProjectMoveSnapshot *snapshot in snapshots) {
        SINProjectPrepared *item=[SINProjectPrepared new];item.snapshot=snapshot;
        item.stage=[snapshot.destinationPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".sin-project-stage-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        item.recovery=[snapshot.sourcePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".sin-project-recovery-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [prepared addObject:item];if(!ProjectStage(item,&failure)){success=NO;break;}
        if(progress)progress(prepared.count,snapshots.count*2);
    }
    if(success)for(SINProjectPrepared *item in prepared) {
        if(!ProjectVerifySource(item.snapshot,item.snapshot.sourcePath,&failure)||(item.snapshot.sourceAssets&&!ProjectVerifyTree(item.snapshot.sourceAssets,item.snapshot.assetManifest,&failure))){success=NO;break;}
    }
    if(success)for(SINProjectPrepared *item in prepared) {
        if(!ProjectRename(item.snapshot.sourcePath,ProjectOriginalHTML(item),&failure)){success=NO;break;}item.htmlReserved=YES;
        if(item.snapshot.sourceAssets){if(!ProjectRename(item.snapshot.sourceAssets,ProjectOriginalAssets(item),&failure)){success=NO;break;}item.assetsReserved=YES;}
    }
    if(success)for(SINProjectPrepared *item in prepared) {
        if(!ProjectVerifySource(item.snapshot,ProjectOriginalHTML(item),&failure)||(item.assetsReserved&&!ProjectVerifyTree(ProjectOriginalAssets(item),item.snapshot.assetManifest,&failure))){success=NO;break;}
    }
    if(success)for(NSUInteger index=0;index<prepared.count;index++) {
        SINProjectPrepared *item=prepared[index];
        if(item.snapshot.destinationAssets){if(!ProjectRename(ProjectStagedAssets(item),item.snapshot.destinationAssets,&failure)){success=NO;break;}item.assetsPublished=YES;}
        if(!ProjectRename(ProjectStagedHTML(item),item.snapshot.destinationPath,&failure)){success=NO;break;}item.htmlPublished=YES;
        if(progress)progress(snapshots.count+index+1,snapshots.count*2);
    }
    if(!success) {
        NSMutableArray *failures=[NSMutableArray array];for(SINProjectPrepared *item in prepared.reverseObjectEnumerator)ProjectRollback(item,failures);
        if(!failures.count)for(SINProjectPrepared *item in prepared){ProjectCleanup(item.stage,failures);ProjectCleanup(item.recovery,failures);}
        NSString *recovery=failures.count?[NSString stringWithFormat:@" Recovery copies were retained where needed: %@",[failures componentsJoinedByString:@"; "]]:@" All original documents and image folders remain at their source paths.";
        ProjectFail(error,SINErrorStorage,[NSString stringWithFormat:@"The project move could not complete. %@%@",failure.localizedDescription?:@"The filesystem operation failed.",recovery]);return nil;
    }
    NSMutableArray *results=[NSMutableArray array];
    for(SINProjectPrepared *item in prepared) {
        NSMutableArray *warnings=[NSMutableArray array];NSError *check=nil;
        if(!ProjectVerifySource(item.snapshot,ProjectOriginalHTML(item),&check)||(item.assetsReserved&&!ProjectVerifyTree(ProjectOriginalAssets(item),item.snapshot.assetManifest,&check)))ProjectRecordFailure(warnings,item.recovery,check);
        else ProjectCleanup(item.recovery,warnings);
        ProjectCleanup(item.stage,warnings);if(warnings.count)item.result.cleanupWarning=[warnings componentsJoinedByString:@"; "];
        [results addObject:item.result];
    }
    return results;
}
@end
