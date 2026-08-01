#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *GDTBackupProgressPathForSummaryPath(NSString *summaryPath);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
    GDTReadBackupProgressAtPath(NSString *path);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
    GDTValidatedBackupProgressForValues(
        NSDictionary<NSString *, NSString *> *progress,
        NSDictionary<NSString *, NSString *> *summary,
        NSString *summaryStatus,
        NSString *profileID,
        NSTimeInterval nowTimestamp);

NS_ASSUME_NONNULL_END
