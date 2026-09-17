#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
@class SINDocument, SINNativeServices;
NS_ASSUME_NONNULL_BEGIN
NSString *SINJSON(id _Nullable object);
@interface SINEditor : NSViewController <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, WKURLSchemeHandler, NSTextViewDelegate>
@property(nonatomic,strong) SINDocument *document;
@property(nonatomic,strong,nullable) WKWebView *webView;
@property(nonatomic,strong) NSTextView *sourceView;
@property(nonatomic,strong) SINNativeServices *services;
@property(nonatomic,copy) void (^changed)(void);
@property(nonatomic,copy) void (^command)(NSString *command);
@property(nonatomic,copy) void (^nativeMessage)(NSDictionary *message, void (^reply)(id _Nullable, NSError *_Nullable));
@property(nonatomic,copy) void (^annotationMode)(BOOL open);
@property(nonatomic,copy) void (^readyHandler)(void);
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) BOOL showingSource;
@property(nonatomic,copy) NSDictionary *preferences;
- (instancetype)initWithDocument:(SINDocument *)document dataDirectory:(NSString *)directory;
- (void)flush:(void (^)(void))completion;
- (void)showSource:(BOOL)source completion:(void (^_Nullable)(void))completion;
- (void)reload;
- (void)applyPreferences;
- (void)evaluate:(NSString *)script completion:(void (^_Nullable)(id _Nullable, NSError *_Nullable))completion;
- (void)asyncScript:(NSString *)script completion:(void (^)(id _Nullable, NSError *_Nullable))completion;
- (void)editCommand:(NSString *)command value:(id _Nullable)value;
- (void)exportKind:(NSString *)kind completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion;
- (void)showFind:(BOOL)replace;
- (void)findNext:(BOOL)backward;
- (void)focusEditor;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
