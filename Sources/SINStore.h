#import <Foundation/Foundation.h>
#import "SINDocument.h"

NS_ASSUME_NONNULL_BEGIN
@interface SINStore : NSObject
@property(nonatomic, copy, readonly) NSString *directory;
@property(nonatomic, strong) NSMutableDictionary *settings;
@property(nonatomic, strong) NSMutableArray *templates;
@property(nonatomic, copy, nullable) NSString *activeIdentifier;
+ (NSString *)defaultDirectory;
- (nullable instancetype)initWithDirectory:(NSString *)directory error:(NSError **)error;
- (nullable SINDocument *)newDocument:(NSError **)error;
- (NSArray<SINDocument *> *)restoreDocuments:(NSError **)error;
- (BOOL)saveSessionDocuments:(NSArray<SINDocument *> *)documents activeIdentifier:(nullable NSString *)identifier error:(NSError **)error;
- (BOOL)saveSettings:(NSError **)error;
- (BOOL)saveTemplates:(NSError **)error;
- (BOOL)relocateToDirectory:(NSString *)directory error:(NSError **)error;
- (void)addRecentPath:(NSString *)path;
@end
NS_ASSUME_NONNULL_END
