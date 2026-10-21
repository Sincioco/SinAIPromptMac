#import "SINSliceExport.h"
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSError *SliceError(NSString *message) { return [NSError errorWithDomain:@"SinSliceExport" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
@interface SINSliceExport ()
@property(nonatomic,copy) NSString *token;
@property(nonatomic,copy) NSString *folder;
@property(nonatomic,copy) NSString *name;
@property(nonatomic) NSUInteger total;
@property(nonatomic) NSUInteger saved;
@property(nonatomic) int directoryFD;
@property(nonatomic) BOOL busy;
@end
@implementation SINSliceExport
- (instancetype)init { if((self=[super init]))_directoryFD=-1;return self; }
- (void)dealloc { if(_directoryFD>=0)close(_directoryFD); }
- (NSString *)beginInDirectory:(NSString *)parent name:(NSString *)name count:(NSUInteger)count error:(NSError **)error {
    if(self.token||self.busy||count<1||count>1089){if(error)*error=SliceError(@"Finish the current export and choose between 1 and 1089 cells.");return nil;}
    NSMutableString *safe=[[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] mutableCopy];
    NSCharacterSet *invalid=[NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r\t"];
    for(NSUInteger i=0;i<safe.length;i++)if([invalid characterIsMember:[safe characterAtIndex:i]]||[safe characterAtIndex:i]<32)[safe replaceCharactersInRange:NSMakeRange(i,1) withString:@"_"];
    if(safe.length>80)[safe deleteCharactersInRange:NSMakeRange(80,safe.length-80)];
    NSString *stem=[safe stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];if(!stem.length)stem=@"Image";
    NSString *folder=nil;
    for(NSUInteger number=1;;number++){
        NSString *leaf=number==1?[stem stringByAppendingString:@" - Slices"]:[NSString stringWithFormat:@"%@ - Slices (%lu)",stem,(unsigned long)number];
        folder=[parent stringByAppendingPathComponent:leaf];
        if(mkdir(folder.fileSystemRepresentation,0700)==0)break;
        if(errno!=EEXIST){if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:folder}];return nil;}
    }
    int fd=open(folder.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(fd<0){if(error)*error=SliceError(@"The export folder could not be opened.");return nil;}
    self.directoryFD=fd;self.folder=folder;self.name=stem;self.total=count;self.saved=0;self.token=NSUUID.UUID.UUIDString;return self.token;
}
- (void)writeToken:(NSString *)token index:(NSUInteger)index dataURL:(NSString *)data completion:(void (^)(NSError *))completion {
    if(!self.token||![token isEqual:self.token]||self.busy||index!=self.saved||index>=self.total){completion(SliceError(@"Image cells must be saved once, in order, in the active export."));return;}
    self.busy=YES;int directory=self.directoryFD;NSUInteger digits=MAX(2,[@(self.total).stringValue length]);
    NSString *leaf=[NSString stringWithFormat:@"%@ - Cell %0*lu.png",self.name,(int)digits,(unsigned long)index+1];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSString *prefix=@"data:image/png;base64,";
        NSData *bytes=[data hasPrefix:prefix]?[[NSData alloc] initWithBase64EncodedString:[data substringFromIndex:prefix.length] options:0]:nil;
        CGImageSourceRef source=bytes?CGImageSourceCreateWithData((__bridge CFDataRef)bytes,NULL):NULL;
        BOOL png=source&&[(__bridge NSString *)CGImageSourceGetType(source) isEqual:@"public.png"]&&CGImageSourceGetCount(source)>0;
        if(source)CFRelease(source);
        if(!png)error=SliceError(@"The image cell is not a valid PNG.");
        NSString *temporary=[@".sin-cell-" stringByAppendingString:NSUUID.UUID.UUIDString];
        if(!error){
            int fd=openat(directory,temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
            if(fd<0)error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            else {
                const uint8_t *buffer=bytes.bytes;NSUInteger offset=0;
                while(offset<bytes.length){ssize_t n=write(fd,buffer+offset,bytes.length-offset);if(n<0&&errno==EINTR)continue;if(n<=0){error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];break;}offset+=(NSUInteger)n;}
                if(!error&&fsync(fd)!=0)error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];close(fd);
                // Exclusive publication also rejects a file created during export.
                if(!error&&renameatx_np(directory,temporary.fileSystemRepresentation,directory,leaf.fileSystemRepresentation,RENAME_EXCL)!=0)error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:@"A cell could not be saved without replacing an existing file."}];
                unlinkat(directory,temporary.fileSystemRepresentation,0);if(!error)fsync(directory);
            }
        }
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;if(!error)self.saved++;completion(error);});
    });
}
- (NSDictionary *)endToken:(NSString *)token error:(NSError **)error {
    if(!self.token||![token isEqual:self.token]||self.busy){if(error)*error=SliceError(@"The export is inactive or a cell is still being saved.");return nil;}
    NSDictionary *result=@{@"folder":self.folder,@"saved":@(self.saved),@"total":@(self.total)};
    close(self.directoryFD);self.directoryFD=-1;self.token=nil;return result;
}
@end
