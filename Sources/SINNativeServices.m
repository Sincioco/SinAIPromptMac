#import "SINNativeServices.h"
#import "SINSliceExport.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

static NSString * const SINFragmentType = @"com.sinaiprompt.document-images.v1";
static NSString * const SINObjectsType = @"com.sinaiprompt.annotation-objects";
static NSError *SINError(NSString *message) { return [NSError errorWithDomain:@"SinAIPrompt" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static NSString *SINString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSString *SINEncode(NSString *value) { return [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"]]; }
static NSString *SINDataURL(NSData *data, NSString *mime) { return [NSString stringWithFormat:@"data:%@;base64,%@",mime,[data base64EncodedStringWithOptions:0]]; }
static NSData *SINDecode(NSString *url, NSError **error) {
    NSRange comma = [url rangeOfString:@","];
    if (![url hasPrefix:@"data:"] || comma.location == NSNotFound) { if(error)*error=SINError(@"The image data is invalid."); return nil; }
    NSString *header = [url substringToIndex:comma.location], *content = [url substringFromIndex:comma.location+1];
    NSData *data = [header.lowercaseString containsString:@";base64"] ? [[NSData alloc] initWithBase64EncodedString:content options:NSDataBase64DecodingIgnoreUnknownCharacters] : [[content stringByRemovingPercentEncoding] dataUsingEncoding:NSUTF8StringEncoding];
    if(!data.length && error)*error=SINError(@"The image data is empty or invalid."); return data;
}
static NSString *SINHash(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hash = [NSMutableString stringWithCapacity:64]; for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[hash appendFormat:@"%02x",digest[i]]; return hash;
}
static NSString *SINRelativePath(NSString *path, NSString *directory) {
    NSArray *target=path.stringByStandardizingPath.pathComponents, *base=directory.stringByStandardizingPath.pathComponents;
    NSUInteger same=0; while(same<MIN(target.count,base.count)&&[target[same] isEqual:base[same]])same++;
    NSMutableArray *parts=[NSMutableArray array]; for(NSUInteger i=same;i<base.count;i++)[parts addObject:@".."];
    for(NSUInteger i=same;i<target.count;i++)[parts addObject:SINEncode(target[i])]; return [parts componentsJoinedByString:@"/"];
}
static BOOL SINWebURL(NSURL *url) { return ([@[@"https",@"http"] containsObject:url.scheme.lowercaseString] && !url.user.length && !url.password.length && url.host.length); }

/// Bound optional preview requests before appending data; no cookies or persistent cache.
@interface SINURLRead : NSObject <NSURLSessionDataDelegate>
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSMutableData *bytes;
@property(nonatomic) NSURLResponse *response;
@property(nonatomic) NSUInteger limit;
@property(nonatomic) NSUInteger redirects;
@property(nonatomic,copy) void (^completion)(NSData *,NSURLResponse *,NSError *);
@end
@implementation SINURLRead
+ (void)read:(NSURL *)url limit:(NSUInteger)limit completion:(void(^)(NSData *,NSURLResponse *,NSError *))completion {
    SINURLRead *read=[SINURLRead new]; read.bytes=[NSMutableData data];read.limit=limit;read.completion=completion;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.timeoutIntervalForRequest=8;config.timeoutIntervalForResource=12;config.HTTPCookieStorage=nil;config.URLCache=nil;
    read.session=[NSURLSession sessionWithConfiguration:config delegate:read delegateQueue:nil];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];[request setValue:@"SinAIPromptMac/1.0" forHTTPHeaderField:@"User-Agent"];
    [[read.session dataTaskWithRequest:request] resume];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.response=response; BOOL valid=[response isKindOfClass:NSHTTPURLResponse.class] && [(NSHTTPURLResponse *)response statusCode]>=200 && [(NSHTTPURLResponse *)response statusCode]<300;
    completionHandler(valid && response.expectedContentLength<=(int64_t)self.limit ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler { completionHandler(SINWebURL(request.URL)&&++self.redirects<=5?request:nil); }
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data { if(self.bytes.length+data.length>self.limit)[task cancel];else[self.bytes appendData:data]; }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    self.completion(error?nil:self.bytes,self.response,error);self.completion=nil;[session finishTasksAndInvalidate];self.session=nil;
}
@end

// The countdown and selection overlays own no document state. Their callbacks
// return a PNG or nil when cancelled; the caller owns window restoration.
@interface SINCapturePanel : NSPanel
@end
@implementation SINCapturePanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface SINCaptureCountdown : NSObject
@property(nonatomic) SINCapturePanel *panel;
@property(nonatomic) NSTextField *label;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSDate *deadline;
@property(nonatomic,copy) void (^completion)(BOOL cancelled);
- (void)start:(NSTimeInterval)seconds completion:(void(^)(BOOL))completion;
@end
@implementation SINCaptureCountdown
- (void)start:(NSTimeInterval)seconds completion:(void(^)(BOOL))completion {
    self.completion=completion;self.deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    self.panel=[[SINCapturePanel alloc] initWithContentRect:NSMakeRect(0,0,280,205) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];self.panel.title=@"Capture countdown";self.panel.level=NSFloatingWindowLevel;self.panel.hidesOnDeactivate=NO;self.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;self.panel.releasedWhenClosed=NO;
    self.label=[NSTextField labelWithString:@""];self.label.frame=NSMakeRect(20,68,240,116);self.label.font=[NSFont monospacedDigitSystemFontOfSize:88 weight:NSFontWeightMedium];self.label.alignment=NSTextAlignmentCenter;[self.panel.contentView addSubview:self.label];
    NSButton *cancel=[NSButton buttonWithTitle:@"Cancel Capture" target:self action:@selector(cancel:)];cancel.frame=NSMakeRect(65,22,150,32);cancel.keyEquivalent=@"\e";[self.panel.contentView addSubview:cancel];
    [self.panel center];[self.panel makeKeyAndOrderFront:nil];
    __weak SINCaptureCountdown *weakSelf=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *timer){[weakSelf tick];}];[self tick];
}
- (void)tick { NSTimeInterval remaining=self.deadline.timeIntervalSinceNow;if(remaining<=0){[self finish:NO];return;}self.label.stringValue=[NSString stringWithFormat:@"%ld",(long)ceil(remaining)]; }
- (void)cancel:(id)sender { [self finish:YES]; }
- (void)finish:(BOOL)cancelled { if(!self.completion)return;[self.timer invalidate];self.timer=nil;[self.panel orderOut:nil];void(^callback)(BOOL)=self.completion;self.completion=nil;callback(cancelled); }
@end

@class SINRegionPicker;
@interface SINRegionView : NSView
@property(nonatomic,weak) SINRegionPicker *picker;
@property(nonatomic) NSDictionary *capture;
@end
@interface SINRegionPicker : NSObject
@property(nonatomic) NSArray<NSDictionary *> *captures;
@property(nonatomic) NSMutableArray<NSWindow *> *windows;
@property(nonatomic) NSPoint pointer;
@property(nonatomic) NSPoint start;
@property(nonatomic) BOOL dragging;
@property(nonatomic) BOOL finished;
@property(nonatomic) NSUInteger samplePixels;
@property(nonatomic,copy) void (^completion)(NSData *,NSError *);
- (void)present:(NSArray<NSDictionary *> *)captures completion:(void(^)(NSData *,NSError *))completion;
- (void)updatePointer;
- (void)finish:(BOOL)cancelled;
- (NSRect)selection;
- (void)key:(NSEvent *)event;
@end

@implementation SINRegionView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.crosshairCursor]; }
- (void)updateTrackingAreas { [super updateTrackingAreas];for(NSTrackingArea *area in self.trackingAreas.copy)[self removeTrackingArea:area];[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved|NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]]; }
- (void)mouseEntered:(NSEvent *)event { [self.window makeKeyWindow];[self.window makeFirstResponder:self];[self.picker updatePointer]; }
- (void)mouseMoved:(NSEvent *)event { [self.picker updatePointer]; }
- (void)mouseDown:(NSEvent *)event { [self.picker updatePointer];self.picker.start=self.picker.pointer;self.picker.dragging=YES;[self.picker updatePointer]; }
- (void)mouseDragged:(NSEvent *)event { [self.picker updatePointer]; }
- (void)mouseUp:(NSEvent *)event { [self.picker updatePointer];[self.picker finish:NO]; }
- (void)rightMouseDown:(NSEvent *)event { [self.picker finish:YES]; }
- (void)keyDown:(NSEvent *)event { [self.picker key:event]; }
- (void)scrollWheel:(NSEvent *)event { NSInteger pixels=(NSInteger)self.picker.samplePixels+(event.scrollingDeltaY>0?-2:2);self.picker.samplePixels=MAX(11,MIN(61,pixels));[self.picker updatePointer]; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect screen=[self.capture[@"frame"] rectValue];NSImage *image=self.capture[@"image"];[image drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:NO hints:nil];
    NSRect selection=self.picker.selection;selection.origin.x-=screen.origin.x;selection.origin.y-=screen.origin.y;
    if(self.picker.dragging&&!NSIsEmptyRect(selection)) { NSBezierPath *border=[NSBezierPath bezierPathWithRect:NSInsetRect(selection,.5,.5)];[NSColor.whiteColor setStroke];border.lineWidth=3;[border stroke];[NSColor.blackColor setStroke];border.lineWidth=1;CGFloat dash[]={5,5};[border setLineDash:dash count:2 phase:0];[border stroke]; }
    NSPoint pointer=self.picker.pointer;if(!NSPointInRect(pointer,screen))return;
    NSPoint local=NSMakePoint(pointer.x-screen.origin.x,pointer.y-screen.origin.y);CGFloat size=248,margin=18;
    NSRect box=NSMakeRect(local.x<screen.size.width/2?MAX(margin,screen.size.width-size-16-margin):margin,local.y<screen.size.height/2?MAX(margin,screen.size.height-size-68-margin):margin,size+16,size+68);
    [[NSColor colorWithWhite:.11 alpha:1] setFill];NSRectFill(box);[NSColor.whiteColor setStroke];NSFrameRectWithWidth(box,2);
    CGFloat scale=[self.capture[@"scale"] doubleValue],sample=MIN(self.picker.samplePixels,MIN(image.size.width*scale,image.size.height*scale));CGFloat logical=sample/scale;
    NSRect source=NSMakeRect(MAX(0,MIN(image.size.width-logical,local.x-logical/2)),MAX(0,MIN(image.size.height-logical,local.y-logical/2)),logical,logical);
    // Align the sample to the frozen bitmap's pixel grid.
    source.origin.x=floor(source.origin.x*scale)/scale;source.origin.y=floor(source.origin.y*scale)/scale;
    NSRect zoom=NSMakeRect(box.origin.x+8,box.origin.y+60,size,size);NSGraphicsContext *context=NSGraphicsContext.currentContext;NSImageInterpolation interpolation=context.imageInterpolation;context.imageInterpolation=NSImageInterpolationNone;
    [image drawInRect:zoom fromRect:source operation:NSCompositingOperationCopy fraction:1 respectFlipped:NO hints:nil];context.imageInterpolation=interpolation;
    [[NSColor colorWithWhite:0 alpha:.25] setStroke];NSBezierPath *grid=NSBezierPath.bezierPath;grid.lineWidth=.5;
    for(NSUInteger i=0;i<=sample;i++){CGFloat offset=size*i/sample;[grid moveToPoint:NSMakePoint(zoom.origin.x+offset,zoom.origin.y)];[grid lineToPoint:NSMakePoint(zoom.origin.x+offset,NSMaxY(zoom))];[grid moveToPoint:NSMakePoint(zoom.origin.x,zoom.origin.y+offset)];[grid lineToPoint:NSMakePoint(NSMaxX(zoom),zoom.origin.y+offset)];}[grid stroke];
    CGFloat px=(floor((local.x-source.origin.x)*scale)+.5)*size/sample,py=(floor((local.y-source.origin.y)*scale)+.5)*size/sample;[NSColor.systemCyanColor setStroke];NSBezierPath *cross=NSBezierPath.bezierPath;cross.lineWidth=1;[cross moveToPoint:NSMakePoint(zoom.origin.x+px,zoom.origin.y)];[cross lineToPoint:NSMakePoint(zoom.origin.x+px,NSMaxY(zoom))];[cross moveToPoint:NSMakePoint(zoom.origin.x,zoom.origin.y+py)];[cross lineToPoint:NSMakePoint(NSMaxX(zoom),zoom.origin.y+py)];[cross stroke];
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:NSColor.whiteColor};
    NSString *caption=self.picker.dragging?[NSString stringWithFormat:@"%.0f × %.0f px",selection.size.width*scale,selection.size.height*scale]:@"Drag to select · Escape cancels";
    [caption drawAtPoint:NSMakePoint(box.origin.x+10,box.origin.y+38) withAttributes:attributes];[@"Arrows: 1 pixel · Shift: 10 pixels" drawAtPoint:NSMakePoint(box.origin.x+10,box.origin.y+22) withAttributes:attributes];[@"Scroll: magnification" drawAtPoint:NSMakePoint(box.origin.x+10,box.origin.y+6) withAttributes:attributes];
}
@end

