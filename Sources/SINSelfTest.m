#import "SINWindowController.h"

static NSArray<NSDictionary<NSPasteboardType, NSData *> *> *SINCopyPasteboard(void) {
    NSMutableArray *items=NSMutableArray.new;
    for(NSPasteboardItem *item in NSPasteboard.generalPasteboard.pasteboardItems){
        NSMutableDictionary *types=NSMutableDictionary.new;
        for(NSPasteboardType type in item.types){NSData *data=[item dataForType:type];if(data)types[type]=data;}
        [items addObject:types];
    }
    return items;
}

static void SINRestorePasteboard(NSArray<NSDictionary<NSPasteboardType, NSData *> *> *saved) {
    NSPasteboard *board=NSPasteboard.generalPasteboard;
    [board clearContents];
    NSMutableArray *items=NSMutableArray.new;
    for(NSDictionary *types in saved){
        NSPasteboardItem *item=NSPasteboardItem.new;
        for(NSPasteboardType type in types)[item setData:types[type] forType:type];
        [items addObject:item];
    }
    if(items.count)[board writeObjects:items];
}

@implementation SINWindowController (SelfTest)
- (void)runSelfTests {
    NSArray *pasteboard=SINCopyPasteboard();
    NSDate *started=NSDate.date;
    NSString *root=NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    NSString *resultPath=[root stringByAppendingPathComponent:@"Tests/last-web-results.json"];
    NSString *snapshotPath=[root stringByAppendingPathComponent:@"build/self-test.png"];
    __block BOOL finished=NO;
    __block BOOL running=NO;
    void (^finish)(id,NSError *)=^(id checks,NSError *error){
        if(finished)return;
        finished=YES;
        SINRestorePasteboard(pasteboard);
        NSMutableDictionary *result=[@{@"passed":error?@NO:@YES,@"elapsedSeconds":@(-started.timeIntervalSinceNow),@"checks":[checks isKindOfClass:NSArray.class]?checks:@[],@"count":@([checks isKindOfClass:NSArray.class]?[checks count]:0)} mutableCopy];
        if(error)result[@"error"]=error.localizedDescription;
        self.testResult=result;
        [self.editor.webView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image,NSError *snapshotError){
            if(image){
                NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
                NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSError *writeError=nil;
                if([png writeToFile:snapshotPath options:NSDataWritingAtomic error:&writeError])result[@"snapshot"]=snapshotPath;
                else result[@"snapshotError"]=writeError.localizedDescription?:@"Unable to encode snapshot";
            }else if(snapshotError)result[@"snapshotError"]=snapshotError.localizedDescription;
            NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
            [NSFileManager.defaultManager createDirectoryAtPath:resultPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [json writeToFile:resultPath atomically:YES];
            fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);fflush(stdout);
            exit(error?1:0);
        }];
    };
    void (^run)(void)=^{
        if(running||finished)return;running=YES;
        NSString *sample=@"<!doctype html><html><head><title>Sin — AI Prompt for Mac</title></head><body><h1>Sin — AI Prompt for Mac</h1><p>Objective-C · AppKit · WebKit</p><h2>One document. Every idea.</h2><p>Write and format prompts, annotate images, reuse object templates, and keep your HTML portable.</p><ul><li><strong>Rich text</strong>, Markdown, and highlighted source blocks</li><li>Native clipboard and image capture</li><li>Search, replace, document outline, and local files</li></ul><blockquote>Built with the tools already on this Mac.</blockquote><p><span style=\"background-color:#fff2a6\">No npm. No third-party libraries.</span></p></body></html>";
        NSString *script=[NSString stringWithFormat:@"await window.editor.ready();await window.editor.load(%@);await window.editor.ready();return await (await import('./mac-self-test.js')).run();",SINJSON(sample)];
        [self.editor asyncScript:script completion:^(id checks,NSError *error){
            if(error){
                [self.editor evaluate:@"window.sinTestResults||[]" completion:^(id partial,NSError *readError){finish(partial,error);}];
                return;
            }
            [self runNativeShellChecks:^(NSArray<NSString *> *nativeChecks,NSError *nativeError){
                NSMutableArray *all=[checks mutableCopy]?:NSMutableArray.new;
                [all addObjectsFromArray:nativeChecks?:@[]];finish(all,nativeError);
            }];
        }];
    };
    void (^previousReady)(void)=self.editor.readyHandler;
    self.editor.readyHandler=^{if(previousReady)previousReady();run();};
    if(self.editor.ready)run();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(!running&&!finished)finish(nil,[NSError errorWithDomain:@"SinSelfTest" code:1 userInfo:@{NSLocalizedDescriptionKey:@"WKWebView did not report editor ready within 45 seconds. Check startup-error output."}]);
    });
}
@end
