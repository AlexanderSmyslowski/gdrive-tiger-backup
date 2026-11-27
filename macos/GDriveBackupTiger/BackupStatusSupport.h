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

FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable GDTLastSuccessfulBackupForSummary(
    NSDictionary<NSString *, NSString *> *summary, NSDate *now);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable GDTLatestSuccessfulBackupAtRoot(
    NSString *root, NSDate *now);

// Run history written by the engine (run-history.tsv), one group per
// destination, most recently used first. Each group has:
//   key          stable identity ("apfs:<volume uuid>", "apfs-name:<name>",
//                "nas:<folder>")
//   target       "nas" or "apfs"
//   label        volume name (disk) or backup folder (NAS), never a host
//   device, bytes, solid, bus   newest known disk description (optional)
//   lastSuccess  epoch of the newest success (optional)
//   lastFailure  epoch of a failure newer than lastSuccess (optional)
//   lastActivity epoch of the newest run
//   runs         up to `runLimit` runs, newest first: status, finished, started
FOUNDATION_EXPORT NSString *GDTBackupHistoryPath(void);
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, id> *> *GDTBackupHistoryGroups(
    NSString *content, NSUInteger runLimit, NSUInteger maxGroups);

NS_ASSUME_NONNULL_END