@implementation SINRegionPicker
- (void)present:(NSArray<NSDictionary *> *)captures completion:(void(^)(NSData *,NSError *))completion {
    self.captures=captures;self.completion=completion;self.windows=NSMutableArray.new;self.samplePixels=31;self.pointer=NSEvent.mouseLocation;
    for(NSDictionary *capture in captures){NSRect frame=[capture[@"frame"] rectValue];SINCapturePanel *window=[[SINCapturePanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];window.level=NSScreenSaverWindowLevel;window.hidesOnDeactivate=NO;window.releasedWhenClosed=NO;window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;window.acceptsMouseMovedEvents=YES;window.backgroundColor=NSColor.blackColor;window.hasShadow=NO;
        SINRegionView *view=[[SINRegionView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width,frame.size.height)];view.picker=self;view.capture=capture;window.contentView=view;[window orderFrontRegardless];[window makeFirstResponder:view];[self.windows addObject:window];}
    [NSApp activateIgnoringOtherApps:YES];for(NSWindow *window in self.windows)if(NSPointInRect(self.pointer,window.frame)){[window makeKeyWindow];break;}[self updatePointer];
}
- (void)updatePointer { self.pointer=NSEvent.mouseLocation;for(NSWindow *window in self.windows)[window.contentView setNeedsDisplay:YES]; }
- (NSRect)selection { return NSMakeRect(MIN(self.start.x,self.pointer.x),MIN(self.start.y,self.pointer.y),fabs(self.start.x-self.pointer.x),fabs(self.start.y-self.pointer.y)); }
- (void)key:(NSEvent *)event {
    if(event.keyCode==53){[self finish:YES];return;}
    if(event.keyCode==36&&self.dragging){[self finish:NO];return;}
    CGFloat scale=1;for(NSDictionary *capture in self.captures)if(NSPointInRect(self.pointer,[capture[@"frame"] rectValue])){scale=[capture[@"scale"] doubleValue];break;}
    CGFloat step=(event.modifierFlags&NSEventModifierFlagShift?10:1)/scale;NSPoint point=self.pointer;
    switch(event.keyCode){case 123:point.x-=step;break;case 124:point.x+=step;break;case 125:point.y-=step;break;case 126:point.y+=step;break;case 49:if(!self.dragging){self.start=point;self.dragging=YES;}else[self finish:NO];return;default:return;}
    CGFloat top=NSMaxY(NSScreen.screens.firstObject.frame);CGWarpMouseCursorPosition(CGPointMake(point.x,top-point.y));[self updatePointer];
}
- (void)finish:(BOOL)cancelled {
    if(self.finished)return;NSRect region=self.selection;CGFloat pixelScale=1;for(NSDictionary *capture in self.captures)if(NSIntersectsRect(region,[capture[@"frame"] rectValue]))pixelScale=MAX(pixelScale,[capture[@"scale"] doubleValue]);if(!cancelled&&(region.size.width*pixelScale<1||region.size.height*pixelScale<1)){self.dragging=NO;[self updatePointer];return;}self.finished=YES;
    for(NSWindow *window in self.windows)[window orderOut:nil];NSData *png=nil;NSError *error=nil;
    if(!cancelled){CGFloat scale=1;for(NSDictionary *capture in self.captures)if(NSIntersectsRect(region,[capture[@"frame"] rectValue]))scale=MAX(scale,[capture[@"scale"] doubleValue]);
        NSInteger width=MAX(1,ceil(region.size.width*scale)),height=MAX(1,ceil(region.size.height*scale));
        if((uint64_t)width*(uint64_t)height>160000000)error=SINError(@"The selected region is too large. Select a smaller area.");
        else {NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            if(!bitmap)error=SINError(@"The selected region could not be allocated.");else {NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];[NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=context;[NSColor.clearColor setFill];NSRectFill(NSMakeRect(0,0,width,height));context.imageInterpolation=NSImageInterpolationHigh;
                for(NSDictionary *capture in self.captures){NSRect frame=[capture[@"frame"] rectValue],intersection=NSIntersectionRect(region,frame);if(NSIsEmptyRect(intersection))continue;NSRect source=NSOffsetRect(intersection,-frame.origin.x,-frame.origin.y),destination=NSMakeRect((intersection.origin.x-region.origin.x)*scale,(intersection.origin.y-region.origin.y)*scale,intersection.size.width*scale,intersection.size.height*scale);[(NSImage *)capture[@"image"] drawInRect:destination fromRect:source operation:NSCompositingOperationCopy fraction:1 respectFlipped:NO hints:nil];}
                [NSGraphicsContext restoreGraphicsState];png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];if(!png)error=SINError(@"The selected region could not be encoded.");}}
    }
    void(^callback)(NSData *,NSError *)=self.completion;self.completion=nil;[self.windows removeAllObjects];self.captures=nil;if(callback)callback(png,error);
}
@end

