// Automatic updates: daily check, offer, verified download, installation with
// the macOS administrator prompt, and a report after the restart.
// Included inside @implementation AppDelegate.

static NSString * const GDTUpdateAutomaticChecksKey = @"GDTAutomaticUpdateChecks";
static NSString * const GDTUpdateLastCheckKey = @"GDTUpdateLastAutomaticCheck";
static NSString * const GDTUpdateOfferedVersionKey = @"GDTUpdateOfferedVersion";
static NSTimeInterval const GDTUpdateCheckInterval = 24.0 * 60.0 * 60.0;

- (BOOL)automaticUpdateChecksEnabled {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:GDTUpdateAutomaticChecksKey];
    return value ? [value boolValue] : YES;
}

- (void)toggleAutomaticUpdateChecks:(id)sender {
    (void)sender;
    [NSUserDefaults.standardUserDefaults setBool:![self automaticUpdateChecksEnabled]
                                          forKey:GDTUpdateAutomaticChecksKey];
    [self buildMainMenu];
    if (self.statusItem && self.lastOverviewSnapshot) {
        self.statusItem.menu = [self statusMenuForSnapshot:self.lastOverviewSnapshot];
        self.statusItem.menu.delegate = self;
    }
}

- (NSString *)updateWorkDirectory {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    return [caches stringByAppendingPathComponent:@"com.commcats.gdrivebackup.tiger/Updates"];
}

- (NSString *)updateResultPath {
    return [[self updateWorkDirectory] stringByAppendingPathComponent:@"install-result"];
}

// Only the menu bar agent checks on its own, so one Mac asks GitHub at most
// once a day however many windows are open.
- (void)scheduleAutomaticUpdateChecks {
    if (!self.menubarOnlyMode || self.updateCheckTimer) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf runAutomaticUpdateCheckIfDue];
    });
    self.updateCheckTimer = [NSTimer scheduledTimerWithTimeInterval:6.0 * 60.0 * 60.0
                                                             target:self
                                                           selector:@selector(runAutomaticUpdateCheckIfDue)
                                                           userInfo:nil
                                                            repeats:YES];
    self.updateCheckTimer.tolerance = 30.0 * 60.0;
}

- (void)runAutomaticUpdateCheckIfDue {
    if (![self automaticUpdateChecksEnabled] || self.updateChecking || self.updateInstallState.length) return;
    NSDate *last = [NSUserDefaults.standardUserDefaults objectForKey:GDTUpdateLastCheckKey];
    if ([last isKindOfClass:NSDate.class] && -last.timeIntervalSinceNow < GDTUpdateCheckInterval) return;
    self.updateChecking = YES;
    if (!self.updateChecker) self.updateChecker = [[GDTUpdateChecker alloc] init];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";
    __weak typeof(self) weakSelf = self;
    [self.updateChecker checkCurrentVersion:version completion:^(NSDictionary *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.updateChecking = NO;
            NSString *status = result[@"status"];
            if ([status isEqualToString:@"unavailable"]) return;  // retry at the next timer tick
            [NSUserDefaults.standardUserDefaults setObject:NSDate.date forKey:GDTUpdateLastCheckKey];
            if (![status isEqualToString:@"updateAvailable"]) return;
            // Offer each version once automatically; the menu always offers it again.
            NSString *offered = [NSUserDefaults.standardUserDefaults stringForKey:GDTUpdateOfferedVersionKey];
            if ([offered isEqualToString:result[@"version"]]) return;
            [NSUserDefaults.standardUserDefaults setObject:result[@"version"] forKey:GDTUpdateOfferedVersionKey];
            [strongSelf presentUpdateResult:result];
        });
    }];
}

- (BOOL)backupIsRunningForUpdate {
    if ([self.lastOverviewSnapshot[@"status"] isEqualToString:@"running"] || self.overviewLaunchPending) return YES;
    NSString *summaryPath = GDTBackupSummaryPathForConfig(GDTReadConfigDictionary());
    return [GDTBackupSummaryStatusAtPath(summaryPath) isEqualToString:@"running"];
}

- (void)setUpdateInstallState:(NSString *)state {
    _updateInstallState = [state copy];
    [self buildMainMenu];
    if (self.statusItem && self.lastOverviewSnapshot) {
        self.statusItem.menu = [self statusMenuForSnapshot:self.lastOverviewSnapshot];
        self.statusItem.menu.delegate = self;
    }
}

