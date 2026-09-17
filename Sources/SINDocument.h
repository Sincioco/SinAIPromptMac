#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const SINErrorDomain;
typedef NS_ENUM(NSInteger, SINErrorCode) { SINErrorConflict = 1, SINErrorOccupied, SINErrorEncoding, SINErrorReadOnly, SINErrorInvalidName, SINErrorStorage };
FOUNDATION_EXPORT BOOL SINAtomicWrite(NSData *data, NSString *path, BOOL backup, NSError **error);
FOUNDATION_EXPORT BOOL SINPathsReferToSameFile(NSString *first, NSString *second);
FOUNDATION_EXPORT BOOL SINMoveFilePreservingCase(NSString *source, NSString *destination, NSError **error);

@interface SINDocument : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy, nullable) NSString *path;
@property(nonatomic, copy, nullable) NSString *draftName;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *savedText;
@property(nonatomic, copy) NSString *encodingName;
@property(nonatomic, copy) NSString *savedEncoding;
@property(nonatomic, copy) NSString *newline;
@property(nonatomic, copy) NSString *savedNewline;
@property(nonatomic, copy, nullable) NSString *fingerprint;
@property(nonatomic) NSInteger untitledNumber;
@property(nonatomic) BOOL autosave;
@property(nonatomic) BOOL pinned;
@property(nonatomic) BOOL readOnly;
@property(nonatomic) NSInteger zoom;
@property(nonatomic) NSRange selection;
@property(nonatomic) double scroll;
@property(nonatomic, strong) NSDate *createdDate;
@property(nonatomic, strong) NSDate *modifiedDate;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) BOOL modified;
+ (NSArray<NSString *> *)encodingNames;
+ (nullable instancetype)openPath:(NSString *)path error:(NSError **)error;
+ (instancetype)documentFromDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)changedOnDisk:(NSError **)error;
- (BOOL)saveToPath:(NSString *)path overwriteConflict:(BOOL)overwrite error:(NSError **)error;
// Save As copies the matching asset folder and rebases local image references.
- (BOOL)saveAsToPath:(NSString *)path error:(NSError **)error;
// Call only after the user explicitly approves replacing the chosen destination.
- (BOOL)saveAsToPath:(NSString *)path replaceExisting:(BOOL)replace error:(NSError **)error;
// Moves saved HTML and its matching folder; pending unsaved text remains unsaved.
- (BOOL)renameToFilename:(NSString *)filename error:(NSError **)error;
- (BOOL)setFileReadOnly:(BOOL)readOnly error:(NSError **)error;
+ (NSString *)fingerprintForData:(NSData *)data;
@end
@interface SINDocument (Rebase)
+ (NSString *)rebaseHTML:(NSString *)html fromPath:(NSString *)oldPath toPath:(NSString *)newPath assetFolderMoved:(BOOL)moved;
@end
NS_ASSUME_NONNULL_END
