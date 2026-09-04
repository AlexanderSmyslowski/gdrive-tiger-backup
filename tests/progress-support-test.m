#import <Foundation/Foundation.h>
#include <math.h>
#include <unistd.h>
#import "BackupProgressSupport.h"

static int failures = 0;
static void Assert(BOOL condition, NSString *message) {
    if (condition) printf("ok - %s\n", message.UTF8String);
    else { printf("not ok - %s\n", message.UTF8String); failures++; }
}

int main(void) {
    @autoreleasepool {
        NSTimeInterval now = floor(NSDate.date.timeIntervalSince1970);
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

        NSMutableDictionary *oneSecondFuture = [progress mutableCopy];
        oneSecondFuture[@"updated_at"] = @"2000000001";
        Assert(GDTValidatedBackupProgressForValues(
                   oneSecondFuture, summary, @"running", @"default",
                   2000000000) == nil,
               @"the smallest representable future timestamp is rejected");

        NSMutableDictionary *mixedTerminal = [progress mutableCopy];
        mixedTerminal[@"status"] = @"finished";
        Assert(GDTValidatedBackupProgressForValues(
                   mixedTerminal, summary, @"running", @"default", now) == nil,
               @"terminal progress cannot be validated as live");

        NSMutableDictionary *unknownState = [progress mutableCopy];
        unknownState[@"status"] = @"paused";
        Assert(GDTValidatedBackupProgressForValues(
                   unknownState, summary, @"running", @"default", now) == nil,
               @"unknown progress states are rejected while validating");

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

        NSMutableDictionary *phaseOnly = [progress mutableCopy];
        [phaseOnly removeObjectForKey:@"percent"];
        [phaseOnly removeObjectForKey:@"detail"];
        NSDictionary *acceptedPhaseOnly = GDTValidatedBackupProgressForValues(
            phaseOnly, summary, @"running", @"default", now);
        Assert([acceptedPhaseOnly[@"phase"] isEqualToString:@"3/5"] &&
               acceptedPhaseOnly[@"percent"] == nil &&
               acceptedPhaseOnly[@"detail"] == nil,
               @"a fresh copy-phase heartbeat remains valid and indeterminate");

        NSMutableDictionary *transferring = [phaseOnly mutableCopy];
        transferring[@"transferred"] = @"12.000 MiB";
        transferring[@"speed"] = @"1.500 MiB/s";
        NSDictionary *acceptedTransferring = GDTValidatedBackupProgressForValues(
            transferring, summary, @"running", @"default", now);
        Assert([acceptedTransferring[@"transferred"] isEqualToString:@"12.000 MiB"] &&
               [acceptedTransferring[@"speed"] isEqualToString:@"1.500 MiB/s"],
               @"bounded unknown-total transfer telemetry is accepted");

        NSMutableDictionary *malformedTransferring = [transferring mutableCopy];
        malformedTransferring[@"transferred"] = @"secret-file.pdf";
        Assert(GDTValidatedBackupProgressForValues(
                   malformedTransferring, summary, @"running", @"default", now) == nil,
               @"non-aggregate transfer telemetry is rejected");

        NSMutableDictionary *partialTransferring = [transferring mutableCopy];
        [partialTransferring removeObjectForKey:@"speed"];
        Assert(GDTValidatedBackupProgressForValues(
                   partialTransferring, summary, @"running", @"default", now) == nil,
               @"partial unknown-total transfer telemetry is rejected");

        NSMutableDictionary *preparingWithTransfer = [preparing mutableCopy];
        preparingWithTransfer[@"transferred"] = @"12.000 MiB";
        preparingWithTransfer[@"speed"] = @"1.500 MiB/s";
        Assert(GDTValidatedBackupProgressForValues(
                   preparingWithTransfer, summary, @"running", @"default", now) == nil,
               @"preparation records cannot claim transfer activity");

        NSMutableDictionary *checking = [phaseOnly mutableCopy];
        checking[@"checked"] = @"43129";
        checking[@"listed"] = @"103256";
        NSDictionary *acceptedChecking = GDTValidatedBackupProgressForValues(
            checking, summary, @"running", @"default", now);
        Assert([acceptedChecking[@"checked"] isEqualToString:@"43129"] &&
               [acceptedChecking[@"listed"] isEqualToString:@"103256"],
               @"bounded aggregate check counters are accepted");

        NSMutableDictionary *invalidChecking = [checking mutableCopy];
        invalidChecking[@"checked"] = @"43k";
        Assert(GDTValidatedBackupProgressForValues(
                   invalidChecking, summary, @"running", @"default", now) == nil,
               @"non-numeric aggregate check counters are rejected");

        NSMutableDictionary *oversizedChecking = [checking mutableCopy];
        oversizedChecking[@"listed"] = @"1234567890123456789";
        Assert(GDTValidatedBackupProgressForValues(
                   oversizedChecking, summary, @"running", @"default", now) == nil,
               @"oversized aggregate check counters are rejected");

        NSMutableDictionary *partialChecking = [checking mutableCopy];
        [partialChecking removeObjectForKey:@"listed"];
        Assert(GDTValidatedBackupProgressForValues(
                   partialChecking, summary, @"running", @"default", now) == nil,
               @"partial aggregate check telemetry is rejected");

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

        NSString *mixedTerminalPath = [fixtureRoot
            stringByAppendingPathComponent:@"mixed-terminal.status"];
        NSString *mixedTerminalContent = [validContent
            stringByAppendingString:@"status=finished\n"];
        [mixedTerminalContent writeToFile:mixedTerminalPath atomically:YES
                                 encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600}
                                      ofItemAtPath:mixedTerminalPath error:nil];
        Assert(GDTReadBackupProgressAtPath(mixedTerminalPath) == nil,
               @"mixed terminal and live records are rejected while parsing");

        NSString *unknownStatePath = [fixtureRoot
            stringByAppendingPathComponent:@"unknown-state.status"];
        NSString *unknownStateContent = [validContent
            stringByAppendingString:@"status=paused\n"];
        [unknownStateContent writeToFile:unknownStatePath atomically:YES
                                encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600}
                                      ofItemAtPath:unknownStatePath error:nil];
        Assert(GDTReadBackupProgressAtPath(unknownStatePath) == nil,
               @"unknown progress states are rejected while parsing");

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
