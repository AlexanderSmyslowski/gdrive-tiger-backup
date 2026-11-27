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

        NSString *uuid = @"5861298E-D6FE-445F-A407-71EC3C8DE30B";
        NSString *history = [@[
            @"v1\t100\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tlog\t90",
            @"v1\t200\tsuccess\tapfs\t/Volumes/Disk A/GoogleDrive-Backup\tlog\t190",
            @"v1\t300\tsuccess\tnas\t/Volumes/share-1/GoogleDrive-Backup\tschedule\t290",
            @"v1\t400\tfailure\tnas\t/Volumes/share/GoogleDrive-Backup\tschedule\t390",
            @"v1\t500\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tschedule\t490",
            @"v1\t600\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tschedule-retry\t590",
            [NSString stringWithFormat:@"v1\t700\tfailure\tapfs\t/Volumes/Disk A/GoogleDrive-Backup\tmanual\t690\t%@\tSamsung PSSD T7\t1000204886016\tyes\tUSB", uuid.lowercaseString],
            @"v1\t650\tcancelled\tapfs\t/Volumes/Disk B/GoogleDrive-Backup\tmanual\t640",
            @"v1\t660\tsuccess\tapfs\t/Volumes/Same/GoogleDrive-Backup\tlog\t650",
            @"v1\t661\tsuccess\tapfs\t/Volumes/Same/GoogleDrive-Backup\tmanual\t655\t11111111-1111-1111-1111-111111111111\tDisk One\t1\tno\tUSB",
            @"v1\t662\tsuccess\tapfs\t/Volumes/Same/GoogleDrive-Backup\tmanual\t656\t22222222-2222-2222-2222-222222222222\tDisk Two\t2\tno\tUSB",
            @"v2\t999\tsuccess\tnas\t/Volumes/x/y\tschedule\t1",
            @"v1\tabc\tsuccess\tnas\t/Volumes/x/y\tschedule\t1",
            @"v1\t800\tsuccess\tother\t/Volumes/x/y\tschedule\t1",
            @"garbage", @""
        ] componentsJoinedByString:@"\n"];
        NSArray<NSDictionary *> *groups = GDTBackupHistoryGroups(history, 10, 10);
        NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
        for (NSDictionary *group in groups) byKey[group[@"key"]] = group;
        NSDictionary *disk = byKey[[@"apfs:" stringByAppendingString:uuid]];
        NSDictionary *nas = byKey[@"nas:GoogleDrive-Backup"];
        Assert(groups.count == 6 && [groups.firstObject[@"key"] isEqual:disk[@"key"]],
               @"history groups one entry per destination, newest activity first, and skips unknown lines");
        Assert([disk[@"label"] isEqual:@"Disk A"] && [disk[@"device"] isEqual:@"Samsung PSSD T7"] &&
               [disk[@"bytes"] isEqual:@1000204886016] && [disk[@"solid"] isEqual:@"yes"] &&
               [disk[@"bus"] isEqual:@"USB"] && [disk[@"lastSuccess"] isEqual:@200] &&
               [disk[@"lastFailure"] isEqual:@700] && [disk[@"runs"] count] == 2 &&
               byKey[@"apfs-name:Disk A"] == nil,
               @"a disk is identified by its volume UUID, describes its device and adopts older runs under its name");
        Assert(byKey[@"apfs-name:Same"] && byKey[@"apfs:11111111-1111-1111-1111-111111111111"] &&
               byKey[@"apfs:22222222-2222-2222-2222-222222222222"],
               @"old runs stay separate when two disks carry the same volume name");
        NSDictionary *bDisk = byKey[@"apfs-name:Disk B"];
        Assert(bDisk && bDisk[@"lastSuccess"] == nil && bDisk[@"lastFailure"] == nil &&
               [[bDisk[@"runs"] firstObject][@"status"] isEqual:@"cancelled"],
               @"a cancelled run is listed but is neither a success nor a failure");
        NSArray *nasRuns = nas[@"runs"];
        Assert([nas[@"lastSuccess"] isEqual:@600] && nas[@"lastFailure"] == nil && nasRuns.count == 5 &&
               [nasRuns[0][@"finished"] isEqual:@600] && [nasRuns[0][@"started"] isEqual:@590] &&
               [nasRuns[2][@"status"] isEqual:@"failure"],
               @"a NAS share keeps one history across mount-point names, newest first, older failure not flagged");
        Assert([GDTBackupHistoryGroups(history, 2, 10).lastObject[@"runs"] count] <= 2 &&
               GDTBackupHistoryGroups(history, 3, 1).count == 1 &&
               GDTBackupHistoryGroups(@"", 3, 5).count == 0,
               @"history respects run and group limits and handles an empty file");
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
