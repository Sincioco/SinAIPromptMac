#import "SINRecoveryWriter.h"
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

id SINDetachedJSON(id value) {
    if([value isKindOfClass:NSDictionary.class]){NSMutableDictionary *copy=NSMutableDictionary.new;for(id key in value)copy[key]=SINDetachedJSON(value[key]);return [copy copy];}
    if([value isKindOfClass:NSArray.class]){NSMutableArray *copy=NSMutableArray.new;for(id item in value)[copy addObject:SINDetachedJSON(item)];return [copy copy];}
    return [value copy];
}
static BOOL WriteRecoveryJSON(id value,NSString *path,NSError **error) {
    if(![NSJSONSerialization isValidJSONObject:value]){if(error)*error=[NSError errorWithDomain:@"SinRecovery" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Recovery contains a value that cannot be stored as JSON."}];return NO;}
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *temporary=[path stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
    NSOutputStream *stream=[NSOutputStream outputStreamToFileAtPath:temporary append:NO];[stream open];
    chmod(temporary.fileSystemRepresentation,0600);
    BOOL success=[NSJSONSerialization writeJSONObject:value toStream:stream options:NSJSONWritingSortedKeys error:error]>0;
    [stream close];
    if(success){int fd=open(temporary.fileSystemRepresentation,O_RDONLY);success=fd>=0&&fsync(fd)==0;if(fd>=0)close(fd);if(!success&&error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}];}
    if(success&&[fm fileExistsAtPath:path]){
        NSString *backup=[path stringByAppendingString:@".bak"],*staged=[backup stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
        success=[fm copyItemAtPath:path toPath:staged error:error];
        if(success&&rename(staged.fileSystemRepresentation,backup.fileSystemRepresentation)!=0){success=NO;if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:backup}];}
        [fm removeItemAtPath:staged error:nil];
    }
    if(success&&rename(temporary.fileSystemRepresentation,path.fileSystemRepresentation)!=0){success=NO;if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}];}
    if(success){int fd=open(path.stringByDeletingLastPathComponent.fileSystemRepresentation,O_RDONLY);if(fd>=0){fsync(fd);close(fd);}}
    [fm removeItemAtPath:temporary error:nil];return success;
}
@interface SINRecoveryWriter ()
@property(nonatomic,copy) NSString *directory;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,copy) NSDictionary *pending;
@property(nonatomic,copy) NSDictionary *written;
@property(nonatomic,strong) NSMutableArray *callbacks;
@property(nonatomic) BOOL draining;
@end
@implementation SINRecoveryWriter
- (instancetype)initWithDirectory:(NSString *)directory { if((self=[super init])){_directory=[directory copy];_queue=dispatch_queue_create("com.sin.aiprompt.recovery",DISPATCH_QUEUE_SERIAL);_callbacks=NSMutableArray.new;}return self; }
- (BOOL)publish:(NSDictionary *)snapshot error:(NSError **)error {
    if([snapshot isEqual:self.written])return YES;
    // A failed publication can update only part of the profile. No older
    // snapshot may then be treated as an already-published complete profile.
    self.written=nil;
    for(NSString *name in @[@"settings.json",@"session.json",@"templates.json"]){id value=snapshot[name];if(value&&!WriteRecoveryJSON(value,[self.directory stringByAppendingPathComponent:name],error))return NO;}
    self.written=snapshot;return YES;
}
- (void)drain {
    while(YES){@autoreleasepool{
        NSDictionary *snapshot;NSArray *callbacks;
        @synchronized(self){snapshot=self.pending;self.pending=nil;callbacks=[self.callbacks copy];[self.callbacks removeAllObjects];if(!snapshot){self.draining=NO;return;}}
        NSError *error=nil;[self publish:snapshot error:&error];
        dispatch_async(dispatch_get_main_queue(),^{for(void(^done)(NSError *) in callbacks)done(error);});
    }}
}
- (void)enqueueSnapshot:(NSDictionary *)snapshot completion:(void (^)(NSError *))completion {
    @synchronized(self){self.pending=snapshot;if(completion)[self.callbacks addObject:[completion copy]];if(self.draining)return;self.draining=YES;}
    dispatch_async(self.queue,^{[self drain];});
}
- (BOOL)saveSnapshot:(NSDictionary *)snapshot error:(NSError **)error {
    NSArray *callbacks;
    @synchronized(self){self.pending=nil;callbacks=[self.callbacks copy];[self.callbacks removeAllObjects];}
    __block BOOL success;__block NSError *failure=nil;
    dispatch_sync(self.queue,^{success=[self publish:snapshot error:&failure];});
    if(error)*error=failure;
    if(callbacks.count)dispatch_async(dispatch_get_main_queue(),^{for(void(^done)(NSError *) in callbacks)done(failure);});
    return success;
}
- (void)waitUntilIdle { dispatch_sync(self.queue,^{}); }
- (void)invalidateAfterPendingWrites { dispatch_sync(self.queue,^{self.written=nil;}); }
@end
