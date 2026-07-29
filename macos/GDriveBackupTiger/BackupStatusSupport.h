#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *GDTBackupSummaryPath(void);
FOUNDATION_EXPORT NSString *GDTBackupSummaryPathForConfig(NSDictionary<NSString *, NSString *> *config);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *GDTReadBackupSummaryAtPath(NSString *path);
FOUNDATION_EXPORT NSString *GDTBackupSummaryStatusForValues(
    NSDictionary<NSString *, NSString *> *values);
FOUNDATION_EXPORT NSString *GDTBackupSummaryStatusAtPath(NSString *path);
FOUNDATION_EXPORT NSString *GDTBackupDestinationForConfig(NSDictionary<NSString *, NSString *> *config);
FOUNDATION_EXPORT NSString *GDTBackupCapacityPathForConfig(NSDictionary<NSString *, NSString *> *config);
FOUNDATION_EXPORT NSDate *GDTNextDailyRunAfterDate(NSDate *date, NSCalendar *calendar);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> * _Nullable GDTStorageCapacityForPath(NSString *path);

NS_ASSUME_NONNULL_END
