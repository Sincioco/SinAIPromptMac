#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// One editor owns one export. The native folder picker supplies the parent;
// browser messages may supply only a token and the next cell, never a path.
@interface SINSliceExport : NSObject
- (nullable NSString *)beginInDirectory:(NSString *)parent name:(NSString *)name count:(NSUInteger)count error:(NSError **)error;
- (void)writeToken:(NSString *)token index:(NSUInteger)index dataURL:(NSString *)data completion:(void (^)(NSError *_Nullable))completion;
- (nullable NSDictionary *)endToken:(NSString *)token error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
