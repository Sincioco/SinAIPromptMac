#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Snapshots contain immutable dictionaries/arrays and immutable document strings.
// One worker publishes the newest queued snapshot; explicit saves are barriers.
@interface SINRecoveryWriter : NSObject
- (instancetype)initWithDirectory:(NSString *)directory;
- (void)enqueueSnapshot:(NSDictionary *)snapshot completion:(void (^)(NSError *_Nullable))completion;
- (BOOL)saveSnapshot:(NSDictionary *)snapshot error:(NSError **)error;
- (void)waitUntilIdle;
- (void)invalidateAfterPendingWrites;
@end
FOUNDATION_EXPORT id SINDetachedJSON(id object);
NS_ASSUME_NONNULL_END
