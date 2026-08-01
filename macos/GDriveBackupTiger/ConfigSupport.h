#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *GDTConfigPath(void);
FOUNDATION_EXPORT NSString *GDTConfigPathForConfigDirectory(NSString *configDirectory);
FOUNDATION_EXPORT NSString *GDTDecodeConfigValue(NSString *value);
FOUNDATION_EXPORT NSMutableDictionary<NSString *, NSString *> *GDTReadConfigDictionary(void);
FOUNDATION_EXPORT NSMutableDictionary<NSString *, NSString *> *GDTReadConfigDictionaryAtPath(NSString *path);
FOUNDATION_EXPORT NSString *GDTNASRemountURLForMountedSMBSource(NSString *source);
FOUNDATION_EXPORT NSString *GDTPreferredNASRemountURL(
    NSString *resourceURLString,
    NSString *mountedSource,
    BOOL isSMBMount);
FOUNDATION_EXPORT NSString *GDTShellQuote(NSString * _Nullable value);
FOUNDATION_EXPORT BOOL GDTWriteConfigUpdates(NSDictionary<NSString *, NSString *> *updates,
                                             NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT BOOL GDTWriteConfigUpdatesAtPath(NSDictionary<NSString *, NSString *> *updates,
                                                   NSString *path,
                                                   NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
