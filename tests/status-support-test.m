#import <Foundation/Foundation.h>

#import "BackupStatusSupport.h"


static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSString *TemporaryPath(NSString *name) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"gdrive-%@-%@", name, NSUUID.UUID.UUIDString]];
}

static void TrashPath(NSString *path) {
    [NSFileManager.defaultManager removeItemAtURL:[NSURL fileURLWithPath:path] error:nil];
}

int main(void) {
    @autoreleasepool {
        NSDate *successNow = [NSDate dateWithTimeIntervalSince1970:1000];
        NSDictionary *retained = @{@"protocol": @"1", @"status": @"failure", @"last_success_at": @"200",
            @"last_success_target": @"nas", @"last_success_destination": @"/Volumes/Archive/Backup",
            @"last_success_volume": @"Archive", @"target": @"apfs", @"destination": @"/Volumes/Other"};
        NSDictionary *last = GDTLastSuccessfulBackupForSummary(retained, successNow);
        Assert([last[@"volume"] isEqual:@"Archive"] && [last[@"at"] isEqual:@"200"],
            @"last success retains its own target after a later failure on another disk");
        NSDictionary *legacy = @{@"protocol": @"1", @"status": @"success", @"pid": @"123", @"started_at": @"100",
            @"finished_at": @"300", @"exit_code": @"0", @"target": @"apfs", @"destination": @"/Volumes/TOSHIBA/Backup"};
        last = GDTLastSuccessfulBackupForSummary(legacy, successNow);
        Assert([last[@"volume"] isEqual:@"TOSHIBA"] && [last[@"at"] isEqual:@"300"],
            @"a legacy successful run identifies its recorded volume without current config");
        last = GDTLastSuccessfulBackupForSummary(
            @{@"protocol": @"1", @"status": @"failure", @"last_success_at": @"400", @"destination": @"/Volumes/Wrong"}, successNow);
        Assert([last[@"at"] isEqual:@"400"] && ![last[@"volume"] length],
            @"timestamp-only history never borrows the latest failed destination");
        Assert(!GDTLastSuccessfulBackupForSummary(
            @{@"protocol": @"1", @"last_success_at": @"1001"}, successNow) &&
            !GDTLastSuccessfulBackupForSummary(@{@"protocol": @"1", @"last_success_at": @"12junk"}, successNow),
            @"future and malformed success timestamps are rejected");
        NSString *historyRoot = TemporaryPath(@"last-success-root");
        NSString *manualDir = [historyRoot stringByAppendingPathComponent:@"manual/disk-uuid"];
        [NSFileManager.defaultManager createDirectoryAtPath:manualDir withIntermediateDirectories:YES attributes:nil error:nil];
        [@"protocol=1\nstatus=success\npid=123\nstarted_at=100\nfinished_at=300\nexit_code=0\ntarget=apfs\ndestination=/Volumes/TOSHIBA/Backup\n"
            writeToFile:[manualDir stringByAppendingPathComponent:@"last-run.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        last = GDTLatestSuccessfulBackupAtRoot(historyRoot, successNow);
        Assert([last[@"volume"] isEqual:@"TOSHIBA"], @"external-disk success survives restart without in-memory selection");
        NSString *profileDir = [historyRoot stringByAppendingPathComponent:@"profiles/default"];
        [NSFileManager.defaultManager createDirectoryAtPath:profileDir withIntermediateDirectories:YES attributes:nil error:nil];
        [@"protocol=1\nstatus=failure\nlast_success_at=400\n"
            writeToFile:[profileDir stringByAppendingPathComponent:@"last-run.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        last = GDTLatestSuccessfulBackupAtRoot(historyRoot, successNow);
        Assert([last[@"at"] isEqual:@"400"] && ![last[@"volume"] length],
            @"newest success wins even when its historical medium is unknown");
        [@"protocol=1\nstatus=failure\nlast_success_at=1001\n"
            writeToFile:[profileDir stringByAppendingPathComponent:@"last-run.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        last = GDTLatestSuccessfulBackupAtRoot(historyRoot, successNow);
        Assert([last[@"at"] isEqual:@"300"], @"a future record cannot hide the valid external success");
        TrashPath(historyRoot);
        NSString *successPath = TemporaryPath(@"summary-success");
        [@"protocol=1\nstatus=success\npid=123\nstarted_at=100\nfinished_at=200\nexit_code=0\ntrigger=manual\ntarget=nas\ndestination=/Volumes/Archive\n"
            writeToFile:successPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Assert([GDTBackupSummaryStatusAtPath(successPath) isEqualToString:@"success"],
               @"validated durable success is accepted");
        TrashPath(successPath);

        NSString *malformedPath = TemporaryPath(@"summary-malformed");
        [@"status=success\nexit_code=0\n"
            writeToFile:malformedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Assert([GDTBackupSummaryStatusAtPath(malformedPath) isEqualToString:@"unknown"],
               @"malformed state never becomes success");
        TrashPath(malformedPath);
        Assert([GDTBackupSummaryStatusAtPath(TemporaryPath(@"missing")) isEqualToString:@"unknown"],
               @"missing state is explicitly unknown");

        NSString *orphanPath = TemporaryPath(@"summary-orphan");
        [@"protocol=1\nstatus=running\npid=99999999\nstarted_at=100\ntrigger=schedule\ntarget=apfs\ndestination=/Volumes/Archive\n"
            writeToFile:orphanPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Assert([GDTBackupSummaryStatusAtPath(orphanPath) isEqualToString:@"interrupted"],
               @"a dead running process is reported as interrupted");
        TrashPath(orphanPath);

        NSDictionary *defaultAPFS = @{};
        Assert([GDTBackupDestinationForConfig(defaultAPFS) isEqualToString:@"/Volumes/GoogleDrive-Backup"],
               @"default APFS destination matches the backup engine");

        NSDictionary *nasConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"nas",
            @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/Archive",
            @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
            @"GDRIVE_BACKUP_NAS_URL": @"smb://private-user@example.invalid/Archive"
        };
        NSString *nasDestination = GDTBackupDestinationForConfig(nasConfig);
        Assert([nasDestination isEqualToString:@"/Volumes/Archive/GoogleDrive-Backup"] &&
               [nasDestination rangeOfString:@"private-user"].location == NSNotFound,
               @"NAS destination uses only the local mount path and never URL credentials");
        Assert([GDTBackupCapacityPathForConfig(nasConfig) isEqualToString:@"/Volumes/Archive"],
               @"NAS capacity is measured at the mount instead of a missing subfolder");

        NSDictionary *overrideConfig = @{
            @"GDRIVE_BACKUP_TARGET": @"apfs",
            @"GDRIVE_BACKUP_DEST_ROOT": @"/Volumes/Archive/Custom"
        };
        Assert([GDTBackupDestinationForConfig(overrideConfig) isEqualToString:@"/Volumes/Archive/Custom"],
               @"explicit destination override remains authoritative");

        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:2 * 60 * 60];
        NSDateComponents *beforeComponents = [[NSDateComponents alloc] init];
        beforeComponents.year = 2026;
        beforeComponents.month = 7;
        beforeComponents.day = 11;
        beforeComponents.hour = 19;
        beforeComponents.minute = 30;
        NSDate *before = [calendar dateFromComponents:beforeComponents];
        NSDate *beforeNext = GDTNextDailyRunAfterDate(before, calendar);
        NSDateComponents *beforeNextParts = [calendar components:(NSCalendarUnitDay | NSCalendarUnitHour)
                                                        fromDate:beforeNext];
        Assert(beforeNextParts.day == 11 && beforeNextParts.hour == 20,
               @"daily schedule points to today before 20:00");

        NSDateComponents *afterComponents = [beforeComponents copy];
        afterComponents.hour = 20;
        afterComponents.minute = 1;
        NSDate *after = [calendar dateFromComponents:afterComponents];
        NSDate *afterNext = GDTNextDailyRunAfterDate(after, calendar);
        NSDateComponents *afterNextParts = [calendar components:(NSCalendarUnitDay | NSCalendarUnitHour)
                                                       fromDate:afterNext];
        Assert(afterNextParts.day == 12 && afterNextParts.hour == 20,
               @"daily schedule rolls to tomorrow after 20:00");

        NSString *storagePath = TemporaryPath(@"storage");
        [NSFileManager.defaultManager createDirectoryAtPath:storagePath
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        NSDictionary<NSString *, NSNumber *> *capacity = GDTStorageCapacityForPath(storagePath);
        Assert(capacity[@"totalBytes"].unsignedLongLongValue > 0 &&
               capacity[@"freeBytes"].unsignedLongLongValue > 0,
               @"mounted destination exposes free and total capacity");
        TrashPath(storagePath);
        Assert(GDTStorageCapacityForPath(TemporaryPath(@"missing-storage")) == nil,
               @"unavailable destination has no fabricated capacity");

        NSString *profileSummary = GDTBackupSummaryPathForConfig(@{
            @"GDRIVE_BACKUP_PROFILE_ID": @"a1b2c3d4-1234-5678-9abc-def012345678",
            @"GDRIVE_BACKUP_PROFILE_NAME": @"Private NAS name"
        });
        Assert([profileSummary hasSuffix:
                   @"GDrive Backup Tiger/profiles/a1b2c3d4-1234-5678-9abc-def012345678/last-run.status"] &&
               [profileSummary rangeOfString:@"Private NAS name"].location == NSNotFound,
               @"each trusted profile has an isolated summary without exposing its display name");
        Assert([GDTBackupSummaryPathForConfig(@{
                   @"GDRIVE_BACKUP_PROFILE_ID": @"../../outside"
               }) isEqualToString:GDTBackupSummaryPath()],
               @"unsafe profile identifiers cannot redirect summary state");
        Assert([GDTBackupSummaryPath() hasSuffix:@"Library/Application Support/GDrive Backup Tiger/last-run.status"],
               @"default durable summary lives in private Application Support");

        NSString *history = [@[
            @"v1\t100\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tlog\t90",
            @"v1\t200\tsuccess\tapfs\t/Volumes/Disk A/GoogleDrive-Backup\tmanual\t190",
            @"v1\t300\tsuccess\tnas\t/Volumes/share-1/GoogleDrive-Backup\tschedule\t290",
            @"v1\t400\tfailure\tnas\t/Volumes/share/GoogleDrive-Backup\tschedule\t390",
            @"v1\t500\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tschedule\t490",
            @"v1\t600\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tschedule-retry\t590",
            @"v1\t700\tfailure\tapfs\t/Volumes/Disk A/GoogleDrive-Backup\tmanual\t690",
            @"v1\t650\tcancelled\tapfs\t/Volumes/Disk B/GoogleDrive-Backup\tmanual\t640",
            @"v2\t999\tsuccess\tnas\t/Volumes/x/y\tschedule\t1",
            @"v1\tabc\tsuccess\tnas\t/Volumes/x/y\tschedule\t1",
            @"v1\t800\tsuccess\tother\t/Volumes/x/y\tschedule\t1",
            @"garbage", @""
        ] componentsJoinedByString:@"\n"];
        NSArray<NSDictionary *> *groups = GDTBackupHistoryGroups(history, 3, 5);
        Assert(groups.count == 3, @"history groups one entry per destination and skips unknown lines");
        NSDictionary *disk = groups.count > 0 ? groups[0] : nil;
        NSDictionary *bDisk = groups.count > 1 ? groups[1] : nil;
        NSDictionary *nas = groups.count > 2 ? groups[2] : nil;
        Assert([disk[@"label"] isEqual:@"Disk A"] && [disk[@"target"] isEqual:@"apfs"] &&
               [disk[@"successes"] isEqual:@[@200]] && [disk[@"lastFailure"] isEqual:@700],
               @"an external disk is named by its volume and shows a failure newer than its last success");
        Assert([bDisk[@"label"] isEqual:@"Disk B"] && [bDisk[@"successes"] count] == 0 &&
               bDisk[@"lastFailure"] == nil,
               @"a cancelled run is activity but neither a success nor a failure");
        Assert([nas[@"label"] isEqual:@"GoogleDrive-Backup"] &&
               [nas[@"successes"] isEqual:(@[@600, @500, @300])] && nas[@"lastFailure"] == nil,
               @"a NAS share keeps one history across mount-point names, newest three successes, older failure hidden");
        Assert(GDTBackupHistoryGroups(history, 3, 1).count == 1 &&
               GDTBackupHistoryGroups(@"", 3, 5).count == 0,
               @"history respects the group limit and handles an empty file");
        Assert([GDTBackupHistoryPath() hasSuffix:
                   @"Library/Application Support/GDrive Backup Tiger/run-history.tsv"],
               @"run history lives next to the summaries");
    }

    if (failures > 0) {
        printf("%d status support test(s) failed.\n", failures);
        return 1;
    }
    printf("All status support tests passed.\n");
    return 0;
}
