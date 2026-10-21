#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A detached disk snapshot. Rewrite html with the editor's HTML parser before
// committing; pending editor text must remain separate from this saved content.
@interface SINProjectMoveSnapshot : NSObject
@property(nonatomic,copy,readonly) NSString *sourcePath;
@property(nonatomic,copy,readonly) NSString *destinationPath;
@property(nonatomic,copy,readonly,nullable) NSString *sourceAssets;
@property(nonatomic,copy,readonly,nullable) NSString *destinationAssets;
@property(nonatomic,copy) NSString *html;
@property(nonatomic,copy,readonly) NSString *fingerprint;
@property(nonatomic,copy,readonly) NSString *encodingName;
@property(nonatomic,copy,readonly) NSString *newline;
+ (nullable instancetype)readPath:(NSString *)path destinationFolder:(NSString *)folder error:(NSError **)error;
@end

@interface SINProjectMoveResult : NSObject
@property(nonatomic,copy,readonly) NSString *sourcePath;
@property(nonatomic,copy,readonly) NSString *destinationPath;
@property(nonatomic,copy,readonly) NSString *html;
@property(nonatomic,copy,readonly) NSString *fingerprint;
@property(nonatomic,strong,readonly) NSDate *createdDate;
@property(nonatomic,strong,readonly) NSDate *modifiedDate;
@property(nonatomic,readonly) BOOL readOnly;
@property(nonatomic,copy,readonly,nullable) NSString *cleanupWarning;
@end

@interface SINProjects : NSObject
+ (NSString *)displaySuffixForDocumentPath:(nullable NSString *)path;
+ (nullable NSString *)createProjectInDirectory:(NSString *)directory name:(NSString *)name error:(NSError **)error;
+ (BOOL)rememberProjectFolder:(NSString *)folder settings:(NSMutableDictionary *)settings error:(NSError **)error;
+ (NSArray<NSString *> *)knownProjectFoldersInSettings:(NSDictionary *)settings;
// URL moves consumed by window.editor.rewriteProjectReferences. Directory URLs
// include their trailing slash. Each mapping carries its source case rule;
// sensitivity-changing moves include exact names from the image-folder manifest.
+ (NSArray<NSDictionary *> *)referenceMovesForSnapshots:(NSArray<SINProjectMoveSnapshot *> *)snapshots;
+ (BOOL)caseSensitiveAtPath:(NSString *)path;
// Copies to the destination volume, verifies the full batch, reserves originals,
// then publishes with exclusive atomic renames. Failure restores source pairs;
// externally changed copies are retained and their paths appear in the error.
// progress runs synchronously on the calling thread after each stage/publication.
+ (nullable NSArray<SINProjectMoveResult *> *)commitSnapshots:(NSArray<SINProjectMoveSnapshot *> *)snapshots
                                                   progress:(void (^_Nullable)(NSUInteger done, NSUInteger total))progress
                                                      error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