- (void)presentUpdateFailure:(NSString *)reason {
    NSString *language = self.language ?: @"en";
    NSDictionary<NSString *, NSString *> *keys = @{
        @"network": @"updateFailedNetwork",
        @"checksum_missing": @"updateFailedChecksum",
        @"checksum_mismatch": @"updateFailedChecksum",
        @"package": @"updateFailedPackage",
        @"unsigned": @"updateFailedSignature",
        @"untrusted_signature": @"updateFailedSignature",
        @"installer": @"updateFailedInstaller"
    };
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(language, @"updateFailedTitle");
    alert.informativeText = [NSString stringWithFormat:@"%@ %@",
        T(language, keys[reason] ?: @"updateFailedNetwork"), T(language, @"updateFailedNothingChanged")];
    [alert addButtonWithTitle:T(language, @"done")];
    [alert addButtonWithTitle:T(language, @"updateOpenRelease")];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertSecondButtonReturn) [self openOfficialReleasePage:nil];
}

- (void)installUpdateVersion:(NSString *)version {
    if (self.updateInstallState.length) return;
    NSString *language = self.language ?: @"en";
    if ([self backupIsRunningForUpdate]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = T(language, @"updateBusyTitle");
        alert.informativeText = T(language, @"updateBusyMessage");
        [alert addButtonWithTitle:T(language, @"done")];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
        return;
    }
    self.updateInstallState = @"downloading";
    if (!self.updateDownloader) self.updateDownloader = [[GDTUpdateDownloader alloc] init];
    NSString *directory = [[self updateWorkDirectory] stringByAppendingPathComponent:version];
    __weak typeof(self) weakSelf = self;
    [self.updateDownloader downloadVersion:version toDirectory:directory
                                completion:^(NSString *packagePath, NSString *failureReason) {
        NSString *problem = failureReason;
        if (packagePath && !problem) problem = [weakSelf updatePackageProblemAtPath:packagePath];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (problem) {
                strongSelf.updateInstallState = nil;
                [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
                [strongSelf presentUpdateFailure:problem];
                return;
            }
            [strongSelf launchPrivilegedInstallOfPackage:packagePath version:version];
        });
    }];
}

// Runs off the main thread: the package must contain this app and, once the
// project signs releases, carry the project's Developer ID signature.
- (NSString *)updatePackageProblemAtPath:(NSString *)packagePath {
    int status = 0;
    NSString *payload = RunCommand(@"/usr/sbin/pkgutil", @[@"--payload-files", packagePath], nil, &status);
    if (status != 0 ||
        ![payload containsString:@"./Applications/GDrive Backup Tiger.app/Contents/Info.plist"] ||
        ![payload containsString:@"./usr/local/bin/backup-google-drive.sh"]) {
        return @"package";
    }
    NSString *signature = RunCommand(@"/usr/sbin/pkgutil", @[@"--check-signature", packagePath], nil, &status);
    return GDTUpdateSignatureProblem(status, signature ?: @"", GDTUpdateTrustedTeamID);
}

// The package's postinstall restarts the app's launch agent, which ends this
// process. The installer therefore runs in its own session so it survives
// that restart, and reports its exit status in a file the next launch reads.
- (void)launchPrivilegedInstallOfPackage:(NSString *)packagePath version:(NSString *)version {
    self.updateInstallState = @"installing";
    NSString *resultPath = [self updateResultPath];
    [NSFileManager.defaultManager removeItemAtPath:resultPath error:nil];
    NSString *script =
        @"/usr/bin/osascript"
        @" -e 'on run argv'"
        @" -e 'do shell script \"/usr/sbin/installer -pkg \" & quoted form of (item 1 of argv) & \" -target /\" with administrator privileges'"
        @" -e 'end run' \"$1\" >/dev/null 2>\"$3.err\";"
        @" status=$?; cancelled=0;"
        @" /usr/bin/grep -q -- '(-128)' \"$3.err\" && cancelled=1;"
        @" /bin/rm -f \"$3.err\";"
        @" printf 'version=%s\\nstatus=%s\\ncancelled=%s\\n' \"$2\" \"$status\" \"$cancelled\" >\"$3.tmp\""
        @" && /bin/mv -f \"$3.tmp\" \"$3\"";
    const char *argv[] = {
        "/bin/sh", "-c", script.fileSystemRepresentation, "gdt-update",
        packagePath.fileSystemRepresentation, version.UTF8String, resultPath.fileSystemRepresentation, NULL
    };
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSID);
    pid_t pid = 0;
    int spawned = posix_spawn(&pid, "/bin/sh", NULL, &attributes, (char * const *)argv, environ);
    posix_spawnattr_destroy(&attributes);
    if (spawned != 0) {
        self.updateInstallState = nil;
        [self presentUpdateFailure:@"installer"];
        return;
    }
    self.updateInstallPID = pid;
    self.updateResultTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                            selector:@selector(pollUpdateInstallResult)
                                                            userInfo:nil repeats:YES];
}

