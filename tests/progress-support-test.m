#import <Foundation/Foundation.h>
#include <unistd.h>
#import "BackupProgressSupport.h"

static int failures = 0;
static void Assert(BOOL condition, NSString *message) {
    if (condition) printf("ok - %s\n", message.UTF8String);
    else { printf("not ok - %s\n", message.UTF8String); failures++; }
}

int main(void) {
    @autoreleasepool {
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSString *pid = [NSString stringWithFormat:@"%d", getpid()];
        NSString *started = [NSString stringWithFormat:@"%.0f", now - 10];
        NSDictionary *summary = @{
            @"protocol": @"1", @"status": @"running", @"pid": pid,
            @"started_at": started, @"trigger": @"schedule-retry",
            @"retry_attempt": @"1"
        };
        NSDictionary *progress = @{
            @"protocol": @"1", @"profile_id": @"default", @"pid": pid,
            @"started_at": started, @"trigger": @"schedule-retry",
            @"retry_attempt": @"1", @"label": @"Shared Drive",
            @"phase": @"3/5", @"percent": @"63",
            @"detail": @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s",
            @"updated_at": [NSString stringWithFormat:@"%.0f", now]
        };
        NSDictionary *accepted = GDTValidatedBackupProgressForValues(
            progress, summary, @"running", @"default", now);
        Assert([accepted[@"percent"] isEqualToString:@"63"] &&
               [accepted[@"phase"] isEqualToString:@"3/5"],
               @"matching live progress is accepted");
        Assert([GDTBackupProgressPathForSummaryPath(@"/tmp/default/last-run.status")
                   isEqualToString:@"/tmp/default/current-progress.status"],
               @"progress path stays beside the profile summary");

        NSMutableDictionary *crossProfile = [progress mutableCopy];
        crossProfile[@"profile_id"] = @"archive";
        Assert(GDTValidatedBackupProgressForValues(
                   crossProfile, summary, @"running", @"default", now) == nil,
               @"cross-profile progress is rejected");

        NSMutableDictionary *wrongProtocol = [progress mutableCopy];
        wrongProtocol[@"protocol"] = @"2";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongProtocol, summary, @"running", @"default", now) == nil,
               @"unknown progress protocols are rejected");

        NSMutableDictionary *stale = [progress mutableCopy];
        stale[@"updated_at"] = [NSString stringWithFormat:@"%.0f", now - 61];
        Assert(GDTValidatedBackupProgressForValues(
                   stale, summary, @"running", @"default", now) == nil,
               @"stale progress is rejected");

        NSMutableDictionary *wrongPID = [progress mutableCopy];
        wrongPID[@"pid"] = @"99999999";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongPID, summary, @"running", @"default", now) == nil,
               @"mismatched process progress is rejected");

        NSMutableDictionary *deadSummary = [summary mutableCopy];
        deadSummary[@"pid"] = @"99999999";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongPID, deadSummary, @"running", @"default", now) == nil,
               @"matching telemetry for a dead process is rejected");

        NSMutableDictionary *wrongStart = [progress mutableCopy];
        wrongStart[@"started_at"] = [NSString stringWithFormat:@"%lld",
            started.longLongValue - 1];
        Assert(GDTValidatedBackupProgressForValues(
                   wrongStart, summary, @"running", @"default", now) == nil,
               @"mismatched start times are rejected");

        NSMutableDictionary *wrongTrigger = [progress mutableCopy];
        wrongTrigger[@"trigger"] = @"schedule";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongTrigger, summary, @"running", @"default", now) == nil,
               @"mismatched triggers are rejected");

        NSMutableDictionary *wrongRetry = [progress mutableCopy];
        wrongRetry[@"retry_attempt"] = @"2";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongRetry, summary, @"running", @"default", now) == nil,
               @"mismatched retry attempts are rejected");

        NSMutableDictionary *future = [progress mutableCopy];
        future[@"updated_at"] = [NSString stringWithFormat:@"%.0f", now + 2];
        Assert(GDTValidatedBackupProgressForValues(
                   future, summary, @"running", @"default", now) == nil,
               @"future progress is rejected");

        NSMutableDictionary *missingIdentity = [progress mutableCopy];
        [missingIdentity removeObjectForKey:@"started_at"];
        Assert(GDTValidatedBackupProgressForValues(
                   missingIdentity, summary, @"running", @"default", now) == nil,
               @"missing identity fields are rejected");

        NSMutableDictionary *unsafe = [progress mutableCopy];
        unsafe[@"detail"] = @"file-name.pdf\nsecret";
        Assert(GDTValidatedBackupProgressForValues(
                   unsafe, summary, @"running", @"default", now) == nil,
               @"multiline detail is rejected");

        NSMutableDictionary *rawLogDetail = [progress mutableCopy];
        rawLogDetail[@"detail"] = @"secret-file.pdf: Failed to copy";
        Assert(GDTValidatedBackupProgressForValues(
                   rawLogDetail, summary, @"running", @"default", now) == nil,
               @"arbitrary rclone log text is rejected");

        NSMutableDictionary *outOfRange = [progress mutableCopy];
        outOfRange[@"percent"] = @"101";
        Assert(GDTValidatedBackupProgressForValues(
                   outOfRange, summary, @"running", @"default", now) == nil,
               @"out-of-range percentages are rejected");

        NSMutableDictionary *impossiblePhase = [progress mutableCopy];
        impossiblePhase[@"phase"] = @"6/5";
        Assert(GDTValidatedBackupProgressForValues(
                   impossiblePhase, summary, @"running", @"default", now) == nil,
               @"impossible phases are rejected");

        NSMutableDictionary *unknownLabel = [progress mutableCopy];
        unknownLabel[@"label"] = @"THE ONE";
        Assert(GDTValidatedBackupProgressForValues(
                   unknownLabel, summary, @"running", @"default", now) == nil,
               @"source names cannot become public progress labels");

        NSMutableDictionary *preparing = [progress mutableCopy];
        preparing[@"label"] = @"preparing";
        [preparing removeObjectForKey:@"phase"];
        [preparing removeObjectForKey:@"percent"];
        [preparing removeObjectForKey:@"detail"];
        Assert(GDTValidatedBackupProgressForValues(
                   preparing, summary, @"running", @"default", now) != nil,
               @"a valid preparation record remains indeterminate");

        NSString *fixtureRoot = NSProcessInfo.processInfo.environment[
            @"GDRIVE_PROGRESS_TEST_DIR"];
        NSString *validPath = [fixtureRoot
            stringByAppendingPathComponent:@"valid.status"];
        NSMutableString *validContent = [NSMutableString string];
        for (NSString *key in @[@"protocol", @"profile_id", @"pid",
                                 @"started_at", @"trigger", @"retry_attempt",
                                 @"label", @"phase", @"percent", @"detail",
                                 @"updated_at"]) {
            [validContent appendFormat:@"%@=%@\n", key, progress[key]];
        }
        [validContent writeToFile:validPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600} ofItemAtPath:validPath error:nil];
        Assert([GDTReadBackupProgressAtPath(validPath)[@"percent"]
                   isEqualToString:@"63"],
               @"a private valid progress record is parsed");

        NSString *duplicatePath = [fixtureRoot
            stringByAppendingPathComponent:@"duplicate.status"];
        NSString *duplicateContent = [validContent
            stringByAppendingString:@"protocol=1\n"];
        [duplicateContent writeToFile:duplicatePath
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600} ofItemAtPath:duplicatePath error:nil];
        Assert(GDTReadBackupProgressAtPath(duplicatePath) == nil,
               @"duplicate keys are rejected while parsing");

        NSString *missingPath = [fixtureRoot
            stringByAppendingPathComponent:@"missing.status"];
        NSString *missingContent = [validContent
            stringByReplacingOccurrencesOfString:
                [NSString stringWithFormat:@"updated_at=%@\n", progress[@"updated_at"]]
                                      withString:@""];
        [missingContent writeToFile:missingPath atomically:YES
                           encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600} ofItemAtPath:missingPath error:nil];
        Assert(GDTReadBackupProgressAtPath(missingPath) == nil,
               @"missing required parser keys are rejected");

        NSString *publicPath = [fixtureRoot
            stringByAppendingPathComponent:@"public.status"];
        [validContent writeToFile:publicPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0644} ofItemAtPath:publicPath error:nil];
        Assert(GDTReadBackupProgressAtPath(publicPath) == nil,
               @"group/world-readable progress is rejected");

        NSString *symlinkPath = [fixtureRoot
            stringByAppendingPathComponent:@"linked.status"];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:symlinkPath
            withDestinationPath:validPath error:nil];
        Assert(GDTReadBackupProgressAtPath(symlinkPath) == nil,
               @"symlinked progress is rejected without following it");

        Assert(GDTValidatedBackupProgressForValues(
                   progress, summary, @"success", @"default", now) == nil,
               @"terminal summaries cannot expose live progress");
    }
    return failures ? 1 : 0;
}
