#import "SINWindowController.h"
#import "SINProjects.h"

NS_ASSUME_NONNULL_BEGIN
@interface SINWindowController (ProjectSession)
- (void)createProject;
- (NSMenuItem *)projectMenuForItems:(NSArray *)items;
- (void)moveItems:(NSArray *)items toProject:(NSString *)folder;
// No panels in this entry point. Completion is delivered on the main queue;
// success may carry refresh/cleanup warnings for already-published files.
- (void)moveItems:(NSArray *)items toProject:(NSString *)folder
       completion:(void (^)(NSArray<SINProjectMoveResult *> *_Nullable results,
                            NSArray<NSString *> *warnings, NSError *_Nullable error))completion;
@end
@interface SINWindowController (ProjectSelfTest)
- (void)runProjectChecks:(void (^)(NSArray<NSString *> *,NSError *_Nullable))completion;
@end
NS_ASSUME_NONNULL_END
