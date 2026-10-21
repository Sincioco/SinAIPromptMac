#import <Foundation/Foundation.h>
#import "SINProjects.h"
#import "SINDocument.h"
#import <sys/stat.h>

static NSUInteger checks;
static void Check(BOOL condition,NSString *message) { checks++;if(!condition){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);} }
static void Put(NSString *path,NSString *text) { NSError *error=nil;Check([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error],error.localizedDescription?:@"write fixture"); }
static NSString *Read(NSString *path) { return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]; }
static NSString *Folder(NSString *parent,NSString *name) { NSString *path=[parent stringByAppendingPathComponent:name];Check([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL],@"create fixture directory");return path; }
static SINProjectMoveSnapshot *Snapshot(NSString *source,NSString *destination) { NSError *error=nil;SINProjectMoveSnapshot *snapshot=[SINProjectMoveSnapshot readPath:source destinationFolder:destination error:&error];Check(snapshot!=nil,error.localizedDescription?:@"read project snapshot");return snapshot; }
static NSUInteger Debris(NSString *root) { NSUInteger count=0;for(NSString *path in [NSFileManager.defaultManager enumeratorAtPath:root])if([path.lastPathComponent hasPrefix:@".sin-project-"])count++;return count; }
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SinAI-project-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];Folder(root,@"");
    NSString *project=[SINProjects createProjectInDirectory:root name:@" 人物與世界 🌌 " error:&error];
    Check([project.lastPathComponent isEqual:@"Project - 人物與世界 🌌"],@"project uses a trimmed physical prefixed Unicode folder");
    Check(![SINProjects createProjectInDirectory:root name:@"../escape" error:&error] && ![SINProjects createProjectInDirectory:root name:@"人物與世界 🌌" error:&error],@"project rejects traversal and existing destination");
    Check(![SINProjects createProjectInDirectory:root name:[NSString stringWithCharacters:(unichar[]){'n','u','l',0,'b','a','d'} length:7] error:&error]&&![SINProjects createProjectInDirectory:root name:@"first\nsecond" error:&error],@"project rejects NUL and control characters before filesystem creation");
    NSMutableDictionary *settings=NSMutableDictionary.new;
    Check([SINProjects rememberProjectFolder:project settings:settings error:&error]&&[SINProjects rememberProjectFolder:[project stringByAppendingString:@"/"] settings:settings error:&error],@"project registration accepts canonical duplicate");
    settings[@"projectFolders"]=[settings[@"projectFolders"] arrayByAddingObject:[root stringByAppendingPathComponent:@"Project - Missing"]];
    NSDictionary *restored=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:settings options:0 error:NULL] options:0 error:NULL];
    Check([SINProjects knownProjectFoldersInSettings:restored].count==1,@"known projects survive JSON and omit duplicates/missing folders");
    Check([[SINProjects displaySuffixForDocumentPath:[project stringByAppendingPathComponent:@"Notes/Prompt.HTML"]] isEqual:@" (人物與世界 🌌)"]&&[[SINProjects displaySuffixForDocumentPath:[project stringByAppendingPathComponent:@"project - Inner/Prompt.htm"]] isEqual:@" (Inner)"]&&![SINProjects displaySuffixForDocumentPath:[project stringByAppendingPathComponent:@"image.png"]].length&&![SINProjects displaySuffixForDocumentPath:nil].length,@"labels use nearest ancestor for HTML and HTM only without filesystem lookup");
    NSString *source=Folder(root,@"Sources"),*first=[source stringByAppendingPathComponent:@"角色 #1.html"],*second=[source stringByAppendingPathComponent:@"Mixed.html"];
    SINDocument *original=SINDocument.new;original.text=@"<p>已儲存</p>\n<a href='../reference.html'>Reference</a>";original.encodingName=@"UTF-16 LE";original.newline=@"\r\n";
    Check([original saveToPath:first overwriteConflict:NO error:&error]&&[original setFileReadOnly:YES error:&error],@"prepare locked UTF-16 saved HTML");
    original.text=[original.text stringByAppendingString:@"\n<p>Unsaved buffer</p>"];NSString *pending=original.text;
    NSData *mixed=[@"\uFEFF<p>One</p>\r\n<p>Two</p>\n<p>Three</p>\r" dataUsingEncoding:NSUTF8StringEncoding];Check([mixed writeToFile:second options:0 error:&error],@"prepare mixed-ending BOM HTML");
    NSString *assets=Folder(source,@"角色 #1"),*nested=Folder(assets,@"Nested");Folder(assets,@"Empty");NSString *image=[nested stringByAppendingPathComponent:@"影像 #1.png"];NSData *imageBytes=[NSData dataWithBytes:(unsigned char[]){1,7,4,2,250,0,12} length:7];Check([imageBytes writeToFile:image options:0 error:&error]&&[fm setAttributes:@{NSFilePosixPermissions:@0444} ofItemAtPath:image error:&error],@"prepare locked image bytes");
    SINProjectMoveSnapshot *a=Snapshot(first,project),*b=Snapshot(second,project);a.html=[a.html stringByReplacingOccurrencesOfString:@"../reference.html" withString:@"../../reference.html"];
    NSArray *moves=[SINProjects referenceMovesForSnapshots:@[a,b]];Check(moves.count==3&&[moves[1][@"oldUrl"] hasSuffix:@"/"]&&[moves[0][@"oldUrl"] containsString:@"%23"],@"reference plan contains encoded file and directory URLs");
    NSMutableArray *progress=NSMutableArray.new;NSArray *result=[SINProjects commitSnapshots:@[a,b] progress:^(NSUInteger done,NSUInteger total){[progress addObject:@[@(done),@(total)]];} error:&error];
    Check(result.count==2&&! [fm fileExistsAtPath:first]&&![fm fileExistsAtPath:second]&&![fm fileExistsAtPath:assets]&&[progress isEqual:@[@[@1,@4],@[@2,@4],@[@3,@4],@[@4,@4]]],error.localizedDescription?:@"batch moves every HTML and asset pair and reports progress");
    SINDocument *disk=[SINDocument openPath:a.destinationPath error:&error];SINProjectMoveResult *moved=result.firstObject;
    Check([disk.text containsString:@"../../reference.html"]&&[disk.encodingName isEqual:@"UTF-16 LE"]&&[disk.newline isEqual:@"\r\n"]&&disk.readOnly&&moved.readOnly,@"rewritten disk HTML preserves encoding, BOM, newline and lock");
    Check([original.text isEqual:pending]&&[original.path isEqual:first]&&original.modified&&![disk.text containsString:@"Unsaved"]&&[moved.html isEqual:disk.text]&&[moved.fingerprint isEqual:disk.fingerprint],@"disk publication leaves detached dirty model untouched and returns actual saved fingerprint");
    Check([[NSData dataWithContentsOfFile:b.destinationPath] isEqual:mixed],@"unchanged move preserves exact original mixed newline bytes");
    NSString *movedImage=[a.destinationAssets stringByAppendingPathComponent:@"Nested/影像 #1.png"];
    Check([[NSData dataWithContentsOfFile:movedImage] isEqual:imageBytes]&&([[fm attributesOfItemAtPath:movedImage error:NULL][NSFilePosixPermissions] unsignedIntegerValue]&0222)==0&&[fm fileExistsAtPath:[a.destinationAssets stringByAppendingPathComponent:@"Empty"]]&&!moved.cleanupWarning&&Debris(root)==0,@"assets preserve exact bytes, Unicode hierarchy, empty folders, locks and clean staging");
    NSString *collisionSource=Folder(root,@"Collision sources"),*ca=[collisionSource stringByAppendingPathComponent:@"A.html"],*cb=[collisionSource stringByAppendingPathComponent:@"B.html"],*collision=Folder(root,@"Project - Collision");Put(ca,@"<p>Saved A</p>");Put(cb,@"<p>Saved B</p>");
    a=Snapshot(ca,collision);b=Snapshot(cb,collision);Put(b.destinationPath,@"Existing destination");
    Check(![SINProjects commitSnapshots:@[a,b] progress:nil error:&error]&&[fm fileExistsAtPath:ca]&&[fm fileExistsAtPath:cb]&&![fm fileExistsAtPath:a.destinationPath]&&[Read(b.destinationPath) isEqual:@"Existing destination"],@"late-batch occupied destination rejects every move without mutation");
    [fm removeItemAtPath:b.destinationPath error:NULL];Folder(collision,@"B");
    Check(![SINProjects commitSnapshots:@[a,b] progress:nil error:&error]&&[fm fileExistsAtPath:ca],@"asset-folder collision rejected even when source has no assets");
    NSString *duplicateFolder=Folder(root,@"Duplicate source"),*duplicate=[duplicateFolder stringByAppendingPathComponent:@"A.html"];Put(duplicate,@"Other A");
    Check(![SINProjects commitSnapshots:@[a,Snapshot(duplicate,collision)] progress:nil error:&error],@"same target filename within batch rejected");
    NSString *rollback=Folder(root,@"Project - Rollback"),*caAssets=Folder(collisionSource,@"A"),*asset=[caAssets stringByAppendingPathComponent:@"saved.png"];Put(asset,@"Saved image");a=Snapshot(ca,rollback);b=Snapshot(cb,rollback);
    NSData *aBefore=[NSData dataWithContentsOfFile:ca],*bBefore=[NSData dataWithContentsOfFile:cb];
    Check(![SINProjects commitSnapshots:@[a,b] progress:^(NSUInteger done,NSUInteger total){(void)total;if(done==3)Put(b.destinationPath,@"Concurrent destination");} error:&error]&&[[NSData dataWithContentsOfFile:ca] isEqual:aBefore]&&[[NSData dataWithContentsOfFile:cb] isEqual:bBefore]&&[Read(asset) isEqual:@"Saved image"]&&![fm fileExistsAtPath:a.destinationPath]&&![fm fileExistsAtPath:a.destinationAssets]&&[Read(b.destinationPath) isEqual:@"Concurrent destination"]&&Debris(root)==0,@"publication failure rolls back every original pair without replacing concurrent destination");
    NSString *changed=Folder(root,@"Project - Changed");a=Snapshot(ca,changed);Put(ca,@"External HTML edit");
    Check(![SINProjects commitSnapshots:@[a] progress:nil error:&error]&&[Read(ca) isEqual:@"External HTML edit"]&&![fm fileExistsAtPath:a.destinationPath],@"external HTML change after snapshot rejects move");
    a=Snapshot(ca,changed);
    Check(![SINProjects commitSnapshots:@[a] progress:^(NSUInteger done,NSUInteger total){(void)total;if(done==1)Put(asset,@"External image edit");} error:&error]&&[Read(asset) isEqual:@"External image edit"]&&[fm fileExistsAtPath:ca]&&![fm fileExistsAtPath:a.destinationPath],@"image change during staging rejects move before reserving originals");
    for(NSNumber *editImage in @[@NO,@YES]) {
        NSString *edited=Folder(root,[NSString stringWithFormat:@"Project - Edited %@",editImage]);a=Snapshot(ca,edited);b=Snapshot(cb,edited);aBefore=[NSData dataWithContentsOfFile:ca];
        Check(![SINProjects commitSnapshots:@[a,b] progress:^(NSUInteger done,NSUInteger total){(void)total;if(done==3){Put(editImage.boolValue?[a.destinationAssets stringByAppendingPathComponent:@"saved.png"]:a.destinationPath,@"New external destination edit");Put(b.destinationPath,@"Concurrent collision");}} error:&error]&&[[NSData dataWithContentsOfFile:ca] isEqual:aBefore]&&[fm fileExistsAtPath:cb]&&[fm fileExistsAtPath:a.destinationPath]&&[fm fileExistsAtPath:a.destinationAssets]&&[Read(editImage.boolValue?[a.destinationAssets stringByAppendingPathComponent:@"saved.png"]:a.destinationPath) isEqual:@"New external destination edit"],@"rollback retains externally edited published pair while restoring originals");
    }
    NSString *linked=[source stringByAppendingPathComponent:@"linked.html"];Check([fm createSymbolicLinkAtPath:linked withDestinationPath:ca error:&error]&&![SINProjectMoveSnapshot readPath:linked destinationFolder:project error:&error],@"linked HTML rejected before transaction");
    NSString *assetLink=[caAssets stringByAppendingPathComponent:@"linked.png"];Check([fm createSymbolicLinkAtPath:assetLink withDestinationPath:movedImage error:&error]&&![SINProjectMoveSnapshot readPath:ca destinationFolder:project error:&error],@"linked assets rejected without following external files");[fm removeItemAtPath:assetLink error:NULL];
    NSString *inside=Folder(caAssets,@"Project - Inside");a=Snapshot(ca,inside);Check(![SINProjects commitSnapshots:@[a] progress:nil error:&error]&&[fm fileExistsAtPath:ca],@"target inside corresponding asset folder rejected");
    NSString *hard=[collisionSource stringByAppendingPathComponent:@"Hard.html"];Check([fm linkItemAtPath:ca toPath:hard error:&error],@"prepare same-inode source alias");a=Snapshot(ca,project);b=Snapshot(hard,project);Check(![SINProjects commitSnapshots:@[a,b] progress:nil error:&error],@"same-inode source duplicates rejected");
    NSString *otherVolume=NSProcessInfo.processInfo.environment[@"SIN_PROJECT_TEST_OTHER_VOLUME"];
    if(otherVolume.length) {
        struct stat here,there;Check(stat(root.fileSystemRepresentation,&here)==0&&stat(otherVolume.fileSystemRepresentation,&there)==0&&here.st_dev!=there.st_dev,@"optional cross-volume fixture is on a separate filesystem");
        NSString *crossRoot=Folder(otherVolume,NSUUID.UUID.UUIDString),*crossPath=[crossRoot stringByAppendingPathComponent:@"Cross volume.html"],*crossAssets=Folder(crossRoot,@"Cross volume");Put(crossPath,@"<p>Across volumes</p>");Check([imageBytes writeToFile:[crossAssets stringByAppendingPathComponent:@"image.png"] options:0 error:&error],@"prepare cross-volume asset");
        SINProjectMoveSnapshot *cross=Snapshot(crossPath,project);NSArray *crossResult=[SINProjects commitSnapshots:@[cross] progress:nil error:&error];
        Check(crossResult.count==1&&![fm fileExistsAtPath:crossPath]&&![fm fileExistsAtPath:crossAssets]&&[[NSData dataWithContentsOfFile:[cross.destinationAssets stringByAppendingPathComponent:@"image.png"]] isEqual:imageBytes],error.localizedDescription?:@"cross-volume move publishes verified HTML and assets before removing originals");
        if(![SINProjects caseSensitiveAtPath:root]&&[SINProjects caseSensitiveAtPath:crossRoot]) {
            NSString *casePath=[root stringByAppendingPathComponent:@"CaseMove.html"],*caseAssets=Folder(root,@"CaseMove"),*caseNested=Folder(caseAssets,@"Nested");Put(casePath,@"<img src='casemove/nested/picture.png'>");Put([caseNested stringByAppendingPathComponent:@"Picture.PNG"],@"image casing");
            SINProjectMoveSnapshot *caseSnapshot=Snapshot(casePath,crossRoot);NSArray<NSDictionary *> *caseMoves=[SINProjects referenceMovesForSnapshots:@[caseSnapshot]];
            NSDictionary *exact=[caseMoves filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *move,NSDictionary *bindings){(void)bindings;return [move[@"oldUrl"] hasSuffix:@"/CaseMove/Nested/Picture.PNG"];}]].firstObject;
            Check(exact&&[exact[@"newUrl"] hasSuffix:@"/CaseMove/Nested/Picture.PNG"]&&![exact[@"caseSensitive"] boolValue]&&![exact[@"directory"] boolValue],@"sensitivity-changing reference plan carries actual asset filename and nested folder casing");
            caseSnapshot.html=@"<img src='CaseMove/Nested/Picture.PNG'>";
            Check([SINProjects commitSnapshots:@[caseSnapshot] progress:nil error:&error].count==1&&[fm fileExistsAtPath:[caseSnapshot.destinationAssets stringByAppendingPathComponent:@"Nested/Picture.PNG"]]&&![fm fileExistsAtPath:[caseSnapshot.destinationAssets stringByAppendingPathComponent:@"nested/picture.png"]],@"sensitivity-changing move retains actual asset casing and accepts parser-corrected HTML");
        }
        [fm removeItemAtPath:crossRoot error:NULL];
    }
    [fm removeItemAtPath:root error:NULL];printf("PASS: %lu physical project assertions\n",(unsigned long)checks);
} return 0; }
