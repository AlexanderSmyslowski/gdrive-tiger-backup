#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GDTProfileStore : NSObject

@property(nonatomic, copy, readonly) NSString *configDirectory;
@property(nonatomic, copy, readonly, nullable) NSString *activeProfileID;

- (instancetype)initWithConfigDirectory:(NSString *)configDirectory;
- (instancetype)initWithConfigDirectory:(NSString *)configDirectory
                             fileManager:(NSFileManager *)fileManager;
- (BOOL)migrateLegacyConfigAtPath:(NSString *)legacyPath
                            error:(NSError * _Nullable * _Nullable)error;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)profiles;
- (nullable NSString *)configPathForProfileID:(NSString *)profileID;
- (nullable NSString *)activeConfigPath;
- (nullable NSDictionary<NSString *, NSString *> *)createProfileNamed:(NSString *)name
                                                          copyingConfig:(NSDictionary<NSString *, NSString *> *)config
                                                                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)renameProfileID:(NSString *)profileID
                   name:(NSString *)name
                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)selectProfileID:(NSString *)profileID
                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteProfileID:(NSString *)profileID
                  error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
