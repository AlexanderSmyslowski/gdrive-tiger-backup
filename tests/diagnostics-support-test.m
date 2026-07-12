#import <Foundation/Foundation.h>

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

int main(void) {
    @autoreleasepool {
        Class builderClass = NSClassFromString(@"GDTDiagnosticsBuilder");
        Assert(builderClass != Nil, @"safe diagnostics builder is available");
        if (builderClass) {
            NSDictionary *config = @{
                @"GDRIVE_BACKUP_TARGET": @"nas",
                @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/alexander",
                @"GDRIVE_BACKUP_NAS_URL": @"smb://private-user:secret-password@nas.local/private-share",
                @"GDRIVE_BACKUP_NAS_SUBDIR": @"Customer Files",
                @"GDRIVE_BACKUP_SCHEDULE": @"daily",
                @"GDRIVE_BACKUP_ENCRYPTION": @"none",
                @"RCLONE_REMOTE": @"private-remote"
            };
            NSDictionary *summary = @{
                @"protocol": @"1",
                @"status": @"failure",
                @"started_at": @"1783801491",
                @"finished_at": @"1783801718",
                @"exit_code": @"1",
                @"trigger": @"manual",
                @"target": @"nas",
                @"destination": @"/Volumes/alexander/GoogleDrive-Backup/Customer Files",
                @"reason": @"nas_connection_lost",
                @"raw_error": @"token=very-secret customer-report.docx"
            };
            NSDictionary *setupHealth = @{
                @"overall": @"failure",
                @"dependencies": @{
                    @"status": @"failure",
                    @"missing": @[@"jq", @"flock", @"unknown-secret-tool"],
                    @"providerOutput": @"oauth_token=secret"
                },
                @"remote": @{
                    @"status": @"blocked",
                    @"detail": @"private-user@example.com"
                },
                @"destination": @{
                    @"status": @"ready",
                    @"detail": @"/Volumes/alexander/GoogleDrive-Backup"
                }
            };
            NSDictionary *appInfo = @{
                @"version": @"1.9.0",
                @"build": @"15",
                @"osVersion": @"macOS 15.5",
                @"architecture": @"arm64",
                @"home": @"/Users/private-user"
            };
            NSDictionary *serviceState = @{
                @"controllerLoaded": @YES,
                @"scheduleLoaded": @YES,
                @"raw": @"launchctl private output"
            };
            NSDictionary *scriptState = @{
                @"installed": @YES,
                @"executable": @YES,
                @"path": @"/usr/local/bin/backup-google-drive.sh"
            };

            SEL snapshotSelector = NSSelectorFromString(
                @"snapshotForConfig:summary:setupHealth:appInfo:serviceState:scriptState:");
            typedef NSDictionary *(*SnapshotMethod)(id, SEL, NSDictionary *, NSDictionary *,
                                                     NSDictionary *, NSDictionary *, NSDictionary *,
                                                     NSDictionary *);
            SnapshotMethod snapshotMethod = (SnapshotMethod)[builderClass
                methodForSelector:snapshotSelector];
            NSDictionary<NSString *, id> *snapshot = snapshotMethod(
                builderClass, snapshotSelector, config, summary, setupHealth,
                appInfo, serviceState, scriptState);

            Assert([snapshot[@"overall"] isEqualToString:@"attention"] &&
                   [snapshot[@"dependencies"][@"status"] isEqualToString:@"failure"] &&
                   [snapshot[@"remote"][@"status"] isEqualToString:@"blocked"] &&
                   [snapshot[@"destination"][@"status"] isEqualToString:@"ready"],
                   @"diagnostics distinguish ready, failed, and blocked checks");
            Assert([snapshot[@"dependencies"][@"missing"] isEqualToArray:@[@"flock", @"jq"]],
                   @"diagnostics expose only the known missing dependency names");
            Assert([snapshot[@"lastRun"][@"status"] isEqualToString:@"failure"] &&
                   [snapshot[@"lastRun"][@"reason"] isEqualToString:@"nas_connection_lost"] &&
                   [snapshot[@"lastRun"][@"trigger"] isEqualToString:@"manual"],
                   @"diagnostics preserve one safe actionable last-run reason");
            Assert([snapshot[@"schedule"][@"mode"] isEqualToString:@"daily"] &&
                   [snapshot[@"schedule"][@"loaded"] boolValue] &&
                   [snapshot[@"controller"][@"loaded"] boolValue] &&
                   [snapshot[@"script"][@"installed"] boolValue] &&
                   [snapshot[@"script"][@"executable"] boolValue],
                   @"diagnostics report scheduler, controller, and installed script state");

            SEL reportSelector = NSSelectorFromString(@"reportForSnapshot:");
            typedef NSString *(*ReportMethod)(id, SEL, NSDictionary *);
            ReportMethod reportMethod = (ReportMethod)[builderClass methodForSelector:reportSelector];
            NSString *report = reportMethod(builderClass, reportSelector, snapshot);
            NSArray<NSString *> *forbidden = @[
                @"private-user", @"secret-password", @"private-share",
                @"Customer Files", @"private-remote", @"very-secret",
                @"customer-report.docx", @"oauth_token", @"/Volumes/",
                @"/Users/", @"launchctl private output", @"/usr/local/bin"
            ];
            BOOL safe = YES;
            for (NSString *value in forbidden) {
                safe = safe && [report rangeOfString:value options:NSCaseInsensitiveSearch].location == NSNotFound;
            }
            Assert(safe && [report containsString:@"protocol=1"] &&
                   [report containsString:@"last_run.reason=nas_connection_lost"],
                   @"support report is useful without paths, credentials, file names, or raw output");

            NSDictionary *readySnapshot = snapshotMethod(builderClass, snapshotSelector,
                @{@"GDRIVE_BACKUP_TARGET": @"apfs", @"GDRIVE_BACKUP_SCHEDULE": @"manual",
                  @"GDRIVE_BACKUP_ENCRYPTION": @"apfs"},
                @{@"protocol": @"1", @"status": @"success", @"started_at": @"100",
                  @"finished_at": @"200", @"exit_code": @"0", @"trigger": @"manual"},
                @{@"overall": @"ready",
                  @"dependencies": @{@"status": @"ready"},
                  @"remote": @{@"status": @"ready"},
                  @"destination": @{@"status": @"ready"}},
                appInfo,
                @{@"controllerLoaded": @YES, @"scheduleLoaded": @NO},
                @{@"installed": @YES, @"executable": @YES});
            Assert([readySnapshot[@"overall"] isEqualToString:@"ready"] &&
                   [readySnapshot[@"schedule"][@"mode"] isEqualToString:@"manual"] &&
                   ![readySnapshot[@"schedule"][@"loaded"] boolValue],
                   @"manual setup can be healthy without a loaded schedule agent");

            NSDictionary *cryptSnapshot = snapshotMethod(builderClass, snapshotSelector,
                @{@"GDRIVE_BACKUP_TARGET": @"nas", @"GDRIVE_BACKUP_SCHEDULE": @"daily",
                  @"GDRIVE_BACKUP_ENCRYPTION": @"rclone-crypt",
                  @"GDRIVE_BACKUP_CRYPT_REMOTE": @"private-customer-crypt"},
                @{@"protocol": @"1", @"status": @"success", @"trigger": @"schedule"},
                @{@"overall": @"ready", @"dependencies": @{@"status": @"ready"},
                  @"remote": @{@"status": @"ready"},
                  @"destination": @{@"status": @"ready"}},
                appInfo, @{@"controllerLoaded": @YES, @"scheduleLoaded": @YES},
                @{@"installed": @YES, @"executable": @YES});
            NSString *cryptReport = reportMethod(builderClass, reportSelector, cryptSnapshot);
            Assert([cryptSnapshot[@"destination"][@"encryption"] isEqualToString:@"rclone-crypt"] &&
                   [cryptReport containsString:@"destination.encryption=rclone-crypt"] &&
                   ![cryptReport containsString:@"private-customer-crypt"],
                   @"diagnostics identify crypt protection without exposing its remote name");

            NSDictionary *malformed = snapshotMethod(builderClass, snapshotSelector,
                @{@"GDRIVE_BACKUP_TARGET": @"../../secret", @"GDRIVE_BACKUP_SCHEDULE": @"evil"},
                @{@"status": @"success\ncredential=secret", @"reason": @"token-secret"},
                @{@"dependencies": @{@"status": @"provider-secret"},
                  @"remote": @{@"status": @"provider-secret"},
                  @"destination": @{@"status": @"provider-secret"}},
                @{@"version": @"1.9.0\nsecret", @"build": @"15x", @"osVersion": @"private-os",
                  @"architecture": @"evil-arch"}, @{}, @{});
            NSString *malformedReport = reportMethod(builderClass, reportSelector, malformed);
            Assert(![malformedReport containsString:@"secret"] &&
                   [malformedReport containsString:@"unknown"],
                   @"malformed diagnostic inputs fail closed instead of entering the report");

            NSDictionary *injectedSnapshot = @{
                @"overall": @"attention\ncredential=direct-secret",
                @"app": @{ @"version": @"1.9.0\n/private/file.txt", @"build": @"15" },
                @"system": @{ @"osVersion": @"macOS 15.5", @"architecture": @"arm64" },
                @"dependencies": @{ @"status": @"ready", @"missing": @[@"token-secret"] },
                @"remote": @{ @"status": @"private-user@example.com" },
                @"destination": @{ @"status": @"ready", @"kind": @"nas", @"encryption": @"none" },
                @"schedule": @{ @"mode": @"manual", @"loaded": @NO },
                @"controller": @{ @"loaded": @YES },
                @"script": @{ @"installed": @YES, @"executable": @YES },
                @"lastRun": @{ @"status": @"success", @"reason": @"raw-log-secret" }
            };
            NSString *injectedReport = reportMethod(builderClass, reportSelector, injectedSnapshot);
            Assert(![injectedReport containsString:@"secret"] &&
                   ![injectedReport containsString:@"private-user"] &&
                   ![injectedReport containsString:@"/private/"] &&
                   [injectedReport containsString:@"unknown"],
                   @"report rendering revalidates snapshots instead of trusting its caller");
        }
    }

    if (failures > 0) {
        printf("%d diagnostics support test(s) failed.\n", failures);
        return 1;
    }
    printf("All diagnostics support tests passed.\n");
    return 0;
}
