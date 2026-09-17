#import "SINEditor.h"
#import "SINDocument.h"
#import "SINNativeServices.h"
#import "SINSearchPanel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
NSString *SINJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: NSNull.null options:NSJSONWritingFragmentsAllowed error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"null";
}
static NSError *EditorError(NSString *message) { return [NSError errorWithDomain:@"SinEditor" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
@interface SINSourceRuler : NSRulerView
@property(nonatomic,weak) NSTextView *textView;
@end
@implementation SINSourceRuler
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill]; NSRectFill(rect);
    NSTextView *text = self.textView; if (!text) return;
    NSLayoutManager *layout = text.layoutManager;
    NSRange visible = [layout glyphRangeForBoundingRect:text.visibleRect inTextContainer:text.textContainer];
    NSRange characters = [layout characterRangeForGlyphRange:visible actualGlyphRange:NULL];
    NSString *content = text.string; NSUInteger line = 1;
    for (NSUInteger i=0;i<MIN(characters.location,content.length);i++) if ([content characterAtIndex:i]=='\n') line++;
    NSUInteger index = [content lineRangeForRange:NSMakeRange(MIN(characters.location,content.length),0)].location;
    NSDictionary *attributes = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.secondaryLabelColor};
    while(index < content.length && index <= NSMaxRange(characters)) {
        NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:index];
        NSRect lineRect = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        CGFloat y = lineRect.origin.y + text.textContainerInset.height - text.visibleRect.origin.y;
        [[NSString stringWithFormat:@"%lu",(unsigned long)line] drawAtPoint:NSMakePoint(6,y) withAttributes:attributes];
        NSUInteger next=NSMaxRange([content lineRangeForRange:NSMakeRange(index,0)]); if(next<=index) break; index=next; line++;
    }
}
@end
@interface SINEditor ()
@property(nonatomic,strong) NSScrollView *sourceScroll;
@property(nonatomic,strong) NSButton *visualButton;
@property(nonatomic,strong) NSMutableDictionary<NSString*,void (^)(id,NSError*)> *pending;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL showingSource;
@property(nonatomic) BOOL receiving;
@property(nonatomic) CGFloat measuredRibbonHeight;
@property(nonatomic) CGFloat navigationWidth;
@property(nonatomic) CGFloat appliedNavigationInset;
@property(nonatomic) BOOL modalOverlay;
@property(nonatomic,copy) NSArray<NSDictionary *> *popupRects;
@property(nonatomic,copy) NSString *baselineHTML;
@property(nonatomic,copy) NSString *loadedRaw;
@property(nonatomic) BOOL invalidated;
@property(nonatomic,strong) NSMutableArray<void (^)(void)> *whenReady;
@property(nonatomic,strong) SINSearchPanel *searchPanel;
@end
@implementation SINEditor
- (instancetype)initWithDocument:(SINDocument *)document dataDirectory:(NSString *)directory {
    if ((self=[super initWithNibName:nil bundle:nil])) {
        _appliedNavigationInset=-1; _document=document; _pending=NSMutableDictionary.new; _whenReady=NSMutableArray.new;
        _services=[[SINNativeServices alloc] initWithDataDirectory:directory];
        _services.documentID=document.identifier;
    } return self;
}
- (void)loadView {
    self.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1000,700)];
    WKWebViewConfiguration *configuration=WKWebViewConfiguration.new;
    configuration.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    [configuration setURLSchemeHandler:self forURLScheme:@"sin-asset"];
    [configuration.userContentController addScriptMessageHandler:self name:@"sinNative"];
    configuration.preferences.javaScriptCanOpenWindowsAutomatically=NO;
    configuration.preferences.elementFullscreenEnabled=YES;
    configuration.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAll;
    self.webView=[[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.webView.navigationDelegate=self; self.webView.UIDelegate=self;
    self.webView.inspectable=YES;
    [self.view addSubview:self.webView];
    self.sourceScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,1000,664)];
    self.sourceScroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.sourceScroll.hasVerticalScroller=YES; self.sourceScroll.hasHorizontalScroller=YES;
    self.sourceView=[[NSTextView alloc] initWithFrame:self.sourceScroll.bounds];
    self.sourceView.richText=NO; self.sourceView.usesFindBar=YES; self.sourceView.incrementalSearchingEnabled=YES;
    self.sourceView.allowsUndo=YES; self.sourceView.automaticQuoteSubstitutionEnabled=NO;
    self.sourceView.automaticDashSubstitutionEnabled=NO; self.sourceView.automaticTextReplacementEnabled=NO;
    self.sourceView.font=[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    self.sourceView.textContainerInset=NSMakeSize(14,14); self.sourceView.delegate=self;
    self.sourceView.autoresizingMask=NSViewWidthSizable; self.sourceView.verticallyResizable=YES;
    self.sourceView.minSize=NSMakeSize(0,664); self.sourceView.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
    self.sourceScroll.documentView=self.sourceView;
    SINSourceRuler *ruler=[[SINSourceRuler alloc] initWithScrollView:self.sourceScroll orientation:NSVerticalRuler];
    ruler.textView=self.sourceView; ruler.ruleThickness=48;
    self.sourceScroll.verticalRulerView=ruler; self.sourceScroll.hasVerticalRuler=YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sourceScrolled:) name:NSViewBoundsDidChangeNotification object:self.sourceScroll.contentView];
    self.sourceScroll.contentView.postsBoundsChangedNotifications=YES;
    self.sourceScroll.hidden=YES; [self.view addSubview:self.sourceScroll];
    self.visualButton=[NSButton buttonWithTitle:@"← Visual editor    ·    HTML source" target:self action:@selector(backToVisual:)];
    self.visualButton.frame=NSMakeRect(10,668,300,28); self.visualButton.autoresizingMask=NSViewMinYMargin;
    self.visualButton.bordered=NO; self.visualButton.hidden=YES; [self.view addSubview:self.visualButton];
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"sin-asset://app/index.html"]]];
}
- (CGFloat)ribbonHeight { return self.showingSource || [self.preferences[@"showToolbar"] isEqual:@NO] ? 0 : self.measuredRibbonHeight*self.webView.pageZoom; }
- (NSArray<NSValue *> *)overlayRects {
    NSMutableArray *rects=NSMutableArray.new;CGFloat scale=self.webView.pageZoom;
    for(NSDictionary *rect in self.popupRects){CGFloat x=[rect[@"x"] doubleValue]*scale,y=[rect[@"y"] doubleValue]*scale,w=[rect[@"width"] doubleValue]*scale,h=[rect[@"height"] doubleValue]*scale;
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x,self.webView.isFlipped?y:self.webView.bounds.size.height-y-h,w,h)]];}
    return rects;
}
- (void)setNavigationWidth:(CGFloat)width {
    _navigationWidth=MAX(0,width);NSRect bounds=self.view.bounds;
    self.sourceScroll.frame=NSMakeRect(_navigationWidth,0,MAX(0,bounds.size.width-_navigationWidth),MAX(0,bounds.size.height-36));
    self.visualButton.frame=NSMakeRect(_navigationWidth+10,MAX(0,bounds.size.height-32),300,28);
    CGFloat inset=_navigationWidth/MAX(.1,self.webView.pageZoom);
    if(self.ready && fabs(inset-self.appliedNavigationInset)>.01){self.appliedNavigationInset=inset;[self evaluate:[NSString stringWithFormat:@"window.editor.setNavigationInset(%.4f);void 0",inset] completion:nil];}
}
- (void)viewDidLayout { [super viewDidLayout]; [self setNavigationWidth:self.navigationWidth]; }
- (void)sourceScrolled:(NSNotification *)note { [self.sourceScroll.verticalRulerView setNeedsDisplay:YES]; }
- (void)backToVisual:(id)sender { [self showSource:NO completion:nil]; }
- (void)syncServices { self.services.documentPath=self.document.path; self.services.documentID=self.document.identifier; self.services.window=self.view.window; }
- (void)evaluate:(NSString *)script completion:(void (^)(id,NSError*))completion {
    [self.webView evaluateJavaScript:script completionHandler:^(id result,NSError *error){ if(completion) completion(result,error); }];
}
- (void)asyncScript:(NSString *)script completion:(void (^)(id,NSError*))completion {
    NSString *identifier=NSUUID.UUID.UUIDString; self.pending[identifier]=[completion copy];
    NSString *js=[NSString stringWithFormat:@"Promise.resolve().then(async()=>{%@}).then(result=>window.webkit.messageHandlers.sinNative.postMessage({type:'async-result',id:%@,result:result??null})).catch(error=>window.webkit.messageHandlers.sinNative.postMessage({type:'async-result',id:%@,error:String(error.stack||error)}));void 0;",script,SINJSON(identifier),SINJSON(identifier)];
    [self evaluate:js completion:^(id value,NSError *error){if(error){void(^reply)(id,NSError*)=self.pending[identifier];[self.pending removeObjectForKey:identifier];if(reply)reply(nil,error);}}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        void(^reply)(id,NSError*)=self.pending[identifier]; if(reply){[self.pending removeObjectForKey:identifier];reply(nil,EditorError(@"The editor operation timed out."));}
    });
}
- (void)afterReady:(void (^)(void))block { (void)self.view; if(self.ready)block();else [self.whenReady addObject:[block copy]]; }
- (void)reload {
    [self syncServices];
    [self afterReady:^{NSString *raw=self.document.text;[self asyncScript:[NSString stringWithFormat:@"await window.editor.load(%@,'sin-asset://document/');return window.editor.html(true);",SINJSON(raw)] completion:^(id result,NSError *error){
        if([result isKindOfClass:NSString.class]){self.baselineHTML=result;self.loadedRaw=raw;}
        if(error)NSLog(@"Editor load: %@",error.localizedDescription); [self applyPreferences];
        [self evaluate:[NSString stringWithFormat:@"window.editor.restoreView(%@);void 0",SINJSON(@{@"selectionStart":@(self.document.selection.location),@"selectionLength":@(self.document.selection.length),@"scroll":@(self.document.scroll)})] completion:nil];
    }];}];
}
- (void)flush:(void (^)(void))completion {
    if(self.showingSource) { self.document.text=self.sourceView.string;self.document.selection=self.sourceView.selectedRange;self.document.scroll=self.sourceScroll.contentView.bounds.origin.y; completion(); return; }
    [self afterReady:^{[self evaluate:@"({html:window.editor.html(true),view:window.editor.captureView()})" completion:^(id result,NSError *error){if([result isKindOfClass:NSDictionary.class]){NSString *html=result[@"html"];self.document.text=[html isEqual:self.baselineHTML]?self.loadedRaw:(html?:self.document.text);NSDictionary *view=result[@"view"];self.document.selection=NSMakeRange([view[@"selectionStart"] unsignedIntegerValue],[view[@"selectionLength"] unsignedIntegerValue]);self.document.scroll=[view[@"scroll"] doubleValue];}completion();}];}];
}
- (void)showSource:(BOOL)source completion:(void (^)(void))completion {
    if(source==self.showingSource){if(completion)completion();return;}
    [self flush:^{
        self.showingSource=source; self.sourceScroll.hidden=!source; self.visualButton.hidden=!source; self.webView.hidden=source;
        if(source){self.receiving=YES;self.sourceView.string=self.document.text;self.receiving=NO;[self evaluate:@"window.editor.stopMedia()" completion:nil];}
        else [self reload];
        if(self.chromeChanged)self.chromeChanged();[self focusEditor];if(completion)completion();
    }];
}
- (void)applyPreferences {
    if(!self.isViewLoaded)return;
    NSDictionary *p=self.preferences?:@{};
    self.sourceView.editable=!self.document.readOnly;
    self.sourceScroll.rulersVisible=[p[@"lineNumbers"] boolValue];
    BOOL wrap=p[@"wordWrap"]?[p[@"wordWrap"] boolValue]:YES;
    self.sourceView.horizontallyResizable=!wrap;
    self.sourceView.textContainer.widthTracksTextView=wrap;
    self.sourceView.textContainer.containerSize=NSMakeSize(wrap?MAX(100,self.sourceScroll.contentSize.width):CGFLOAT_MAX,CGFLOAT_MAX);
    self.sourceView.font=[NSFont monospacedSystemFontOfSize:13*self.document.zoom/100.0 weight:NSFontWeightRegular];
    self.webView.pageZoom=self.document.zoom/100.0;
    [self setNavigationWidth:self.navigationWidth];if(self.chromeChanged)self.chromeChanged();
    if(!self.ready)return;
    [self evaluate:[NSString stringWithFormat:@"document.documentElement.dataset.theme=%@;document.querySelector('#toolbar').hidden=%@;window.editor.setToolbarWrap(%@);window.editor.setImageStorage(%@);window.editor.setReadOnly(%@)",SINJSON([p[@"theme"] lowercaseString]?:@"system"),[p[@"showToolbar"] isEqual:@NO]?@"true":@"false",[p[@"wrapToolbar"] isEqual:@NO]?@"false":@"true",SINJSON(p[@"imageStorage"]?:@""),self.document.readOnly?@"true":@"false"] completion:nil];
}
- (void)textDidChange:(NSNotification *)notification { if(self.receiving)return; self.document.text=self.sourceView.string; [self.sourceScroll.verticalRulerView setNeedsDisplay:YES]; if(self.changed)self.changed(); }
- (void)textViewDidChangeSelection:(NSNotification *)notification { if(self.changed)self.changed(); }
- (void)focusEditor { if(self.showingSource)[self.view.window makeFirstResponder:self.sourceView];else {[self.view.window makeFirstResponder:self.webView];if(self.ready)[self evaluate:@"window.editor.focus()" completion:nil];} }
- (void)editCommand:(NSString *)command value:(id)value {
    if(self.document.readOnly&&![@[@"copy",@"selectAll"] containsObject:command])return;
    if(self.showingSource){
        NSDictionary *selectors=@{@"undo":@"undo:",@"redo":@"redo:",@"cut":@"cut:",@"copy":@"copy:",@"paste":@"paste:",@"selectAll":@"selectAll:",@"delete":@"delete:"};
        if([command isEqual:@"insertText"]||[command isEqual:@"insertHTML"]){[self.sourceView insertText:value?:@"" replacementRange:self.sourceView.selectedRange];return;}
        if(selectors[command]){[NSApp sendAction:NSSelectorFromString(selectors[command]) to:nil from:self];return;}
    }
    [self evaluate:[NSString stringWithFormat:@"window.editor.command(%@,%@);void 0",SINJSON(command),SINJSON(value)] completion:nil];
}
- (void)showFind:(BOOL)replace {
    if(!self.searchPanel)self.searchPanel=[[SINSearchPanel alloc] initWithEditor:self];
    [self.searchPanel showForWindow:self.view.window replace:replace];
}
- (void)findNext:(BOOL)backward {if(!self.searchPanel)[self showFind:NO];else [self.searchPanel findNext:backward];}
- (void)pollExport:(NSString *)key attempts:(NSUInteger)attempts completion:(void (^)(NSString*,NSError*))completion {
    [self evaluate:[NSString stringWithFormat:@"window.editor.exportResult(%@)",SINJSON(key)] completion:^(id result,NSError *error){
        if(error){completion(nil,error);return;}
        if([result isKindOfClass:NSDictionary.class]){completion(result[@"html"],result[@"error"]?EditorError(result[@"error"]):nil);return;}
        if(attempts==0){completion(nil,EditorError(@"Export timed out while reading image assets."));return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self pollExport:key attempts:attempts-1 completion:completion];});
    }];
}
- (void)exportKind:(NSString *)kind completion:(void (^)(NSString*,NSError*))completion {
    [self flush:^{
        [self syncServices];
        NSString *begin=[kind isEqual:@"relocate"]?@"window.editor.beginRelocate()":([kind isEqual:@"markdown"]?@"window.editor.beginMarkdown()":([kind isEqual:@"duplicate"]?@"window.editor.beginPortable(true)":@"window.editor.beginPortable()"));
        void(^start)(void)=^{[self evaluate:begin completion:^(id key,NSError *error){if(error||![key isKindOfClass:NSString.class])completion(nil,error?:EditorError(@"Could not begin export."));else [self pollExport:key attempts:1200 completion:completion];}];};
        if(self.showingSource)[self asyncScript:[NSString stringWithFormat:@"await window.editor.load(%@,'sin-asset://document/');",SINJSON(self.document.text)] completion:^(id r,NSError *e){if(e)completion(nil,e);else start();}];else start();
    }];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if(!message.frameInfo.isMainFrame||![message.frameInfo.request.URL.host isEqual:@"app"]||![message.body isKindOfClass:NSDictionary.class])return;
    NSDictionary *body=message.body;NSString *type=body[@"type"],*identifier=body[@"id"];
    if([type isEqual:@"async-result"]){void(^reply)(id,NSError*)=self.pending[identifier];[self.pending removeObjectForKey:identifier];if(reply)reply(body[@"result"],body[@"error"]?EditorError(body[@"error"]):nil);return;}
    void(^reply)(id,NSError*)=^(id result,NSError *error){if(!identifier)return;[self evaluate:[NSString stringWithFormat:@"window.sinNativeReply(%@)",SINJSON(error?@{@"id":identifier,@"error":error.localizedDescription}:@{@"id":identifier,@"result":result?:NSNull.null})] completion:nil];};
    if([type isEqual:@"ready"]){self.ready=YES;[self reload];NSArray *blocks=self.whenReady.copy;[self.whenReady removeAllObjects];for(void(^block)(void) in blocks)block();if(self.readyHandler)self.readyHandler();return;}
    if([type isEqual:@"startup-error"]){NSLog(@"Editor JavaScript error: %@",body);return;}
    if([type isEqual:@"change"]){if(!self.document.readOnly && !self.showingSource){NSString *html=body[@"html"]?:@"";self.document.text=[html isEqual:self.baselineHTML]?self.loadedRaw:html;if(self.changed)self.changed();}return;}
    if([type isEqual:@"command"]){if(body[@"html"]&&!self.document.readOnly)self.document.text=[body[@"html"] isEqual:self.baselineHTML]?self.loadedRaw:body[@"html"];if(self.command)self.command(body[@"command"]);return;}
    if([type isEqual:@"source"]){[self showSource:YES completion:nil];return;}
    if([type isEqual:@"annotation-mode"]){if(self.annotationMode)self.annotationMode([body[@"open"] boolValue]);reply(nil,nil);return;}
    if([type isEqual:@"ribbon-height"]){self.measuredRibbonHeight=MAX(0,[body[@"height"] doubleValue]);if(self.chromeChanged)self.chromeChanged();reply(nil,nil);return;}
    if([type isEqual:@"chrome-overlay"]){self.modalOverlay=[body[@"modal"] boolValue];self.popupRects=[body[@"rects"] isKindOfClass:NSArray.class]?body[@"rects"]:@[];if(self.chromeChanged)self.chromeChanged();reply(nil,nil);return;}
    if([@[@"image-status",@"painted"] containsObject:type]){reply(nil,nil);return;}
    [self syncServices];
    // File-changing requests are mediated by the document shell before native services.
    if(self.nativeMessage) self.nativeMessage(body,reply);
    else if(![self.services handleMessage:body completion:reply])reply(nil,EditorError([@"Unsupported command: " stringByAppendingString:type?:@"unknown"]));
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *url=action.request.URL;
    if(!action.targetFrame.isMainFrame){
        BOOL document=[url.absoluteString isEqual:@"about:srcdoc"]||[url.absoluteString isEqual:@"about:blank"];
        BOOL player=[url.scheme isEqual:@"https"]&&[@[@"www.youtube.com",@"www.youtube-nocookie.com"] containsObject:url.host]&&[url.path hasPrefix:@"/embed/"];
        handler(document||player?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);return;
    }
    BOOL internal=[url.scheme isEqual:@"sin-asset"]&&[url.host isEqual:@"app"];
    handler(internal?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL*>*))completion {
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.allowsMultipleSelection=parameters.allowsMultipleSelection;panel.canChooseDirectories=parameters.allowsDirectories;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result){completion(result==NSModalResponseOK?panel.URLs:nil);}];
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {
    NSAlert *alert=NSAlert.new;alert.messageText=@"Sin — AI Prompt";alert.informativeText=message;[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r){completion();}];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completion {
    NSAlert *alert=NSAlert.new;alert.messageText=message;[alert addButtonWithTitle:@"OK"];[alert addButtonWithTitle:@"Cancel"];[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r){completion(r==NSAlertFirstButtonReturn);}];
}
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSURL *url=task.request.URL;NSString *path=nil;
    if([url.host isEqual:@"app"]){NSString *root=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Web"];path=[[root stringByAppendingPathComponent:url.path] stringByStandardizingPath];if(![path hasPrefix:[root stringByAppendingString:@"/"]])path=nil;}
    else if([url.host isEqual:@"document"]){NSString *folder=self.document.path.stringByDeletingLastPathComponent?:self.services.dataDirectory;path=[[folder stringByAppendingPathComponent:url.path] stringByStandardizingPath];}
    else if([url.host isEqual:@"original"])path=[self.services localPathForSource:url.absoluteString base:nil error:nil];
    NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
    if(!data){[task didFailWithError:EditorError([NSString stringWithFormat:@"Could not read local asset: %@",url.absoluteString])];return;}
    NSString *extension=path.pathExtension.lowercaseString;
    NSDictionary *types=@{@"js":@"text/javascript",@"css":@"text/css",@"html":@"text/html",@"htm":@"text/html",@"json":@"application/json",@"svg":@"image/svg+xml"};
    NSString *mime=types[extension]?:[UTType typeWithFilenameExtension:extension].preferredMIMEType?:@"application/octet-stream";
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":[mime stringByAppendingString:@"; charset=utf-8"],@"Access-Control-Allow-Origin":@"*",@"Cache-Control":@"no-store"}];
    [task didReceiveResponse:response];[task didReceiveData:data];[task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {self.ready=NO;[webView reload];}
- (void)invalidate {if(self.invalidated)return;self.invalidated=YES;[self.searchPanel invalidate];self.searchPanel=nil;[self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"sinNative"];[NSNotificationCenter.defaultCenter removeObserver:self];[self.webView stopLoading];[self.webView removeFromSuperview];self.webView.navigationDelegate=nil;self.webView.UIDelegate=nil;self.webView=nil;}
@end
