#import <Foundation/Foundation.h>
#import "SINDocument.h"
#import "SINStore.h"
#import <sys/stat.h>

static NSInteger assertions = 0;
static void Check(BOOL value, NSString *message) {
    assertions++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void Put(NSString *text, NSString *path) {
    Check([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write fixture");
}
static NSString *ExpectedDraftName(SINDocument *document) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = @"yyyy-MM-dd HHmm";
    return [NSString stringWithFormat:@"%@ - Prompt %ld", [formatter stringFromDate:document.createdDate], (long)document.untitledNumber];
}
int main(void) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"SinAIPrompt-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSFileManager *fm = NSFileManager.defaultManager;
        Check([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL], @"temporary directory");
        NSString *previousLocation = [NSUserDefaults.standardUserDefaults stringForKey:@"SinAIPromptDataDirectory"];
        NSError *error = nil;
        SINStore *store = [[SINStore alloc] initWithDirectory:[root stringByAppendingPathComponent:@"profile"] error:&error];
        Check(store != nil, error.localizedDescription ?: @"create profile");
        SINDocument *one = [store newDocument:&error], *two = [store newDocument:&error];
        Check(one.untitledNumber == 1 && two.untitledNumber == 2 && [one.name hasSuffix:@" - Prompt 1"] && [two.name hasSuffix:@" - Prompt 2"], @"sequential prompt names include the Windows naming suffix");
        Check([one.name isEqual:ExpectedDraftName(one)] && [two.name isEqual:ExpectedDraftName(two)], @"new manual drafts include their creation date and local 24-hour minute");
        NSRegularExpression *draftPattern = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4} - Prompt [0-9]+$" options:0 error:NULL];
        Check([draftPattern numberOfMatchesInString:one.name options:0 range:NSMakeRange(0,one.name.length)] == 1 && !one.path && !two.path, @"manual draft names use the exact invariant Windows format without creating files");
        Check(!one.modified, @"new draft starts clean");
        NSString *originalDraftName = one.name;
        one.text = @"<!doctype html><html><body><p>Unsaved 😀</p></body></html>";
        Check(one.modified, @"dirty state");
        store.settings[@"wordWrap"] = @NO;
        [store.templates addObject:@{@"name":@"Example", @"objects":@[]}];
        Check([store saveSessionDocuments:@[one,two] activeIdentifier:one.identifier error:&error], @"persist session");
        SINStore *restoredStore = [[SINStore alloc] initWithDirectory:store.directory error:&error];
        NSArray *restored = [restoredStore restoreDocuments:&error];
        Check(restored.count == 2 && [[restored[0] text] isEqual:one.text] && [restored[0] modified], @"recover unsaved text");
        Check([[restored[0] name] isEqual:originalDraftName] && [[restored[0] draftName] isEqual:originalDraftName], @"session recovery preserves the creation-time draft name and pending edits");
        SINDocument *historic = [SINDocument documentFromDictionary:@{@"untitledNumber":@42, @"draftName":@"2020-01-02 0304 - Prompt 42", @"createdDate":@0}];
        Check([historic.name isEqual:@"2020-01-02 0304 - Prompt 42"], @"recovered names are not regenerated from the current date or stored timestamp");
        Check([[SINDocument documentFromDictionary:@{@"untitledNumber":@42}].name isEqual:@"Prompt 42"], @"legacy recovery without a draft name retains its original Prompt N name");
        Check([historic renameToFilename:@"My renamed draft.html" error:&error] && [historic.name isEqual:@"My renamed draft.html"] && !historic.path, @"renaming a draft preserves the chosen name without saving a file");
        Check([[SINDocument documentFromDictionary:historic.dictionaryRepresentation].name isEqual:historic.name], @"custom draft names survive recovery unchanged");
        Check([restoredStore.activeIdentifier isEqual:one.identifier], @"restore active document");
        Check(![restoredStore.settings[@"wordWrap"] boolValue] && restoredStore.templates.count == 1, @"settings and template roundtrip");
        restoredStore.settings[@"nextDocumentNumber"] = @1;
        [restoredStore restoreDocuments:&error];
        SINDocument *continued = [restoredStore newDocument:&error];
        Check(continued.untitledNumber == 3 && [continued.name hasSuffix:@" - Prompt 3"], @"recovery raises stale numbering before creating the next timestamped draft");
        SINStore *reopenedNumbering = [[SINStore alloc] initWithDirectory:store.directory error:&error];
        Check([reopenedNumbering.settings[@"nextDocumentNumber"] integerValue] == 4, @"new document sequence persists across profile restarts");
        NSString *path = [root stringByAppendingPathComponent:@"original.html"];
        Check([one saveToPath:path overwriteConflict:NO error:&error] && !one.modified, @"save new document");
        Check(!one.draftName && [one.name isEqual:@"original.html"], @"first save replaces the timestamp draft name with the chosen filename");
        one.text = [one.text stringByAppendingString:@"\n<p>More</p>"];
        Put(@"external", path);
        Check(![one saveToPath:path overwriteConflict:NO error:&error] && error.code == SINErrorConflict, @"reject external modification");
        Check([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] isEqual:@"external"], @"conflict leaves disk untouched");
        Check([one saveToPath:path overwriteConflict:YES error:&error], @"explicit conflict overwrite");
        Check(![two saveToPath:path overwriteConflict:NO error:&error] && error.code == SINErrorOccupied, @"reject occupied save destination");
        Check([one setFileReadOnly:YES error:&error], @"lock document");
        one.text = [one.text stringByAppendingString:@"x"];
        Check(![one saveToPath:path overwriteConflict:NO error:&error] && error.code == SINErrorReadOnly, @"locked save rejected");
        Check([one setFileReadOnly:NO error:&error], @"unlock document");
        Check([one saveToPath:path overwriteConflict:NO error:&error], @"unlocked save");
        for (NSString *encoding in [SINDocument encodingNames]) {
            SINDocument *document = [SINDocument new];
            document.text = @"Café\nsecond line"; document.encodingName = encoding; document.newline = @"\r\n";
            NSString *encodedPath = [root stringByAppendingPathComponent:[encoding stringByAppendingString:@".html"]];
            Check([document saveToPath:encodedPath overwriteConflict:NO error:&error], [@"save encoding " stringByAppendingString:encoding]);
            SINDocument *opened = [SINDocument openPath:encodedPath error:&error];
            // BOM-less Mac Roman has no automatic signal; explicit selection is used when reopening legacy text.
            if (![encoding isEqual:@"Mac Roman"]) Check([opened.text isEqual:document.text], [@"decode encoding " stringByAppendingString:encoding]);
            Check([opened.newline isEqual:@"\r\n"], @"preserve CRLF preference");
        }
        SINDocument *lossy = [SINDocument new]; lossy.text = @"😀"; lossy.encodingName = @"ANSI";
        Check(![lossy saveToPath:[root stringByAppendingPathComponent:@"lossy.html"] overwriteConflict:NO error:&error] && error.code == SINErrorEncoding, @"reject lossy encoding");
        NSString *mixed = [root stringByAppendingPathComponent:@"mixed.html"];
        Put(@"one\r\ntwo\nthree\rfour", mixed);
        NSData *mixedBytes = [NSData dataWithContentsOfFile:mixed];
        SINDocument *mixedDocument = [SINDocument openPath:mixed error:&error];
        Check([mixedDocument saveToPath:mixed overwriteConflict:NO error:&error] && [[NSData dataWithContentsOfFile:mixed] isEqual:mixedBytes], @"unchanged save preserves exact bytes");
        NSString *assetFolder = path.stringByDeletingPathExtension;
        [fm createDirectoryAtPath:assetFolder withIntermediateDirectories:YES attributes:nil error:NULL];
        Put(@"PNG bytes", [assetFolder stringByAppendingPathComponent:@"image.png"]);
        one.text = @"<!doctype html><html><head><script>const s=\"<img src='original/image.png'>\";</script></head><body><img src=\"original/image.png\"><img src='shared.png'></body></html>";
        Check([one saveToPath:path overwriteConflict:NO error:&error], @"save image document");
        one.text = [one.text stringByAppendingString:@"<!-- pending -->"];
        Check([one renameToFilename:@"renamed.html" error:&error], @"rename html with folder");
        Check(one.modified && [one.text containsString:@"pending"] && ![one.savedText containsString:@"pending"], @"rename preserves pending edits");
        Check([one.text containsString:@"src=\"renamed/image.png\""] && [one.text containsString:@"const s=\"<img src='original/image.png'>"], @"rename rebases image source and preserves script text");
        Check([fm fileExistsAtPath:[[root stringByAppendingPathComponent:@"renamed"] stringByAppendingPathComponent:@"image.png"]] && ![fm fileExistsAtPath:assetFolder], @"rename moves asset folder");
        NSString *occupied = [root stringByAppendingPathComponent:@"occupied"];
        [fm createDirectoryAtPath:occupied withIntermediateDirectories:YES attributes:nil error:NULL];
        Check(![one renameToFilename:@"occupied.html" error:&error] && [fm fileExistsAtPath:one.path], @"occupied image folder rejected without moving html");
        NSString *copyDirectory = [root stringByAppendingPathComponent:@"copies"];
        [fm createDirectoryAtPath:copyDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *originalRenamed = one.path;
        BOOL copySucceeded=[one saveAsToPath:[copyDirectory stringByAppendingPathComponent:@"copy.html"] error:&error];
        Check(copySucceeded, [@"save as copies assets: " stringByAppendingString:error.localizedDescription?:@""]);
        Check([fm fileExistsAtPath:originalRenamed] && [fm fileExistsAtPath:[copyDirectory stringByAppendingPathComponent:@"copy/image.png"]], @"save as retains original and copies image");
        Check([one.text containsString:@"copy/image.png"] && [one.text containsString:@"../shared.png"], @"save as rebases copied and original references");
        NSString *complex = @"<html><head><base href='assets/'><link href='../original/style.css'><style>.x{background:url('../original/a%20b.png')}</style></head><body><img alt='src=\"leave-me.png\"' src='../original/a%20b.png'><p style=\"background:url('../original/bg.png')\"></p></body></html>";
        NSString *complexRebased = [SINDocument rebaseHTML:complex fromPath:path toPath:[root stringByAppendingPathComponent:@"renamed.html"] assetFolderMoved:YES];
        Check([complexRebased containsString:@"src='../renamed/a%20b.png'"] && [complexRebased containsString:@"alt='src=\"leave-me.png\"'"], @"rebase respects base directories and quoted attribute content");
        Check([complexRebased containsString:@"url('../renamed/bg.png')"] && [complexRebased containsString:@"url('../renamed/a%20b.png')"] && [complexRebased containsString:@"href='../renamed/style.css'"], @"rebase CSS backgrounds and stylesheet references");
        NSString *casePath=[root stringByAppendingPathComponent:@"caseassets.html"],*caseFolder=casePath.stringByDeletingPathExtension;
        [fm createDirectoryAtPath:caseFolder withIntermediateDirectories:YES attributes:nil error:NULL];Put(@"fixture",[caseFolder stringByAppendingPathComponent:@"image.png"]);
        NSNumber *caseSensitive=nil;[[NSURL fileURLWithPath:root] getResourceValue:&caseSensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:NULL];
        NSString *caseInput=@"<img src='CASEASSETS/image.png?size=1#detail'>";
        if(caseSensitive) {
            NSString *caseOutput=[SINDocument rebaseHTML:caseInput fromPath:casePath toPath:[root stringByAppendingPathComponent:@"changedcase.html"] assetFolderMoved:YES];
            Check([caseOutput containsString:caseSensitive.boolValue?@"CASEASSETS/image.png?size=1#detail":@"changedcase/image.png?size=1#detail"],@"asset folder rebasing respects actual filesystem case sensitivity");
            if(!caseSensitive.boolValue) {
                SINDocument *caseDocument=[SINDocument new];caseDocument.text=caseInput;
                Check([caseDocument saveToPath:casePath overwriteConflict:NO error:&error],@"save differently cased asset references");
                caseDocument.text=[caseInput stringByAppendingString:@"<!-- unsaved -->"];
                Check([caseDocument renameToFilename:@"changedcase.html" error:&error]&&caseDocument.modified&&[caseDocument.text containsString:@"changedcase/image.png?size=1#detail"]&&[caseDocument.savedText containsString:@"changedcase/image.png?size=1#detail"],@"rename updates saved and unsaved case-variant references after folder move");
            }
        }
        NSString *mergeSourcePath=[root stringByAppendingPathComponent:@"merge-source.html"],*mergeSourceFolder=mergeSourcePath.stringByDeletingPathExtension;
        NSString *mergeTargetPath=[root stringByAppendingPathComponent:@"merge-target.html"],*mergeTargetFolder=mergeTargetPath.stringByDeletingPathExtension;
        [fm createDirectoryAtPath:[mergeSourceFolder stringByAppendingPathComponent:@"nested"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:mergeTargetFolder withIntermediateDirectories:YES attributes:nil error:NULL];
        Put(@"same image",[mergeSourceFolder stringByAppendingPathComponent:@"same.png"]);Put(@"same image",[mergeTargetFolder stringByAppendingPathComponent:@"same.png"]);
        Put(@"new image",[mergeSourceFolder stringByAppendingPathComponent:@"nested/added.png"]);Put(@"unknown retained",[mergeTargetFolder stringByAppendingPathComponent:@"keep.txt"]);Put(@"old HTML",mergeTargetPath);
        SINDocument *mergeDocument=[SINDocument new];mergeDocument.text=@"<img src='merge-source/same.png'><img src='merge-source/nested/added.png'>";
        Check([mergeDocument saveToPath:mergeSourcePath overwriteConflict:NO error:&error],@"prepare replacement source");
        NSData *mergeOriginal=[NSData dataWithContentsOfFile:mergeSourcePath];
        Check(![mergeDocument saveAsToPath:mergeTargetPath error:&error]&&error.code==SINErrorOccupied,@"default Save As still rejects occupied files");
        Check([mergeDocument saveAsToPath:mergeTargetPath replaceExisting:YES error:&error],@"explicit Save As replaces approved HTML and merges compatible assets");
        Check([[NSData dataWithContentsOfFile:mergeSourcePath] isEqual:mergeOriginal]&&[fm fileExistsAtPath:[mergeSourceFolder stringByAppendingPathComponent:@"nested/added.png"]],@"replacement Save As preserves original HTML and assets");
        Check([mergeDocument.text containsString:@"merge-target/nested/added.png"]&&[fm fileExistsAtPath:[mergeTargetFolder stringByAppendingPathComponent:@"nested/added.png"]],@"replacement Save As rebases and copies nested assets");
        Check([[NSString stringWithContentsOfFile:[mergeTargetFolder stringByAppendingPathComponent:@"keep.txt"] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"unknown retained"],@"replacement Save As keeps unknown destination assets");
        NSString *collisionPath=[root stringByAppendingPathComponent:@"collision-source.html"],*collisionFolder=collisionPath.stringByDeletingPathExtension;
        [fm createDirectoryAtPath:collisionFolder withIntermediateDirectories:YES attributes:nil error:NULL];Put(@"new uncolliding asset",[collisionFolder stringByAppendingPathComponent:@"a-new.png"]);Put(@"different pixels",[collisionFolder stringByAppendingPathComponent:@"same.png"]);
        SINDocument *collision=[SINDocument new];collision.text=@"<img src='collision-source/same.png'>";Check([collision saveToPath:collisionPath overwriteConflict:NO error:&error],@"prepare asset collision source");
        NSData *approvedHTML=[NSData dataWithContentsOfFile:mergeTargetPath];
        Check(![collision saveAsToPath:mergeTargetPath replaceExisting:YES error:&error]&&error.code==SINErrorOccupied,@"replacement rejects differing assets with the same destination filename");
        Check([[NSData dataWithContentsOfFile:mergeTargetPath] isEqual:approvedHTML]&&![fm fileExistsAtPath:[mergeTargetFolder stringByAppendingPathComponent:@"a-new.png"]]&&[collision.path isEqual:collisionPath],@"asset collision leaves destination HTML, assets and source model unchanged");
        NSString *caseRenamePath=[root stringByAppendingPathComponent:@"CaseDocument.html"],*caseRenameFolder=caseRenamePath.stringByDeletingPathExtension;
        [fm createDirectoryAtPath:caseRenameFolder withIntermediateDirectories:YES attributes:nil error:NULL];Put(@"image",[caseRenameFolder stringByAppendingPathComponent:@"CaseImage.png"]);
        SINDocument *caseRename=[SINDocument new];caseRename.text=@"<img src='CaseDocument/CaseImage.png'>";Check([caseRename saveToPath:caseRenamePath overwriteConflict:NO error:&error],@"prepare case-only document rename");caseRename.text=[caseRename.text stringByAppendingString:@"<!-- pending -->"];
        Check([caseRename renameToFilename:@"casedocument.html" error:&error]&&caseRename.modified&&[caseRename.text containsString:@"casedocument/CaseImage.png"],@"case-only document and folder rename preserves unsaved edits");
        NSArray *actualNames=[fm contentsOfDirectoryAtPath:root error:NULL];Check([actualNames containsObject:@"casedocument.html"]&&[actualNames containsObject:@"casedocument"]&&![actualNames containsObject:@"CaseDocument.html"],@"case-only rename updates actual on-disk letter casing");
        NSString *imageBefore=[caseRename.path.stringByDeletingPathExtension stringByAppendingPathComponent:@"CaseImage.png"],*imageAfter=[caseRename.path.stringByDeletingPathExtension stringByAppendingPathComponent:@"caseimage.png"];
        Check(SINMoveFilePreservingCase(imageBefore,imageAfter,&error)&&[[fm contentsOfDirectoryAtPath:caseRename.path.stringByDeletingPathExtension error:NULL] containsObject:@"caseimage.png"],@"case-only image move preserves bytes and updates directory entry");
        NSString *alias=[root stringByAppendingPathComponent:@"same-file-alias.html"];Check([fm linkItemAtPath:caseRename.path toPath:alias error:&error]&&SINPathsReferToSameFile(caseRename.path,alias),@"same-inode aliases are recognized for cross-window destination guards");
        Check([store saveSessionDocuments:@[one,two] activeIdentifier:two.identifier error:&error], @"second recovery snapshot");
        Put(@"broken JSON", [store.directory stringByAppendingPathComponent:@"session.json"]);
        NSArray *fallback = [store restoreDocuments:&error];
        Check(fallback.count == 2 && [[fallback[0] text] containsString:@"Unsaved"], @"corrupted session falls back to previous snapshot");
        NSString *newStorage = [root stringByAppendingPathComponent:@"relocated"];
        NSString *oldStorage = store.directory;
        Check([store relocateToDirectory:newStorage error:&error], @"relocate profile");
        Check([fm fileExistsAtPath:[oldStorage stringByAppendingPathComponent:@"session.json.bak"]] && [fm fileExistsAtPath:[newStorage stringByAppendingPathComponent:@"session.json.bak"]], @"relocate retains old files and recovery backup");
        Check(![store relocateToDirectory:occupied error:&error] || [store.directory isEqual:occupied], @"empty storage destination permitted");
        NSString *occupiedProfile = [root stringByAppendingPathComponent:@"busy"];
        [fm createDirectoryAtPath:occupiedProfile withIntermediateDirectories:YES attributes:nil error:NULL]; Put(@"unrelated", [occupiedProfile stringByAppendingPathComponent:@"file"]);
        Check(![store relocateToDirectory:occupiedProfile error:&error], @"occupied profile rejected");
        store.settings[@"autoSaveDirectory"] = [root stringByAppendingPathComponent:@"autosave"];
        SINDocument *autoOne = [store newDocument:&error];
        Check(autoOne.autosave && [fm fileExistsAtPath:autoOne.path], @"autosave reserves and writes document");
        Check([autoOne.name isEqual:[ExpectedDraftName(autoOne) stringByAppendingPathExtension:@"html"]] && !autoOne.draftName, @"autosave uses one creation timestamp prefix and one HTML extension");
        store.settings[@"nextDocumentNumber"] = @(autoOne.untitledNumber);
        SINDocument *autoTwo = [store newDocument:&error];
        Check(autoTwo.untitledNumber > autoOne.untitledNumber && ![autoOne.path isEqual:autoTwo.path], @"autosave numbering collision cannot overwrite");
        if (previousLocation) [NSUserDefaults.standardUserDefaults setObject:previousLocation forKey:@"SinAIPromptDataDirectory"];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SinAIPromptDataDirectory"];
        [fm removeItemAtPath:root error:NULL];
        printf("PASS: %ld persistence assertions\n", (long)assertions);
    }
    return 0;
}
