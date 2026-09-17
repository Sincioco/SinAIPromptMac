#import <Foundation/Foundation.h>
#import "../Sources/SINDocument.h"
extern NSArray<NSString *> *SINUnusedImagePaths(NSString *,NSArray<NSDictionary *> *,NSError **);
extern BOOL SINFolderContainsReferencedFiles(NSString *,NSArray<NSDictionary *> *,NSError **);
static NSUInteger checks=0;
static void Check(BOOL condition,NSString *message){checks++;if(!condition){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Write(NSString *path,NSString *text){NSError *error=nil;Check([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error],@"create fixture directory");Check([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error],@"write fixture");}
int main(void){@autoreleasepool{
    NSString *root=[[NSTemporaryDirectory() stringByAppendingPathComponent:[@"Sin-unused-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]] stringByResolvingSymlinksInPath],*external=[root stringByAppendingString:@"-outside"];NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
    NSString *(^path)(NSString *)=^NSString *(NSString *relative){return [root stringByAppendingPathComponent:relative];};
    for(NSString *name in @[@"used.png",@"unused.png",@"background.webp",@"first.jpg",@"second.jpg",@"poster.gif",@"linked.svg",@"object.bmp",@"A&B.png",@"percent%20.png",@"unsaved.png",@"nested/unreferenced.tiff",@".hidden.png"])Write(path([@"Report/" stringByAppendingString:name]),@"image fixture");
    Write(path(@"loose.png"),@"not an asset");Write(path(@"NoMatchingHTML/ignored.png"),@"not an asset");
    NSString *html=@"<html><head><style>div{background:url('Report/background.webp')}span:before{content:'&copy;'}</style></head><body><img src='Report/used.png'><img srcset='Report/first.jpg 1x, Report/second.jpg 2x'><video poster='Report/poster.gif'></video><a href='Report/linked.svg'>Asset</a><object data='Report/object.bmp'></object><img src='Report/A&amp;B.png'><img src='Report/percent%2520.png'><!-- <img src='Report/unused.png'> --><script>var ignored=\"<img src='Report/unused.png'>\"</script><textarea><img src='Report/unused.png'></textarea></body></html>";
    Write(path(@"Report.html"),html);Write(path(@"nested/Other.htm"),@"<img src='Other/used.png'>");Write(path(@"nested/Other/used.png"),@"image");Write(path(@"nested/Other/unused.ico"),@"image");
    Write([external stringByAppendingPathComponent:@"External.html"],@"<p>External</p>");Write([external stringByAppendingPathComponent:@"External/unused.png"],@"external");
    Check([fm createSymbolicLinkAtPath:path(@"linked-directory") withDestinationPath:external error:&error],@"create directory link fixture");Check([fm createSymbolicLinkAtPath:path(@"Report/link.png") withDestinationPath:path(@"Report/unused.png") error:&error],@"create file link fixture");
    NSArray *unused=SINUnusedImagePaths(root,@[],&error);Check(unused&&!error,@"scan succeeds with HTML, CSS and Unicode-safe paths");
    NSSet *expected=[NSSet setWithArray:@[path(@"Report/unused.png"),path(@"Report/unsaved.png"),path(@"Report/nested/unreferenced.tiff"),path(@"nested/Other/unused.ico")]];
    Check([[NSSet setWithArray:unused] isEqual:expected],@"only unreferenced images inside matching asset folders are listed");
    NSString *openHTML=[html stringByAppendingString:@"<img src='Report/unsaved.png'>"];
    unused=SINUnusedImagePaths(root,@[@{@"path":path(@"Report.html"),@"text":openHTML}],&error);Check(![unused containsObject:path(@"Report/unsaved.png")],@"unsaved added reference protects its file");
    unused=SINUnusedImagePaths(root,@[@{@"path":path(@"Report.html"),@"text":@"<p>No image references</p>"}],&error);Check([unused containsObject:path(@"Report/used.png")],@"open current text supersedes older saved references");
    NSString *absolute=[NSURL fileURLWithPath:path(@"Report/unused.png")].absoluteString;
    unused=SINUnusedImagePaths(root,@[@{@"path":[external stringByAppendingPathComponent:@"Outside.html"],@"text":[NSString stringWithFormat:@"<img src='%@'>",absolute]}],&error);Check(![unused containsObject:path(@"Report/unused.png")],@"open document outside scan folder protects absolute references");
    unused=SINUnusedImagePaths(root,@[@{@"path":path(@"Report.html"),@"text":@"<base href='Report/'><img src='used.png'><img src='A&#38;B.png'><img src='percent%2520.png'>"}],&error);Check(![unused containsObject:path(@"Report/used.png")]&&![unused containsObject:path(@"Report/A&B.png")]&&![unused containsObject:path(@"Report/percent%20.png")],@"base href, numeric entities and literal percent filenames resolve correctly");
    unused=SINUnusedImagePaths(root,@[@{@"path":path(@"Report.html"),@"text":@"<img src='sin-asset://document/Report/used.png'>"}],&error);Check(![unused containsObject:path(@"Report/used.png")],@"native document URLs preserve referenced image");
    if([fm fileExistsAtPath:path(@"Report/USED.PNG")]){unused=SINUnusedImagePaths(root,@[@{@"path":path(@"Report.html"),@"text":@"<img src='Report/USED.PNG'>"}],&error);Check(![unused containsObject:path(@"Report/used.png")],@"filesystem identity respects case-insensitive volume references");}
    error=nil;unused=SINUnusedImagePaths(root,@[@{@"path":path(@"Report.html"),@"text":@"<img src='Report/&unknown;.png'>"}],&error);Check(!unused&&error,@"uncertain local entity aborts cleanup instead of guessing unused");
    unsigned char invalid[]={0xff,0xfe,0xff};[[NSData dataWithBytes:invalid length:3]writeToFile:path(@"Unreadable.html") atomically:YES];error=nil;unused=SINUnusedImagePaths(root,@[],&error);Check(!unused&&error,@"undecodable HTML aborts scan");[fm removeItemAtPath:path(@"Unreadable.html") error:nil];
    error=nil;unused=SINUnusedImagePaths(path(@"linked-directory"),@[],&error);Check(!unused&&error,@"symbolic link scan root rejected");
    error=nil;Check(SINFolderContainsReferencedFiles(path(@"Report"),@[@{@"path":path(@"Report.html"),@"text":@"<img srcset='Report/first.jpg 1x, Report/second.jpg 2x'>"}],&error)&&!error,@"folder guard recognizes srcset references");
    Check(SINFolderContainsReferencedFiles(path(@"Report"),@[@{@"path":path(@"Report.html"),@"text":@"<a href='Report/linked.svg'>link</a>"}],&error),@"folder guard recognizes href references");
    Check(SINFolderContainsReferencedFiles(path(@"Report"),@[@{@"path":path(@"Report.html"),@"text":@"<p style=\"background:url(Report/background.webp)\">x</p>"}],&error),@"folder guard recognizes CSS references");
    Check(!SINFolderContainsReferencedFiles(path(@"Report"),@[@{@"path":path(@"Report.html"),@"text":@"<img src='Report/missing.png'>"}],&error),@"missing references do not block an otherwise unused folder");
    error=nil;Check(SINFolderContainsReferencedFiles(path(@"Report"),@[@{@"path":path(@"Report.html"),@"text":@"<img src='Report/&unknown;.png'>"}],&error)&&error,@"folder guard fails closed on uncertain references");
    error=nil;Check(SINFolderContainsReferencedFiles(path(@"MissingFolder"),@[],&error)&&error,@"folder guard fails closed on missing directory");
    Check([fm fileExistsAtPath:path(@"Report/unused.png")]&&[fm fileExistsAtPath:[external stringByAppendingPathComponent:@"External/unused.png"]],@"scanning never deletes any files");
    [fm removeItemAtPath:root error:nil];[fm removeItemAtPath:external error:nil];printf("PASS: %lu unused image checks\n",(unsigned long)checks);
}return 0;}