@interface SINNativeServices ()
@property(nonatomic,strong) SINSliceExport *sliceExport;
@property(nonatomic) id captureController;
@property(nonatomic) BOOL captureActive;
@property(nonatomic, readwrite, copy) NSString *dataDirectory;
@end
@implementation SINNativeServices
- (instancetype)initWithDataDirectory:(NSString *)directory { if((self=[super init])) { _dataDirectory=[directory copy];_documentID=NSUUID.UUID.UUIDString;[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]; } return self; }
+ (NSData *)PNGDataFromData:(NSData *)data error:(NSError **)error {
    if(!data.length) { if(error)*error=SINError(@"There is no image data.");return nil; }
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    CGImageRef image=source?CGImageSourceCreateImageAtIndex(source,0,NULL):NULL;
    if(source)CFRelease(source);
    if(!image) { if(error)*error=SINError(@"This image cannot be decoded. Choose PNG, JPEG, GIF, TIFF, HEIC, BMP, or WebP.");return nil; }
    NSMutableData *result=[NSMutableData data];CGImageDestinationRef output=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)result,CFSTR("public.png"),1,NULL);
    CGImageDestinationAddImage(output,image,NULL);BOOL success=CGImageDestinationFinalize(output);CFRelease(output);CGImageRelease(image);
    if(!success) { if(error)*error=SINError(@"The PNG image could not be created.");return nil; } return result;
}
+ (NSString *)savePNGDataURL:(NSString *)dataURL documentPath:(NSString *)documentPath reuseOnly:(BOOL)reuseOnly error:(NSError **)error {
    if(!documentPath.length) { if(!reuseOnly&&error)*error=SINError(@"Save the HTML document before storing a separate image.");return nil; }
    NSData *raw=SINDecode(dataURL,error), *data=raw?[self PNGDataFromData:raw error:error]:nil;if(!data)return nil;
    NSString *folderName=documentPath.lastPathComponent.stringByDeletingPathExtension, *folder=[documentPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:folderName];
    NSFileManager *fm=NSFileManager.defaultManager;NSString *hash=SINHash(data);
    for(NSString *name in [fm contentsOfDirectoryAtPath:folder error:nil]) {
        if(![name.pathExtension.lowercaseString isEqual:@"png"])continue;NSString *path=[folder stringByAppendingPathComponent:name];
        NSDictionary *attributes=[fm attributesOfItemAtPath:path error:nil];if([attributes fileSize]!=data.length)continue;
        NSData *existing=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if([SINHash(existing) isEqual:hash])return [NSString stringWithFormat:@"%@/%@",SINEncode(folderName),SINEncode(name)];
    }
    if(reuseOnly)return nil;
    if(![fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSString *name=[NSString stringWithFormat:@"image-%@.png",hash], *path=[folder stringByAppendingPathComponent:name];
    if([fm fileExistsAtPath:path]) { name=[NSString stringWithFormat:@"image-%@.png",NSUUID.UUID.UUIDString];path=[folder stringByAppendingPathComponent:name]; }
    if(![data writeToFile:path options:NSDataWritingAtomic error:error])return nil;
    return [NSString stringWithFormat:@"%@/%@",SINEncode(folderName),SINEncode(name)];
}
- (NSURL *)baseURL:(NSString *)base document:(NSString *)document {
    NSURL *url=[NSURL fileURLWithPath:[(document.length?document:[self.dataDirectory stringByAppendingPathComponent:@"Untitled.html"]) stringByDeletingLastPathComponent] isDirectory:YES];
    if(!base.length)return url;
    NSURL *resolved=[NSURL URLWithString:base relativeToURL:url].absoluteURL;
    if([resolved.scheme isEqual:@"sin-asset"]&&[resolved.host isEqual:@"document"])return [NSURL fileURLWithPath:[[url.path stringByAppendingPathComponent:[resolved.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]] stringByStandardizingPath] isDirectory:[base hasSuffix:@"/"]];
    return resolved;
}
- (NSString *)localPathForSource:(NSString *)source base:(NSString *)base error:(NSError **)error {
    NSURL *url=[NSURL URLWithString:source];
    if([url.scheme isEqual:@"sin-asset"]) {
        NSString *decoded=[[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES].percentEncodedPath stringByRemovingPercentEncoding]?:url.path;
        if([url.host isEqual:@"original"]) { while([decoded hasPrefix:@"//"])decoded=[decoded substringFromIndex:1];return decoded.stringByStandardizingPath; }
        if([url.host isEqual:@"document"])return [[(self.documentPath.length?self.documentPath.stringByDeletingLastPathComponent:self.dataDirectory) stringByAppendingPathComponent:[decoded stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]] stringByStandardizingPath];
    }
    url=[NSURL URLWithString:source relativeToURL:[self baseURL:base document:self.documentPath]].absoluteURL;
    if(!url.isFileURL) { if(error)*error=SINError(@"This action requires a local image file.");return nil; }return url.path.stringByStandardizingPath;
}
- (NSDictionary *)mapSource:(NSString *)source base:(NSString *)base error:(NSError **)error {
    NSString *path=[self localPathForSource:source base:base error:error];if(!path)return nil;
    BOOL directory=NO;if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]||directory) { if(error)*error=SINError([NSString stringWithFormat:@"The original image is no longer at this location: %@",path]);return nil; }
    return @{ @"source":[NSURL fileURLWithPath:path].absoluteString,@"display":[@"sin-asset://original/" stringByAppendingString:SINEncode(path)] };
}
- (NSString *)referenceSource:(NSString *)source base:(NSString *)base absolute:(BOOL)absolute destination:(NSString *)destination error:(NSError **)error {
    NSString *path=[self localPathForSource:source base:base error:error];if(!path)return nil;
    NSURL *target=[self baseURL:destination?nil:base document:destination?:self.documentPath];
    if(absolute||!target.isFileURL)return [NSURL fileURLWithPath:path].absoluteString;
    return SINRelativePath(path,target.path);
}
- (void)readImage:(NSString *)source completion:(SINServiceCompletion)completion {
    if([source.lowercaseString hasPrefix:@"data:image/"]) { completion(source,nil);return; }
    void(^decode)(NSData *,NSError *)=^(NSData *bytes,NSError *error) {
        NSString *result=nil;
        if(bytes) {
            NSString *prefix=[[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(0,MIN(bytes.length,1024))] encoding:NSISOLatin1StringEncoding];
            if([prefix.lowercaseString containsString:@"<svg"])result=SINDataURL(bytes,@"image/svg+xml");
            else { NSData *png=[SINNativeServices PNGDataFromData:bytes error:&error];if(png)result=SINDataURL(png,@"image/png"); }
        }
        dispatch_async(dispatch_get_main_queue(),^{completion(result,error);});
    };
    NSURL *url=[NSURL URLWithString:source];
    if(SINWebURL(url)) { [SINURLRead read:url limit:32*1024*1024 completion:^(NSData *data,NSURLResponse *response,NSError *error){decode(data,error);}];return; }
    NSError *error=nil;NSString *path=[self localPathForSource:source base:nil error:&error];if(!path){completion(nil,error);return;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *readError=nil;NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&readError];decode(data,readError);});
}
- (id)readJSON:(NSString *)name fallback:(id)fallback { NSData *data=[NSData dataWithContentsOfFile:[self.dataDirectory stringByAppendingPathComponent:name]];return data?([NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil]?:fallback):fallback; }
- (BOOL)writeJSON:(id)value name:(NSString *)name error:(NSError **)error { NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:error];return data&&[data writeToFile:[self.dataDirectory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:error]; }
- (NSString *)pasteboardImage:(NSPasteboard *)board {
    NSData *png=[board dataForType:NSPasteboardTypePNG];if(png)return SINDataURL(png,@"image/png");
    NSData *tiff=[board dataForType:NSPasteboardTypeTIFF];if(tiff) { png=[SINNativeServices PNGDataFromData:tiff error:nil];if(png)return SINDataURL(png,@"image/png"); }
    NSData *svg=[board dataForType:@"public.svg-image"]?:[board dataForType:@"image/svg+xml"];return svg?SINDataURL(svg,@"image/svg+xml"):nil;
}
- (id)readEditorPasteboard {
    NSPasteboard *board=NSPasteboard.generalPasteboard;NSString *text=[board stringForType:NSPasteboardTypeString]?:@"";
    NSData *internal=[board dataForType:SINFragmentType];NSDictionary *fragment=internal?[NSJSONSerialization JSONObjectWithData:internal options:0 error:nil]:nil;
    if([fragment isKindOfClass:NSDictionary.class]&&[fragment[@"document"] isEqual:self.documentID]&&[fragment[@"html"] isKindOfClass:NSString.class])return @{ @"html":fragment[@"html"],@"text":text,@"preserveImageMarkup":@YES };
    NSArray<NSURL *> *files=[board readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    for(NSURL *file in files)if([@[@"md",@"markdown"] containsObject:file.pathExtension.lowercaseString]) { NSString *markdown=[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil];if(markdown)return @{ @"markdown":markdown,@"base":[file URLByDeletingLastPathComponent].absoluteString }; }
    NSString *html=[board stringForType:NSPasteboardTypeHTML];
    if(!html.length) {
        NSData *rtf=[board dataForType:NSPasteboardTypeRTF];
        if(rtf) { NSAttributedString *rich=[[NSAttributedString alloc] initWithRTF:rtf documentAttributes:nil];NSData *encoded=[rich dataFromRange:NSMakeRange(0,rich.length) documentAttributes:@{NSDocumentTypeDocumentAttribute:NSHTMLTextDocumentType} error:nil];if(encoded)html=[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]; }
    }
    if(html.length) {
        NSRange start=[html rangeOfString:@"<!--StartFragment-->" options:NSCaseInsensitiveSearch],end=[html rangeOfString:@"<!--EndFragment-->" options:NSCaseInsensitiveSearch];
        if(start.location!=NSNotFound&&end.location>NSMaxRange(start))html=[html substringWithRange:NSMakeRange(NSMaxRange(start),end.location-NSMaxRange(start))];
        return @{ @"html":html,@"text":text,@"preserveImageMarkup":@(internal!=nil) };
    }
    for(NSURL *file in files)if([@[@"png",@"jpg",@"jpeg",@"gif",@"bmp",@"webp",@"svg",@"tif",@"tiff",@"heic"] containsObject:file.pathExtension.lowercaseString])return @{ @"image":file.absoluteString };
    NSString *image=[self pasteboardImage:board];return image?@{ @"image":image }:@{ @"text":text };
}
+ (NSString *)youTubeIDForURL:(NSURL *)url {
    if(!SINWebURL(url))return nil;NSString *host=url.host.lowercaseString,*value=@"";NSArray *parts=[[url.path componentsSeparatedByString:@"/"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if([@[@"youtu.be",@"www.youtu.be"] containsObject:host])value=parts.firstObject?:@"";
    else if([@[@"youtube.com",@"www.youtube.com",@"m.youtube.com",@"youtube-nocookie.com",@"www.youtube-nocookie.com"] containsObject:host]) {
        if(parts.count>1&&[@[@"shorts",@"embed",@"live"] containsObject:parts[0]])value=parts[1];
        else for(NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)if([item.name isEqual:@"v"]) {value=item.value;break;}
    }
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_-]{11}$" options:0 error:nil];
    return value&&[pattern numberOfMatchesInString:value options:0 range:NSMakeRange(0,value.length)]?value:nil;
}
+ (NSString *)thumbnail:(NSData *)data {
    if(!data)return nil;CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);if(!source)return nil;
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@640,(id)kCGImageSourceCreateThumbnailWithTransform:@YES});CFRelease(source);if(!image)return nil;
    NSMutableData *png=[NSMutableData data];CGImageDestinationRef output=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png,CFSTR("public.png"),1,NULL);CGImageDestinationAddImage(output,image,NULL);BOOL ok=CGImageDestinationFinalize(output);CFRelease(output);CGImageRelease(image);return ok?SINDataURL(png,@"image/png"):nil;
}
+ (NSString *)decodeEntities:(NSString *)text {
    NSMutableString *result=[text mutableCopy];NSDictionary *entities=@{@"&quot;":@"\"",@"&#39;":@"'",@"&apos;":@"'",@"&lt;":@"<",@"&gt;":@">",@"&amp;":@"&"};
    for(NSString *key in entities)[result replaceOccurrencesOfString:key withString:entities[key] options:0 range:NSMakeRange(0,result.length)];
    NSRegularExpression *numeric=[NSRegularExpression regularExpressionWithPattern:@"&#(x[0-9a-fA-F]+|[0-9]+);" options:0 error:nil];
    for(NSTextCheckingResult *match in [[numeric matchesInString:result options:0 range:NSMakeRange(0,result.length)] reverseObjectEnumerator]) { NSString *number=[result substringWithRange:[match rangeAtIndex:1]];unsigned int point=0; if([number hasPrefix:@"x"])[[NSScanner scannerWithString:[number substringFromIndex:1]] scanHexInt:&point];else point=number.intValue; if(point>0&&point<=0x10ffff&&!(point>=0xd800&&point<=0xdfff)) { UTF32Char scalar=point;NSString *value=[[NSString alloc] initWithBytes:&scalar length:sizeof(scalar) encoding:NSUTF32LittleEndianStringEncoding];if(value)[result replaceCharactersInRange:match.range withString:value]; } }
    return result;
}
+ (NSDictionary *)metadata:(NSString *)html url:(NSURL *)url {
    NSString *title=@"",*image=@"",*fallback=@"";
    NSRegularExpression *tags=[NSRegularExpression regularExpressionWithPattern:@"<(?:meta|link)\\b[^>]*>" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *attributes=[NSRegularExpression regularExpressionWithPattern:@"([\\w:-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))" options:0 error:nil];
    for(NSTextCheckingResult *tag in [tags matchesInString:html options:0 range:NSMakeRange(0,html.length)]) {
        NSString *text=[html substringWithRange:tag.range];NSMutableDictionary *values=[NSMutableDictionary dictionary];
        for(NSTextCheckingResult *attr in [attributes matchesInString:text options:0 range:NSMakeRange(0,text.length)]) { NSString *key=[[text substringWithRange:[attr rangeAtIndex:1]] lowercaseString];for(NSUInteger i=2;i<=4;i++)if([attr rangeAtIndex:i].location!=NSNotFound){values[key]=[self decodeEntities:[text substringWithRange:[attr rangeAtIndex:i]]];break;} }
        NSString *name=[(values[@"property"]?:values[@"name"]?:@"") lowercaseString],*value=values[@"content"]?:@"";
        if([name isEqual:@"og:title"]&&!title.length)title=value;
        if([@[@"og:image",@"og:image:url",@"og:image:secure_url"] containsObject:name]&&!image.length)image=value;
        if([@[@"twitter:image",@"twitter:image:src"] containsObject:name]&&!fallback.length)fallback=value;
        if([SINString(values[@"rel"]).lowercaseString isEqual:@"image_src"]&&!fallback.length)fallback=values[@"href"]?:@"";
    }
    if(!title.length) { NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"<title\\b[^>]*>(.*?)</title>" options:NSRegularExpressionCaseInsensitive|NSRegularExpressionDotMatchesLineSeparators error:nil];NSTextCheckingResult *match=[pattern firstMatchInString:html options:0 range:NSMakeRange(0,html.length)];if(match)title=[[self decodeEntities:[html substringWithRange:[match rangeAtIndex:1]]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
    NSString *candidate=image.length?image:fallback;NSURL *imageURL=candidate.length?[NSURL URLWithString:candidate relativeToURL:url].absoluteURL:nil;
    return @{ @"title":title,@"image":SINWebURL(imageURL)?imageURL.absoluteString:@"" };
}
- (void)linkPreview:(NSString *)address completion:(SINServiceCompletion)completion {
    NSURL *url=[NSURL URLWithString:address];if(!SINWebURL(url)){completion(nil,nil);return;}
    void(^fetchImage)(NSString *,NSString *)=^(NSString *imageAddress,NSString *title) {
        NSURL *imageURL=[NSURL URLWithString:imageAddress];if(!SINWebURL(imageURL)){dispatch_async(dispatch_get_main_queue(),^{completion(nil,nil);});return;}
        [SINURLRead read:imageURL limit:8000000 completion:^(NSData *data,NSURLResponse *response,NSError *error) { NSString *image=[response.MIMEType hasPrefix:@"image/"]?[SINNativeServices thumbnail:data]:nil;dispatch_async(dispatch_get_main_queue(),^{completion(image?@{@"title":title,@"image":image}:nil,nil);}); }];
    };
    NSString *video=[SINNativeServices youTubeIDForURL:url];if(video){fetchImage([NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg",video],@"");return;}
    [SINURLRead read:url limit:2000000 completion:^(NSData *data,NSURLResponse *response,NSError *error) {
        if([response.MIMEType hasPrefix:@"image/"]) {NSString *image=[SINNativeServices thumbnail:data];dispatch_async(dispatch_get_main_queue(),^{completion(image?@{@"title":@"",@"image":image}:nil,nil);});return;}
        NSString *html=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;if(!html||![response.MIMEType containsString:@"html"]){dispatch_async(dispatch_get_main_queue(),^{completion(nil,nil);});return;}
        NSDictionary *metadata=[SINNativeServices metadata:html url:response.URL];fetchImage(metadata[@"image"],metadata[@"title"]);
    }];
}
- (void)youtubePreview:(NSString *)address save:(BOOL)save completion:(SINServiceCompletion)completion {
    NSString *video=[SINNativeServices youTubeIDForURL:[NSURL URLWithString:address]];if(!video){completion(nil,nil);return;}
    NSString *thumbnail=[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg",video];
    NSString *oembed=[@"https://www.youtube.com/oembed?format=json&url=" stringByAppendingString:SINEncode([@"https://www.youtube.com/watch?v=" stringByAppendingString:video])];
    [SINURLRead read:[NSURL URLWithString:oembed] limit:256000 completion:^(NSData *data,NSURLResponse *response,NSError *error) {
        id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSDictionary *metadata=[json isKindOfClass:NSDictionary.class]?json:@{};
        NSMutableDictionary *result=[@{@"id":video,@"title":SINString(metadata[@"title"]).length?metadata[@"title"]:@"YouTube video",@"author":SINString(metadata[@"author_name"]),@"image":thumbnail} mutableCopy];
        if(!save){dispatch_async(dispatch_get_main_queue(),^{completion(result,nil);});return;}
        [SINURLRead read:[NSURL URLWithString:thumbnail] limit:8000000 completion:^(NSData *bytes,NSURLResponse *reply,NSError *thumbnailError) { NSString *image=[SINNativeServices thumbnail:bytes];if(image)result[@"image"]=image;dispatch_async(dispatch_get_main_queue(),^{completion(image?result:nil,image?nil:(thumbnailError?:SINError(@"The YouTube thumbnail could not be saved. Try again, or turn off Save thumbnail.")));}); }];
    }];
}
- (NSData *)captureArguments:(NSArray<NSString *> *)arguments error:(NSError **)error {
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"SinAIPrompt-capture-%@.png",NSUUID.UUID.UUIDString]];
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/sbin/screencapture"];task.arguments=[arguments arrayByAddingObject:path];task.standardError=[NSPipe pipe];task.standardOutput=NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:error])return nil;[task waitUntilExit];NSData *data=[NSData dataWithContentsOfFile:path];[NSFileManager.defaultManager removeItemAtPath:path error:nil];
    if(!data.length&&task.terminationStatus!=0) {
        NSString *detail=[[[NSString alloc] initWithData:[[(NSPipe *)task.standardError fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // Apple's interactive picker exits without a file when Escape is pressed.
        BOOL interactive=[arguments containsObject:@"-i"],cancelled=interactive&&(!detail.length||[detail.lowercaseString containsString:@"cancel"]);
        if(!cancelled&&error)*error=SINError([NSString stringWithFormat:@"Screen capture failed.%@ Enable SinAIPrompt in System Settings → Privacy & Security → Screen & System Audio Recording if macOS denied access.",detail.length?[@" " stringByAppendingString:detail]:@""]);
    }
    if(!data.length&&task.terminationStatus==0&&![arguments containsObject:@"-i"]&&error)*error=SINError(@"Screen capture did not produce an image. Check Screen Recording access in System Settings.");
    return data.length?data:nil;
}
- (void)captureRegion:(BOOL)region completion:(SINServiceCompletion)completion {
    if(self.captureActive){completion(nil,SINError(@"Finish or cancel the current screen capture first."));return;}
    NSArray<NSScreen *> *screens=NSScreen.screens;
    if(!screens.count){completion(nil,SINError(@"No displays are available to capture."));return;}
    // Region Capture matches the original one-click workflow: three seconds,
    // no cursor, and a separate image regardless of the paste preference.
    NSInteger index=0;BOOL withCursor=NO;NSTimeInterval seconds=3;
    if(!region){
        NSAlert *options=NSAlert.new;options.messageText=@"Screen Capture";
        options.informativeText=@"Regions use an undimmed frozen desktop with a pixel magnifier. Windows use the macOS window picker. Escape cancels either selection.";
        [options addButtonWithTitle:@"Capture"];[options addButtonWithTitle:@"Cancel"];
        NSView *accessory=[[NSView alloc] initWithFrame:NSMakeRect(0,0,390,116)];
        NSPopUpButton *mode=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,84,390,26)];[mode addItemsWithTitles:@[@"Select a region across displays",@"Select a window",@"Main display"]];
        for(NSUInteger i=1;i<screens.count;i++)[mode addItemWithTitle:[NSString stringWithFormat:@"Display %lu — %@",(unsigned long)i+1,screens[i].localizedName]];
        [accessory addSubview:mode];
        NSTextField *label=[NSTextField labelWithString:@"Delay (seconds)"];label.frame=NSMakeRect(0,50,150,24);[accessory addSubview:label];
        NSPopUpButton *delay=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(170,50,90,26)];[delay addItemsWithTitles:@[@"0",@"3",@"5",@"10"]];[delay selectItemWithTitle:@"3"];[accessory addSubview:delay];
        NSButton *cursor=[NSButton checkboxWithTitle:@"Include cursor (region or display)" target:nil action:NULL];cursor.frame=NSMakeRect(0,16,390,24);[accessory addSubview:cursor];
        options.accessoryView=accessory;if([options runModal]!=NSAlertFirstButtonReturn){completion(nil,nil);return;}
        index=mode.indexOfSelectedItem;withCursor=cursor.state==NSControlStateValueOn;seconds=delay.titleOfSelectedItem.doubleValue;
    }
    if(!CGPreflightScreenCaptureAccess()&&!CGRequestScreenCaptureAccess()){completion(nil,SINError(@"Allow SinAIPrompt in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app and try again."));return;}
    self.captureActive=YES;NSWindow *window=self.window;
    // A region can include this editor. Hide it for window/display capture so it
    // does not cover the target while the user arranges the desktop.
    if(index!=0)[window orderOut:nil];
    SINServiceCompletion finished=^(id data,NSError *error){self.captureActive=NO;self.captureController=nil;[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];NSString *image=data?SINDataURL(data,@"image/png"):nil;completion(image?(region?@{@"source":image,@"storage":@"separate"}:image):nil,error);};
    void(^performCapture)(void)=^{
        CGFloat top=NSMaxY(screens.firstObject.frame);NSMutableArray *frames=NSMutableArray.new;
        for(NSScreen *screen in screens)[frames addObject:@{@"frame":[NSValue valueWithRect:screen.frame]}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.18*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSError *error=nil;
            if(index==0){NSMutableArray *captures=NSMutableArray.new;
                for(NSDictionary *entry in frames){NSRect frame=[entry[@"frame"] rectValue];NSMutableArray *args=[NSMutableArray arrayWithArray:@[@"-x",@"-t",@"png",[NSString stringWithFormat:@"-R%.0f,%.0f,%.0f,%.0f",frame.origin.x,top-NSMaxY(frame),frame.size.width,frame.size.height]]];if(withCursor)[args addObject:@"-C"];
                    NSData *data=[self captureArguments:args error:&error];if(!data)break;NSBitmapImageRep *bitmap=[NSBitmapImageRep imageRepWithData:data];NSImage *image=[[NSImage alloc] initWithData:data];if(!image||!bitmap){error=SINError(@"The captured display could not be decoded.");break;}image.size=frame.size;[captures addObject:@{@"frame":entry[@"frame"],@"image":image,@"scale":@(bitmap.pixelsWide/frame.size.width)}];
                }
                dispatch_async(dispatch_get_main_queue(),^{if(error||!captures.count){finished(nil,error?:SINError(@"No displays could be captured."));return;}SINRegionPicker *picker=SINRegionPicker.new;self.captureController=picker;[picker present:captures completion:^(NSData *data,NSError *selectionError){finished(data,selectionError);}];});
            }else {NSMutableArray *args=[NSMutableArray arrayWithArray:@[@"-x",@"-t",@"png"]];
                if(index==1)[args addObjectsFromArray:@[@"-i",@"-w"]];else {NSUInteger screenIndex=(NSUInteger)index-2;NSRect frame=[frames[MIN(screenIndex,frames.count-1)][@"frame"] rectValue];[args addObject:[NSString stringWithFormat:@"-R%.0f,%.0f,%.0f,%.0f",frame.origin.x,top-NSMaxY(frame),frame.size.width,frame.size.height]];if(withCursor)[args addObject:@"-C"];}
                NSData *data=[self captureArguments:args error:&error];dispatch_async(dispatch_get_main_queue(),^{finished(data,error);});}
        });
    };
    if(seconds<=0){performCapture();return;}
    SINCaptureCountdown *countdown=SINCaptureCountdown.new;self.captureController=countdown;[countdown start:seconds completion:^(BOOL cancelled){if(cancelled)finished(nil,nil);else performCapture();}];
}

- (BOOL)handleMessage:(NSDictionary *)message completion:(SINServiceCompletion)completion {
    NSString *type=SINString(message[@"type"]);NSError *error=nil;id result=nil;
    if([@[@"save-image",@"save-image-as",@"reuse-image"] containsObject:type]) {
        NSString *path=[type isEqual:@"save-image-as"]?self.saveAsPath:self.documentPath;
        result=[SINNativeServices savePNGDataURL:SINString(message[@"data"]) documentPath:path reuseOnly:[type isEqual:@"reuse-image"] error:&error];
    } else if([type isEqual:@"read-image"]) { [self readImage:SINString(message[@"source"]) completion:completion];return YES;
    } else if([type isEqual:@"map-original-image"])result=[self mapSource:SINString(message[@"source"]) base:SINString(message[@"base"]) error:&error];
    else if([type isEqual:@"reference-image"]) {
        NSString *source=SINString(message[@"source"]);if([source hasPrefix:@"data:"]||[source hasPrefix:@"blob:"]) {
            NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"Choose the Original Image";panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.allowedFileTypes=@[@"png",@"jpg",@"jpeg",@"gif",@"bmp",@"webp",@"svg",@"tiff",@"heic"];
            if([panel runModal]!=NSModalResponseOK){completion(nil,nil);return YES;}source=panel.URL.absoluteString;
        }
        NSDictionary *mapped=[self mapSource:source base:SINString(message[@"base"]) error:&error];
        NSString *reference=mapped?[self referenceSource:source base:SINString(message[@"base"]) absolute:[message[@"absolute"] boolValue] destination:nil error:&error]:nil;
        if(reference)result=@{@"reference":reference,@"display":mapped[@"display"]};
    } else if([type isEqual:@"relocate-original-image"]) {
        if(!self.saveAsPath)error=SINError(@"There is no Save As destination.");
        else { NSString *source=SINString(message[@"source"]);result=[self referenceSource:source base:SINString(message[@"base"]) absolute:[NSURL URLWithString:source].scheme.length>0 destination:self.saveAsPath error:&error]; }
    } else if([type isEqual:@"editor-copy"]) {
        NSPasteboard *board=NSPasteboard.generalPasteboard;[board clearContents];
        if(![board setString:SINString(message[@"text"]) forType:NSPasteboardTypeString]||![board setString:SINString(message[@"html"]) forType:NSPasteboardTypeHTML])error=SINError(@"The selection could not be copied. It has not been cut.");
        if([message[@"internalHtml"] isKindOfClass:NSString.class]) { NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"document":self.documentID,@"html":message[@"internalHtml"]} options:0 error:&error];if(data)[board setData:data forType:SINFragmentType]; }
    } else if([type isEqual:@"editor-paste"])result=[message[@"textOnly"] boolValue]?@{@"text":[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString]?:@""}:[self readEditorPasteboard];
    else if([type isEqual:@"copy-image"]) {
        NSData *data=SINDecode(SINString(message[@"data"]),&error);
        NSData *png=data?[SINNativeServices PNGDataFromData:data error:&error]:nil;
        if(png){NSPasteboard *board=NSPasteboard.generalPasteboard;[board clearContents];
            if(![board setData:png forType:NSPasteboardTypePNG])error=SINError(@"The image could not be copied to the clipboard.");
            else {NSImage *image=[[NSImage alloc] initWithData:png];if(image.TIFFRepresentation)[board setData:image.TIFFRepresentation forType:NSPasteboardTypeTIFF];}}
    } else if([type isEqual:@"slice-export-begin"]) {
        NSInteger count=[message[@"count"] integerValue];if(count<1||count>1089){completion(nil,SINError(@"Choose between 1 and 1089 cells."));return YES;}
        NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"Save All Slices — Choose a destination folder";panel.canChooseDirectories=YES;panel.canChooseFiles=NO;panel.canCreateDirectories=YES;
        if([panel runModal]!=NSModalResponseOK){completion(nil,nil);return YES;}
        if(!self.sliceExport)self.sliceExport=SINSliceExport.new;
        result=[self.sliceExport beginInDirectory:panel.URL.path name:SINString(message[@"name"]) count:(NSUInteger)count error:&error];
    } else if([type isEqual:@"slice-export-write"]) {
        if(!self.sliceExport){completion(nil,SINError(@"The export is no longer active."));return YES;}
        [self.sliceExport writeToken:SINString(message[@"token"]) index:[message[@"index"] unsignedIntegerValue] dataURL:SINString(message[@"data"]) completion:^(NSError *failure){completion(nil,failure);}];return YES;
    } else if([type isEqual:@"slice-export-end"]) {
        if(!self.sliceExport)error=SINError(@"The export is no longer active.");else result=[self.sliceExport endToken:SINString(message[@"token"]) error:&error];
    }
    else if([type isEqual:@"annotation-copy"]) {
        NSString *format=SINString(message[@"format"]),*content=SINString(message[@"content"]);NSPasteboard *board=NSPasteboard.generalPasteboard;
        if([format isEqual:@"svg"]) { [board clearContents];NSData *svg=[content dataUsingEncoding:NSUTF8StringEncoding];[board setData:svg forType:@"public.svg-image"];[board setData:svg forType:@"image/svg+xml"];[board setString:content forType:NSPasteboardTypeString]; }
        else if([format isEqual:@"png"]) { NSData *png=SINDecode(content,&error);if(png) { [board clearContents];[board setData:png forType:NSPasteboardTypePNG];NSImage *image=[[NSImage alloc] initWithData:png];if(image.TIFFRepresentation)[board setData:image.TIFFRepresentation forType:NSPasteboardTypeTIFF]; } }
        else error=SINError(@"Choose SVG or PNG.");
        if(!error)[board setString:SINString(message[@"objects"]) forType:SINObjectsType];
    } else if([type isEqual:@"annotation-paste"]) {
        NSPasteboard *board=NSPasteboard.generalPasteboard;NSString *objects=[board stringForType:SINObjectsType],*image=[self pasteboardImage:board];result=objects?@{@"objects":objects}:(image?@{@"image":image}:nil);
    } else if([type isEqual:@"templates-load"])result=[self readJSON:@"templates.json" fallback:@[]];
    else if([type isEqual:@"templates-save"]) {
        if(![message[@"templates"] isKindOfClass:NSArray.class])error=SINError(@"Templates must be a JSON array.");else[self writeJSON:message[@"templates"] name:@"templates.json" error:&error];
    } else if([type isEqual:@"export-template"]) {
        NSSavePanel *panel=NSSavePanel.savePanel;panel.title=@"Export Object Template";panel.nameFieldStringValue=@"Object.pmt-template.json";panel.allowedFileTypes=@[@"json"];
        if([panel runModal]==NSModalResponseOK)[SINString(message[@"contents"]) writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    } else if([type isEqual:@"recent-colors"])result=[self readJSON:@"recent-colors.json" fallback:@[]];
    else if([type isEqual:@"color-used"]) {
        NSString *value=SINString(message[@"value"]).lowercaseString;NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^#[0-9a-f]{6}$" options:0 error:nil];
        if([pattern numberOfMatchesInString:value options:0 range:NSMakeRange(0,value.length)]) { id saved=[self readJSON:@"recent-colors.json" fallback:@[]];NSMutableArray *colors=[saved isKindOfClass:NSArray.class]?[saved mutableCopy]:[NSMutableArray array];[colors removeObject:value];[colors insertObject:value atIndex:0];if(colors.count>10)[colors removeObjectsInRange:NSMakeRange(10,colors.count-10)];[self writeJSON:colors name:@"recent-colors.json" error:&error]; }
    } else if([type isEqual:@"editor-fonts"]) {
        // WebKit sees installed macOS and Office fonts; no downloads or font copies.
        result=@"@font-face{font-family:'Segoe UI';src:local('Segoe UI'),local('Helvetica Neue');} @font-face{font-family:'Consolas';src:local('Consolas'),local('Menlo');}";
    } else if([type isEqual:@"link-preview"]) { [self linkPreview:SINString(message[@"url"]) completion:completion];return YES;
    } else if([type isEqual:@"youtube-preview"]) { [self youtubePreview:SINString(message[@"url"]) save:[message[@"saveThumbnail"] boolValue] completion:completion];return YES;
    } else if([type isEqual:@"open-video"]) {
        NSString *video=SINString(message[@"video"]);NSURL *url=[NSURL URLWithString:[@"https://www.youtube.com/watch?v=" stringByAppendingString:video]];
        if(![[SINNativeServices youTubeIDForURL:url] isEqual:video])error=SINError(@"Invalid YouTube video.");else if(![NSWorkspace.sharedWorkspace openURL:url])error=SINError(@"No browser could open the video.");
    } else if([type isEqual:@"open-image"]) {
        NSData *data=SINDecode(SINString(message[@"data"]),&error);if(data) {
            NSString *folder=[self.dataDirectory stringByAppendingPathComponent:@"ExternalImages"];[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
            NSString *extension=[SINString(message[@"data"]) hasPrefix:@"data:image/svg"]?@"svg":@"png";if([extension isEqual:@"png"])data=[SINNativeServices PNGDataFromData:data error:&error];
            if(data) { NSString *path=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"image-%@.%@",SINHash(data),extension]];if([data writeToFile:path options:NSDataWritingAtomic error:&error]&&![NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]])error=SINError(@"No application could open this image."); }
        }
    } else if([type isEqual:@"screen-capture"]||[type isEqual:@"region-capture"]) { [self captureRegion:[type isEqual:@"region-capture"] completion:completion];return YES;
    } else return NO;
    completion(result,error);return YES;
}
@end
