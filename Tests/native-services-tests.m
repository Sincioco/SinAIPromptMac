#import <AppKit/AppKit.h>
#import "../Sources/SINNativeServices.h"
static NSUInteger checks=0;
static void Check(BOOL condition,NSString *message) { checks++;if(!condition){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);} }
static id Request(SINNativeServices *services,NSDictionary *message) { __block id value=nil;__block BOOL called=NO;BOOL handled=[services handleMessage:message completion:^(id result,NSError *error){Check(!error,error.localizedDescription?:@"request succeeds");value=result;called=YES;}];Check(handled,@"message recognized");Check(called,@"synchronous callback delivered");return value; }
@interface SINRegionPicker : NSObject
@property(nonatomic) NSArray<NSDictionary *> *captures;
@property(nonatomic) NSMutableArray<NSWindow *> *windows;
@property(nonatomic) NSPoint pointer;
@property(nonatomic) NSPoint start;
@property(nonatomic) BOOL dragging;
@property(nonatomic,copy) void (^completion)(NSData *,NSError *);
- (void)finish:(BOOL)cancelled;
@end
static id ReadImage(SINNativeServices *services,NSString *source,NSError **outError) {
    __block BOOL done=NO;__block id result=nil;__block NSError *failure=nil;
    Check([services handleMessage:@{@"type":@"read-image",@"source":source} completion:^(id value,NSError *error){Check(NSThread.isMainThread,@"image completion runs on main queue");result=value;failure=error;done=YES;}],@"read image recognized");
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(done,@"image completion delivered");if(outError)*outError=failure;return result;
}
static NSImage *SolidImage(NSColor *color,NSInteger width,NSInteger height,NSSize logical) {
    NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for(NSInteger x=0;x<width;x++)for(NSInteger y=0;y<height;y++)[bitmap setColor:color atX:x y:y];NSImage *image=[[NSImage alloc] initWithSize:logical];[image addRepresentation:bitmap];image.size=logical;return image;
}
static void CaptureTests(void) {
    NSImage *red=SolidImage([NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1],8,4,NSMakeSize(8,4)),*blue=SolidImage([NSColor colorWithDeviceRed:0 green:0 blue:1 alpha:1],16,8,NSMakeSize(8,4));
    NSArray *captures=@[@{@"frame":[NSValue valueWithRect:NSMakeRect(-8,0,8,4)],@"image":red,@"scale":@1},@{@"frame":[NSValue valueWithRect:NSMakeRect(0,0,8,4)],@"image":blue,@"scale":@2}];
    SINRegionPicker *picker=[SINRegionPicker new];picker.captures=captures;picker.windows=NSMutableArray.new;picker.start=NSMakePoint(-2,0);picker.pointer=NSMakePoint(2,4);picker.dragging=YES;
    __block NSData *png=nil;__block NSError *failure=nil;__block NSUInteger calls=0;picker.completion=^(NSData *data,NSError *error){png=data;failure=error;calls++;};[picker finish:NO];[picker finish:NO];
    Check(png&&!failure&&calls==1,@"region selection completes once");NSBitmapImageRep *bitmap=[NSBitmapImageRep imageRepWithData:png];Check(bitmap.pixelsWide==8&&bitmap.pixelsHigh==8,@"mixed-scale cross-display region uses maximum pixel density");
    NSColor *left=[[bitmap colorAtX:1 y:1] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace],*right=[[bitmap colorAtX:6 y:1] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];Check(left.redComponent>.9&&left.blueComponent<.1&&right.blueComponent>.9&&right.redComponent<.1,@"cross-display crop preserves left and right pixels");
    picker=SINRegionPicker.new;picker.captures=captures;picker.start=NSZeroPoint;picker.pointer=NSMakePoint(.5,.5);picker.dragging=YES;png=nil;picker.completion=^(NSData *data,NSError *error){png=data;failure=error;};[picker finish:NO];bitmap=[NSBitmapImageRep imageRepWithData:png];Check(bitmap.pixelsWide==1&&bitmap.pixelsHigh==1,@"precision keyboard selection supports one Retina pixel");
    picker=SINRegionPicker.new;picker.captures=captures;__block BOOL cancelled=NO;picker.completion=^(NSData *data,NSError *error){cancelled=data==nil&&error==nil;};[picker finish:YES];Check(cancelled,@"region cancellation does not fabricate an image or error");
}
static void ClipboardTests(SINNativeServices *services,NSData *png,NSString *dataURL,NSString *root) {
    NSPasteboard *board=NSPasteboard.generalPasteboard;NSMutableArray<NSPasteboardItem *> *saved=NSMutableArray.new;BOOL complete=YES;
    for(NSPasteboardItem *item in board.pasteboardItems){NSPasteboardItem *copy=NSPasteboardItem.new;for(NSPasteboardType type in item.types){NSData *data=[item dataForType:type];if(!data){complete=NO;break;}[copy setData:data forType:type];}[saved addObject:copy];}
    if(!complete){printf("SKIP: clipboard tests because an existing clipboard format could not be materialized safely\n");return;}
    NSMutableArray *results=NSMutableArray.new;NSString *identifier=services.documentID;
    id(^request)(NSDictionary *)=^id(NSDictionary *message){__block id value=nil;__block NSError *error=nil;__block BOOL called=NO;BOOL recognized=[services handleMessage:message completion:^(id result,NSError *failure){value=result;error=failure;called=YES;}];[results addObject:@[@(recognized&&called&&!error),[@"clipboard request: " stringByAppendingString:message[@"type"]]]];return value;};
    @try {
        NSString *portable=@"<p>Portable <img src='data:image/png;base64,AA=='></p>",*internal=@"<p>Original <img src='My%20Prompt/image.png'></p>";
        request(@{@"type":@"editor-copy",@"html":portable,@"internalHtml":internal,@"text":@"plain text"});NSDictionary *value=request(@{@"type":@"editor-paste"});[results addObject:@[@([value[@"html"] isEqual:internal]&&[value[@"preserveImageMarkup"] boolValue]&&[value[@"text"] isEqual:@"plain text"]),@"same-document clipboard preserves image references"]];
        services.documentID=@"another-document";value=request(@{@"type":@"editor-paste"});[results addObject:@[@([value[@"html"] isEqual:portable]),@"cross-document clipboard uses portable HTML"]];
        value=request(@{@"type":@"editor-paste",@"textOnly":@YES});[results addObject:@[@([value[@"text"] isEqual:@"plain text"]&&value.count==1),@"Paste as Text ignores rich HTML and internal fragments"]];
        [board setString:@"First\r\n\r\nSecond\rThird\n" forType:NSPasteboardTypeString];value=request(@{@"type":@"editor-paste",@"textOnly":@YES});[results addObject:@[@([value[@"text"] isEqual:@"First\r\n\r\nSecond\rThird\n"]),@"native plain-text clipboard retains blank and trailing line breaks for the editor"]];
        request(@{@"type":@"copy-image",@"data":dataURL});NSBitmapImageRep *copied=[NSBitmapImageRep imageRepWithData:[board dataForType:NSPasteboardTypePNG]];[results addObject:@[@(copied.pixelsWide==2&&copied.pixelsHigh==2&&![board dataForType:NSPasteboardTypeHTML]&&![board dataForType:@"com.sinaiprompt.annotation-objects"]),@"Copy Image publishes original-size image pixels without HTML or editable object metadata"]];
        [board clearContents];[board setString:@"<html><!--StartFragment--><b>ü text</b><!--EndFragment--></html>" forType:NSPasteboardTypeHTML];value=request(@{@"type":@"editor-paste"});[results addObject:@[@([value[@"html"] isEqual:@"<b>ü text</b>"]),@"HTML clipboard fragments retain Unicode"]];
        NSString *objects=@"{\"name\":\"Copied objects\",\"objects\":[]}";request(@{@"type":@"annotation-copy",@"format":@"png",@"content":dataURL,@"objects":objects});value=request(@{@"type":@"annotation-paste"});[results addObject:@[@([value[@"objects"] isEqual:objects]&&[[board dataForType:NSPasteboardTypePNG] isEqual:png]),@"annotation copy includes editable objects and public PNG"]];
        [board clearContents];[board setData:png forType:NSPasteboardTypePNG];value=request(@{@"type":@"editor-paste"});[results addObject:@[@([value[@"image"] isEqual:dataURL]),@"external PNG clipboard is read as an image"]];
        NSString *svg=@"<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'/>";request(@{@"type":@"annotation-copy",@"format":@"svg",@"content":svg,@"objects":objects});[results addObject:@[@([[board stringForType:NSPasteboardTypeString] isEqual:svg]&&[board dataForType:@"public.svg-image"]!=nil),@"SVG clipboard offers native SVG and text formats"]];
        [board clearContents];[board setData:[svg dataUsingEncoding:NSUTF8StringEncoding] forType:@"public.svg-image"];value=request(@{@"type":@"annotation-paste"});[results addObject:@[@([value[@"image"] hasPrefix:@"data:image/svg+xml;base64,"]),@"external SVG clipboard imports without object metadata"]];
        NSString *path=[root stringByAppendingPathComponent:@"clipboard.md"];[@"# Markdown image\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];[board clearContents];[board writeObjects:@[[NSURL fileURLWithPath:path]]];value=request(@{@"type":@"editor-paste"});[results addObject:@[@([value[@"markdown"] isEqual:@"# Markdown image\n"]&&[value[@"base"] hasPrefix:@"file:"]),@"Markdown file clipboard carries source base URL"]];
        [board clearContents];[board setString:@"No markup" forType:NSPasteboardTypeString];value=request(@{@"type":@"editor-paste"});[results addObject:@[@([value[@"text"] isEqual:@"No markup"]),@"plain clipboard text round trips"]];
    } @catch(NSException *exception) {[results addObject:@[@NO,exception.reason?:@"Unexpected clipboard exception"]];}
    @finally {services.documentID=identifier;[board clearContents];if(saved.count)[board writeObjects:saved];}
    NSArray *restored=board.pasteboardItems;BOOL restoredExactly=restored.count==saved.count;
    for(NSUInteger i=0;i<MIN(restored.count,saved.count);i++)for(NSPasteboardType type in saved[i].types)if(![[restored[i] dataForType:type] isEqual:[saved[i] dataForType:type]])restoredExactly=NO;
    Check(restoredExactly,@"clipboard contents and formats restored after tests");for(NSArray *result in results)Check([result[0] boolValue],result[1]);
}

int main(void) { @autoreleasepool {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"SinAIPrompt-services-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];NSFileManager *fm=NSFileManager.defaultManager;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    SINNativeServices *services=[[SINNativeServices alloc] initWithDataDirectory:root];services.documentPath=[root stringByAppendingPathComponent:@"My Prompt.html"];
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:8 bitsPerPixel:32];
    memset(rep.bitmapData,127,16);NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];NSString *url=[@"data:image/png;base64," stringByAppendingString:[png base64EncodedStringWithOptions:0]];
    NSString *saved=Request(services,@{@"type":@"save-image",@"data":url});Check([saved hasPrefix:@"My%20Prompt/image-"],@"image stored relative to HTML with escaped folder");
    NSString *path=[services localPathForSource:saved base:nil error:nil];Check([fm fileExistsAtPath:path],@"separate PNG exists");
    Check([Request(services,@{@"type":@"save-image",@"data":url}) isEqual:saved],@"identical pixels reuse file");
    NSString *renamed=[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"A renamed image.png"];[fm moveItemAtPath:path toPath:renamed error:nil];
    Check([Request(services,@{@"type":@"reuse-image",@"data":url}) isEqual:@"My%20Prompt/A%20renamed%20image.png"],@"reuse preserves renamed filename");
    NSError *error=nil;Check(![SINNativeServices savePNGDataURL:@"data:image/png;base64,not-png" documentPath:services.documentPath reuseOnly:NO error:&error]&&error,@"invalid pixels rejected");
    NSString *original=[root stringByAppendingPathComponent:@"literal %20 # ü.png"];[png writeToFile:original atomically:YES];
    NSDictionary *mapping=Request(services,@{@"type":@"map-original-image",@"source":[NSURL fileURLWithPath:original].absoluteString});
    Check([[[services localPathForSource:mapping[@"display"] base:nil error:nil] precomposedStringWithCanonicalMapping] isEqual:original.precomposedStringWithCanonicalMapping],@"original display URL round trips percent signs, spaces, hash and Unicode");
    NSDictionary *reference=Request(services,@{@"type":@"reference-image",@"source":[NSURL fileURLWithPath:original].absoluteString,@"absolute":@NO});
    Check([[[services localPathForSource:reference[@"reference"] base:nil error:nil] precomposedStringWithCanonicalMapping] isEqual:original.precomposedStringWithCanonicalMapping],@"relative reference resolves correctly");
    NSString *newFolder=[root stringByAppendingPathComponent:@"subfolder"];services.saveAsPath=[newFolder stringByAppendingPathComponent:@"Moved.html"];
    NSString *relocated=Request(services,@{@"type":@"relocate-original-image",@"source":reference[@"reference"]});Check([relocated hasPrefix:@"../"],@"Save As relocates relative original references");
    Check([[services localPathForSource:@"sin-asset://document/My%20Prompt/A%20renamed%20image.png" base:nil error:nil] isEqual:renamed],@"document scheme resolves current document folder");
    for(NSUInteger i=0;i<12;i++)Request(services,@{@"type":@"color-used",@"value":[NSString stringWithFormat:@"#%06lx",(unsigned long)i]});
    NSArray *colors=Request(services,@{@"type":@"recent-colors"});Check(colors.count==10&&[colors[0] isEqual:@"#00000b"],@"recent colors retain latest ten");
    Request(services,@{@"type":@"color-used",@"value":@"#000003"});colors=Request(services,@{@"type":@"recent-colors"});Check(colors.count==10&&[colors[0] isEqual:@"#000003"],@"recent colors deduplicate");
    Request(services,@{@"type":@"color-used",@"value":@"not-a-color"});Check([Request(services,@{@"type":@"recent-colors"}) isEqual:colors],@"invalid colors ignored");
    NSArray *templates=@[@{@"name":@"Test",@"objects":@[]}];Request(services,@{@"type":@"templates-save",@"templates":templates});Check([Request(services,@{@"type":@"templates-load"}) isEqual:templates],@"object templates round trip");
    Check([[SINNativeServices youTubeIDForURL:[NSURL URLWithString:@"https://youtu.be/abcdefghijk?t=10"]] isEqual:@"abcdefghijk"],@"short YouTube URL parsed");
    Check([[SINNativeServices youTubeIDForURL:[NSURL URLWithString:@"https://www.youtube.com/watch?v=abcdefghijk"]] isEqual:@"abcdefghijk"],@"watch YouTube URL parsed");
    Check(![SINNativeServices youTubeIDForURL:[NSURL URLWithString:@"https://youtube.com.attacker.test/watch?v=abcdefghijk"]],@"lookalike YouTube host rejected");
    Check(![SINNativeServices youTubeIDForURL:[NSURL URLWithString:@"https://user@youtube.com/watch?v=abcdefghijk"]],@"URL credentials rejected");
    Check(![services handleMessage:@{@"type":@"other"} completion:^(id result,NSError *e){}],@"unknown messages left to shell");
    NSError *readError=nil;NSString *read=ReadImage(services,mapping[@"display"],&readError);Check([read hasPrefix:@"data:image/png;base64,"]&&!readError,@"read original display URL returns PNG");
    NSString *svgPath=[root stringByAppendingPathComponent:@"image.svg"];[@"<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"/>" writeToFile:svgPath atomically:YES encoding:NSUTF8StringEncoding error:nil];read=ReadImage(services,[NSURL fileURLWithPath:svgPath].absoluteString,&readError);Check([read hasPrefix:@"data:image/svg+xml;base64,"]&&!readError,@"SVG stays vector until browser rasterizes it");
    read=ReadImage(services,@"missing-file.png",&readError);Check(!read&&readError,@"missing image returns an error");
    error=nil;Check(![services localPathForSource:@"https://example.com/image.png" base:nil error:&error]&&error,@"remote URL cannot masquerade as local file");
    NSString *based=[services localPathForSource:@"A%20renamed%20image.png" base:@"My%20Prompt/" error:nil];Check([based isEqual:renamed],@"relative base href resolves image folder");
    ClipboardTests(services,png,url,root);CaptureTests();
    [fm removeItemAtPath:root error:nil];printf("PASS: %lu native service checks\n",(unsigned long)checks);
}return 0; }
