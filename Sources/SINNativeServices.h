#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SINServiceCompletion)(id _Nullable result, NSError * _Nullable error);

/// Native image storage, clipboard, screen capture and optional URL metadata.
/// Call the bridge entry point on the main queue. Completions run on that queue.
@interface SINNativeServices : NSObject
@property(nonatomic, copy, nullable) NSString *documentPath;
@property(nonatomic, copy, nullable) NSString *saveAsPath;
@property(nonatomic, copy) NSString *documentID;
@property(nonatomic, weak, nullable) NSWindow *window;
@property(nonatomic, readonly, copy) NSString *dataDirectory;
- (instancetype)initWithDataDirectory:(NSString *)directory;
- (BOOL)handleMessage:(NSDictionary *)message completion:(SINServiceCompletion)completion;
/// Resolve local source URLs, including the sin-asset custom scheme.
- (nullable NSString *)localPathForSource:(NSString *)source base:(nullable NSString *)base error:(NSError **)error;
+ (nullable NSData *)PNGDataFromData:(NSData *)data error:(NSError **)error;
+ (nullable NSString *)savePNGDataURL:(NSString *)dataURL documentPath:(NSString *)documentPath reuseOnly:(BOOL)reuseOnly error:(NSError **)error;
+ (nullable NSString *)youTubeIDForURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
