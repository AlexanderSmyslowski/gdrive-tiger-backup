#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString * _Nullable (^GDTRestoreDigestProvider)(NSURL *url, NSError **error);

@interface GDTRestoreCatalog : NSObject

- (instancetype)initWithBackupRootURL:(NSURL *)backupRootURL
                           fileManager:(NSFileManager *)fileManager;
- (NSArray<NSDictionary<NSString *, id> *> *)childrenAtRelativePath:(NSString *)relativePath
                                                               error:(NSError **)error;
- (NSArray<NSDictionary<NSString *, id> *> *)versionsForRelativePath:(NSString *)relativePath
                                                                error:(NSError **)error;

@end

@interface GDTRestoreCopier : NSObject

@property(nonatomic, copy) GDTRestoreDigestProvider digestProvider;

- (instancetype)initWithBackupRootURL:(NSURL *)backupRootURL
                           fileManager:(NSFileManager *)fileManager;
- (nullable NSDictionary<NSString *, id> *)restoreSourceURL:(NSURL *)sourceURL
                                             toDirectoryURL:(NSURL *)directoryURL
                                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