- (NSDictionary<NSString *, NSString *> *)readUpdateResult {
    NSString *content = [NSString stringWithContentsOfFile:[self updateResultPath]
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (!content.length || content.length > 256) return nil;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location != NSNotFound) {
            values[[line substringToIndex:equals.location]] = [line substringFromIndex:NSMaxRange(equals)];
        }
    }
    return values;
}

- (void)pollUpdateInstallResult {
    if (self.updateInstallPID > 0) {
        int status = 0;
        if (waitpid(self.updateInstallPID, &status, WNOHANG) == self.updateInstallPID) self.updateInstallPID = 0;
    }
    NSDictionary *result = [self readUpdateResult];
    if (!result) return;
    [self.updateResultTimer invalidate];
    self.updateResultTimer = nil;
    self.updateInstallState = nil;
    if ([result[@"status"] isEqualToString:@"0"]) {
        // Normally the restarted agent has already replaced this process. A
        // window opened by the user is left running on the old code, so it
        // reopens itself from the new app.
        [self finishInstalledUpdateRelaunching:YES];
        return;
    }
    [NSFileManager.defaultManager removeItemAtPath:[self updateWorkDirectory] error:nil];
    // A dismissed password prompt is the user's choice, not a failure.
    if (![result[@"cancelled"] isEqualToString:@"1"]) [self presentUpdateFailure:@"installer"];
}

- (void)finishInstalledUpdateRelaunching:(BOOL)relaunch {
    if (!relaunch || self.menubarOnlyMode) return;
    NSString *appPath = @"/Applications/GDrive Backup Tiger.app";
    const char *argv[] = { "/bin/sh", "-c", "/bin/sleep 1; /usr/bin/open -n \"$1\"", "gdt-relaunch",
                           appPath.fileSystemRepresentation, NULL };
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSID);
    pid_t pid = 0;
    posix_spawn(&pid, "/bin/sh", NULL, &attributes, (char * const *)argv, environ);
    posix_spawnattr_destroy(&attributes);
    [NSApp terminate:nil];
}

// After the restart: confirm a successful update once and clean up. The
// package's postinstall starts this new process a moment before the old
// installer process writes its result, so wait for it while the download of
// this version is still present (at most two minutes).
- (void)reportInstalledUpdateIfNeeded {
    [self reportInstalledUpdateAttempt:0];
}

- (void)reportInstalledUpdateAttempt:(NSUInteger)attempt {
    NSDictionary *result = [self readUpdateResult];
    if (!result) {
        NSString *current = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
        BOOL justInstalled = current.length && [NSFileManager.defaultManager fileExistsAtPath:
            [[self updateWorkDirectory] stringByAppendingPathComponent:current]];
        if (justInstalled && attempt < 60) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf reportInstalledUpdateAttempt:attempt + 1];
            });
        } else if (justInstalled) {
            [NSFileManager.defaultManager removeItemAtPath:[self updateWorkDirectory] error:nil];
        }
        return;
    }
    NSString *current = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    BOOL installed = [result[@"status"] isEqualToString:@"0"] && [result[@"version"] isEqualToString:current];
    [NSFileManager.defaultManager removeItemAtPath:[self updateWorkDirectory] error:nil];
    if (!installed || !self.menubarOnlyMode) return;
    NSString *language = self.language ?: @"en";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = T(language, @"updateInstalledTitle");
    alert.informativeText = [NSString stringWithFormat:T(language, @"updateInstalledMessage"), current];
    [alert addButtonWithTitle:T(language, @"done")];
    [alert addButtonWithTitle:T(language, @"updateWhatsNew")];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertSecondButtonReturn) [self openOfficialReleasePage:nil];
}

- (NSString *)updateMenuTitleKey {
    if ([self.updateInstallState isEqualToString:@"downloading"]) return @"updateDownloading";
    if ([self.updateInstallState isEqualToString:@"installing"]) return @"updateInstalling";
    return self.updateChecking ? @"updateChecking" : @"updateCheck";
}

- (NSMenuItem *)automaticUpdateMenuItem {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:T(self.language ?: @"en", @"updateAutomaticChecks")
                                                  action:@selector(toggleAutomaticUpdateChecks:)
                                           keyEquivalent:@""];
    item.target = self;
    item.state = [self automaticUpdateChecksEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    return item;
}
