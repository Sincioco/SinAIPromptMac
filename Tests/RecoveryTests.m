#import <Foundation/Foundation.h>
#import "SINStore.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Wait(BOOL(^ready)(void)){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:20];while(!ready()&&end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"background recovery completes");}
static NSDictionary *Read(NSString *folder,NSString *file){return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:file]] options:0 error:nil];}
int main(void){@autoreleasepool{
    NSFileManager *fm=NSFileManager.defaultManager;NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"Sin-recovery-" stringByAppendingString:NSUUID.UUID.UUIDString]];NSError *error=nil;
    SINStore *store=[[SINStore alloc] initWithDirectory:root error:&error];Check(store!=nil,@"isolated recovery profile");SINDocument *doc=[store newDocument:&error];
    NSMutableString *text=[NSMutableString stringWithString:@"<p>Snapshot 😀</p>"];doc.text=text;store.settings[@"nested"]=[NSMutableArray arrayWithObject:@"before"];
    __block BOOL done=NO;__block NSError *failure=nil;
    [store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier completion:^(NSError *e){failure=e;done=YES;}];
    doc.text=@"Changed after enqueue";[store.settings[@"nested"] addObject:@"after"];Wait(^BOOL{return done;});
    Check(!failure,@"asynchronous recovery succeeds");Check([Read(root,@"session.json")[@"documents"][0][@"text"] isEqual:@"<p>Snapshot 😀</p>"],@"queued document snapshot is detached from later edits");Check([Read(root,@"settings.json")[@"nested"] count]==1,@"queued nested settings are immutable");
    for(NSUInteger i=0;i<30;i++){doc.text=[NSString stringWithFormat:@"Queued %lu",(unsigned long)i];[store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier completion:^(NSError *e){Check(!e,@"queued recovery succeeds");}];}
    doc.text=@"Explicit save wins";Check([store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier error:&error],@"explicit recovery save is a barrier");
    Check([Read(root,@"session.json")[@"documents"][0][@"text"] isEqual:doc.text],@"older pending writes cannot overwrite explicit save");
    NSString *session=[root stringByAppendingPathComponent:@"session.json"];NSDictionary *before=[fm attributesOfItemAtPath:session error:nil];
    done=NO;[store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier completion:^(NSError *e){failure=e;done=YES;}];Wait(^BOOL{return done;});NSDictionary *after=[fm attributesOfItemAtPath:session error:nil];
    Check([before[NSFileSystemFileNumber] isEqual:after[NSFileSystemFileNumber]]&&[before[NSFileModificationDate] isEqual:after[NSFileModificationDate]],@"unchanged snapshots do not rewrite recovery files");
    NSDictionary *savedSettings=[store.settings copy];NSArray *savedTemplates=[store.templates copy];store.settings[@"temporary"]=@YES;Check([store saveSettings:&error],@"direct settings save");store.settings=[savedSettings mutableCopy];[store.templates addObject:@{@"name":@"Temporary",@"objects":@[]}];Check([store saveTemplates:&error],@"direct templates save");store.templates=[savedTemplates mutableCopy];
    Check([store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier error:&error],@"snapshot after direct profile writes");Check(Read(root,@"settings.json")[@"temporary"]==nil&&[Read(root,@"templates.json") count]==savedTemplates.count,@"direct writes invalidate snapshot deduplication");
    NSData *savedSession=[NSData dataWithContentsOfFile:session];Check([fm removeItemAtPath:session error:&error]&&[fm createDirectoryAtPath:session withIntermediateDirectories:NO attributes:nil error:&error],@"simulate partial profile publication failure");store.settings[@"temporary"]=@YES;Check(![store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier error:&error],@"session failure follows settings publication");Check([Read(root,@"settings.json")[@"temporary"] boolValue],@"settings were partially published");
    [fm removeItemAtPath:session error:nil];[savedSession writeToFile:session atomically:YES];store.settings=[savedSettings mutableCopy];Check([store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier error:&error]&&Read(root,@"settings.json")[@"temporary"]==nil,@"retrying older snapshot repairs partial publication");
    NSMutableString *large=NSMutableString.new;for(NSUInteger i=0;i<65536;i++)[large appendString:@"Screenshot-like payload 😀 \\\"\n"];
    doc.text=large;done=NO;[store saveSessionDocuments:@[doc] activeIdentifier:doc.identifier completion:^(NSError *e){failure=e;done=YES;}];Wait(^BOOL{return done;});Check(!failure&&[Read(root,@"session.json")[@"documents"][0][@"text"] isEqual:large],@"streamed recovery retains large Unicode and escaped content exactly");
    Check([fm fileExistsAtPath:[session stringByAppendingString:@".bak"]],@"atomic recovery retains previous backup");
    store.settings[@"restoreSession"]=@NO;Check([store saveSessionDocuments:@[doc] activeIdentifier:nil error:&error],@"disabled session recovery saves settings");Check([Read(root,@"session.json")[@"documents"] count]==0,@"disabled restoration omits document text");
    store.settings[@"restoreSession"]=@YES;
    // A profile can become unavailable while open. Failed snapshots must retry.
    NSString *moved=[root stringByAppendingString:@"-moved"];Check([fm moveItemAtPath:root toPath:moved error:&error],@"simulate unavailable profile");
    doc.text=@"Retry latest";done=NO;[store saveSessionDocuments:@[doc] activeIdentifier:nil completion:^(NSError *e){failure=e;done=YES;}];Wait(^BOOL{return done;});Check(failure!=nil,@"recovery failure reaches caller");
    Check([fm moveItemAtPath:moved toPath:root error:&error],@"restore profile");done=NO;[store saveSessionDocuments:@[doc] activeIdentifier:nil completion:^(NSError *e){failure=e;done=YES;}];Wait(^BOOL{return done;});Check(!failure,@"failed unchanged snapshot retries successfully");
    [fm removeItemAtPath:root error:nil];printf("PASS: %lu background recovery assertions\n",(unsigned long)checks);
}return 0;}
