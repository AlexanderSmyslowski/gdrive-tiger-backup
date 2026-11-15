#import <Cocoa/Cocoa.h>
#include <spawn.h>
#include <signal.h>
#include <pwd.h>
#include <sys/wait.h>
#include <mach-o/dyld.h>

static const char *fixtureMode;
static char fixtureExecutable[4096];
static char fixtureTrace[4096];
static int spawnError;
static int signalDuringSpawn;
static int spawnCalls;

static void Require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

// Only this test translation unit substitutes the external launch boundary.
// The real worker chooses argv/env/attributes; every actual child is this safe
// fixture executable, so neither installed engine nor user config is touched.
static int FixtureSpawn(pid_t *pid, const char *path,
                        const posix_spawn_file_actions_t *actions,
                        const posix_spawnattr_t *attributes,
                        char *const arguments[], char *const environment[]) {
    spawnCalls++;
    Require(strcmp(path, "/bin/bash") == 0 &&
            strcmp(arguments[0], "/bin/bash") == 0 &&
            strcmp(arguments[1], "/usr/local/bin/backup-google-drive.sh") == 0 &&
            strcmp(arguments[2], "--run") == 0 && !arguments[3], "fixed engine command");
    struct passwd *account = getpwuid(getuid());
    char expectedHome[4096];
    snprintf(expectedHome, sizeof(expectedHome), "HOME=%s", account->pw_dir);
    const char *expected[] = {expectedHome,
        "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "GDRIVE_BACKUP_TRIGGER=schedule", "BACKUP_ASSUME_YES=1", "BACKUP_PROGRESS_FOREGROUND=0"};
    int count = 0;
    for (; environment[count]; count++) {
        BOOL allowed = NO;
        for (size_t i = 0; i < sizeof(expected)/sizeof(expected[0]); i++)
            if (strcmp(environment[count], expected[i]) == 0) allowed = YES;
        Require(allowed, "child environment contains only trusted schedule values");
    }
    Require(count == 5, "complete minimal environment");
    if (spawnError == ENOENT || spawnError == EACCES)
        return posix_spawn(pid, spawnError == ENOENT ? "/nonexistent/gdrive-scheduled-fixture" : "/",
                           actions, attributes, arguments, environment);
    if (spawnError) return spawnError;
    if (!strcmp(fixtureMode, "missing-script")) {
        char *missing[] = {"/bin/bash", "/nonexistent/gdrive-scheduled-fixture.sh", NULL};
        return posix_spawn(pid, "/bin/bash", actions, attributes, missing, environment);
    }
    if (signalDuringSpawn) kill(getpid(), signalDuringSpawn);
    char owner[32];
    snprintf(owner, sizeof(owner), "%d", getpid());
    char *fixtureArguments[] = {fixtureExecutable, "--fixture", (char *)fixtureMode, fixtureTrace, owner, NULL};
    int result = posix_spawn(pid, fixtureExecutable, actions, attributes, fixtureArguments, environment);
    return result;
}

static int FixtureSpawnFlags(posix_spawnattr_t *attributes, short flags) {
    int result = posix_spawnattr_setflags(attributes, flags);
    if (signalDuringSpawn < 0) kill(getpid(), -signalDuringSpawn);
    return result;
}

#define posix_spawnattr_setflags FixtureSpawnFlags
#define posix_spawn FixtureSpawn
#define main GDTApplicationMain
#import "../macos/GDriveBackupTiger/main.m"
#undef main
#undef posix_spawn
#undef posix_spawnattr_setflags

static void Trace(const char *path, const char *text) {
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0 || write(fd, text, strlen(text)) != (ssize_t)strlen(text)) _exit(95);
    close(fd);
}

static int FixtureMain(const char *mode, const char *trace, pid_t owner) {
    alarm(4);
    if (getppid() != owner || getpgrp() != getpid()) return 96;
    if (!strcmp(mode, "stop-success")) {
        signal(SIGTERM, SIG_IGN);
        kill(owner, SIGTERM);
        usleep(200000);
        return 0;
    }
    if (!strncmp(mode, "exit-", 5)) return atoi(mode + 5);
    if (!strcmp(mode, "killed")) { raise(SIGKILL); return 99; }
    int signalNumber = atoi(mode);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGHUP); sigaddset(&signals, SIGINT); sigaddset(&signals, SIGTERM);
    sigprocmask(SIG_BLOCK, &signals, NULL);
    int readiness[2];
    if (pipe(readiness) != 0) return 97;
    pid_t descendant = fork();
    if (descendant == 0) {
        alarm(4);
        close(readiness[0]);
        if (write(readiness[1], "R", 1) != 1) _exit(97);
        close(readiness[1]);
        int received = 0;
        if (sigwait(&signals, &received)) _exit(97);
        Trace(trace, "grandchild received group signal\n");
        _exit(128 + received);
    }
    close(readiness[1]);
    char ready;
    if (descendant < 0 || read(readiness[0], &ready, 1) != 1) return 97;
    close(readiness[0]);
    Trace(trace, "child ready\n");
    // Zero is the spawn-window test: the worker already has a pending TERM.
    if (signalNumber) kill(owner, signalNumber);
    int received = 0;
    if (sigwait(&signals, &received)) return 97;
    int status = 0;
    if (waitpid(descendant, &status, 0) != descendant || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 128 + received) return 98;
    Trace(trace, "child reaped grandchild; terminal state written\n");
    return 128 + received;
}

static int RunWorker(const char *mode, int launchError, int startupSignal, BOOL ignoreTerm) {
    fixtureMode = mode; spawnError = launchError; signalDuringSpawn = startupSignal;
    char errorArgument[16], signalArgument[16];
    snprintf(errorArgument, sizeof(errorArgument), "%d", launchError);
    snprintf(signalArgument, sizeof(signalArgument), "%d", startupSignal);
    char *workerArguments[] = {fixtureExecutable, "--worker", (char *)mode, errorArgument,
        signalArgument, ignoreTerm ? "1" : "0", fixtureTrace, NULL};
    pid_t worker = fork();
    Require(worker >= 0, "fork isolated native worker");
    if (!worker) {
        execv(fixtureExecutable, workerArguments);
        _exit(94);
    }
    int status = 0;
    for (int i = 0; i < 600; i++) {
        pid_t result = waitpid(worker, &status, WNOHANG);
        if (result == worker) {
            int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            fprintf(stderr, "fixture %s returned %d\n", mode, code);
            return code;
        }
        usleep(10000);
    }
    kill(worker, SIGKILL);
    waitpid(worker, &status, 0);
    return 99;
}

int main(int argc, const char *argv[]) {
    if (argc == 5 && !strcmp(argv[1], "--fixture")) return FixtureMain(argv[2], argv[3], (pid_t)atoi(argv[4]));
    if (argc == 7 && !strcmp(argv[1], "--worker")) {
        uint32_t size = sizeof(fixtureExecutable);
        if (_NSGetExecutablePath(fixtureExecutable, &size)) return 94;
        snprintf(fixtureTrace, sizeof(fixtureTrace), "%s", argv[6]);
        fixtureMode = argv[2]; spawnError = atoi(argv[3]); signalDuringSpawn = atoi(argv[4]);
        if (atoi(argv[5])) signal(SIGTERM, SIG_IGN);
        const char *hostile[] = {"HOME", "PATH", "BASH_ENV", "ENV", "SHELLOPTS", "BASH_FUNC_fake%%", "DYLD_INSERT_LIBRARIES", "GDRIVE_BACKUP_CONFIG", "GDRIVE_BACKUP_CONFIG_DIR", "GDRIVE_BACKUP_PROFILE_ID", "GDRIVE_BACKUP_PATH", "GDRIVE_BACKUP_NAS_MOUNT_HELPER", "GDRIVE_BACKUP_DEST_ROOT", "GDRIVE_BACKUP_LOCK", "GDRIVE_BACKUP_PAUSED", "GDRIVE_BACKUP_TEST_ENGINE", "BACKUP_ASSUME_YES", "BACKUP_PROGRESS_FOREGROUND", "GDRIVE_BACKUP_TRIGGER"};
        for (size_t i = 0; i < sizeof(hostile)/sizeof(hostile[0]); i++) setenv(hostile[i], "/untrusted/override", 1);
        const char *args[] = {"GDriveBackupTiger", "--run-scheduled-backup", NULL};
        const int monitored[] = {SIGHUP, SIGINT, SIGTERM, SIGCHLD};
        struct sigaction prior[4], after;
        sigset_t priorMask, afterMask;
        for (size_t i = 0; i < 4; i++) sigaction(monitored[i], NULL, &prior[i]);
        sigprocmask(SIG_SETMASK, NULL, &priorMask);
        int result = GDTApplicationMain(2, args);
        Require(NSApp == nil, "worker completes before UI initialization");
        for (size_t i = 0; i < 4; i++) {
            sigaction(monitored[i], NULL, &after);
            Require(after.sa_handler == prior[i].sa_handler, "worker restores signal dispositions");
        }
        sigprocmask(SIG_SETMASK, NULL, &afterMask);
        for (int i = 1; i < NSIG; i++) Require(sigismember(&priorMask, i) == sigismember(&afterMask, i), "worker restores signal mask");
        if (signalDuringSpawn < 0) Require(spawnCalls == 0, "pending stop prevents child launch");
        return result;
    }
    @autoreleasepool {
        uint32_t executableSize = sizeof(fixtureExecutable);
        Require(_NSGetExecutablePath(fixtureExecutable, &executableSize) == 0, "fixture executable location");
        char directory[] = "/tmp/gdrive-native-schedule.XXXXXX";
        Require(mkdtemp(directory) != NULL, "isolated trace directory");
        snprintf(fixtureTrace, sizeof(fixtureTrace), "%s/trace", directory);
        AppDelegate *delegate = [[AppDelegate alloc] init];
        for (NSString *mode in @[@"daily", @"hourly", @"login"]) {
            NSData *data = [delegate schedulePlistDataForMode:mode error:nil];
            NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
            Require([plist[@"ProgramArguments"] isEqual:@[@"/Applications/GDrive Backup Tiger.app/Contents/MacOS/GDriveBackupTiger", @"--run-scheduled-backup"]], "every schedule enters native worker");
            Require([plist[@"AssociatedBundleIdentifiers"] isEqual:@[@"com.commcats.gdrivebackup.tiger"]], "schedule associates native bundle");
            NSArray *dailyIntervals = plist[@"StartCalendarInterval"];
            Require([mode isEqual:@"daily"] ? ([dailyIntervals isKindOfClass:NSArray.class] && dailyIntervals.count == 24 && [dailyIntervals.firstObject isEqual:@{@"Hour":@20,@"Minute":@0}] && [[NSSet setWithArray:[dailyIntervals valueForKey:@"Hour"]] count] == 24) : !dailyIntervals, "daily window opens at 20:00 with hourly catch-up entries only for daily mode");
            Require([mode isEqual:@"hourly"] ? [plist[@"StartInterval"] isEqual:@3600] : !plist[@"StartInterval"], "hourly timing preserved only for hourly mode");
            Require([mode isEqual:@"login"] ? [plist[@"RunAtLoad"] isEqual:@YES] : !plist[@"RunAtLoad"], "login timing preserved only for login mode");
        }
        puts("PASS: daily/hourly/login generator and bundle association");
        Require(NSApp == nil, "test does not initialize AppKit");
        const char *extra[] = {"app", "--run-scheduled-backup", "--profile=other", NULL};
        Require(GDTApplicationMain(3, extra) == 64 && spawnCalls == 0 && NSApp == nil, "reject extra CLI args before UI or spawn");
        const char *valid[] = {"app", "--run-scheduled-backup", NULL};
        const char *approvals[] = {"GDRIVE_BACKUP_RUN_TARGET", "GDRIVE_BACKUP_RUN_VOLUME_UUID", "GDRIVE_BACKUP_APPROVE_VOLUME_CREATION"};
        for (size_t i = 0; i < sizeof(approvals)/sizeof(approvals[0]); i++) {
            setenv(approvals[i], "1", 1);
            Require(GDTApplicationMain(2, valid) == 64 && spawnCalls == 0 && NSApp == nil, "reject one-shot approvals before spawn/UI");
            unsetenv(approvals[i]);
        }
        Require(RunWorker("exit-0", 0, 0, NO) == 0, "successful child exit and sanitized environment");
        Require(RunWorker("exit-69", 0, 0, NO) == 69, "engine failure preserved");
        Require(RunWorker("missing-script", 0, 0, NO) == 127, "missing-script shell status preserved");
        Require(RunWorker("exit-0", ENOENT, 0, NO) == 127, "spawn missing executable failure");
        Require(RunWorker("exit-0", EACCES, 0, NO) == 126, "spawn permission failure");
        Require(RunWorker("exit-0", EAGAIN, 0, NO) == 71, "spawn resource failure");
        Require(RunWorker("killed", 0, 0, NO) == 137, "child signal failure preserved");
        puts("PASS: strict CLI, fixed command, hostile environment, launch and exit errors");
        for (NSNumber *signalNumber in @[@SIGHUP, @SIGINT, @SIGTERM]) {
            char mode[16]; snprintf(mode, sizeof(mode), "%d", signalNumber.intValue);
            Require(RunWorker(mode, 0, 0, NO) == 128 + signalNumber.intValue, "forward signal to child and grandchild, wait for terminal cleanup");
        }
        NSString *trace = [NSString stringWithContentsOfFile:@(fixtureTrace) encoding:NSUTF8StringEncoding error:nil];
        Require([[trace componentsSeparatedByString:@"grandchild received group signal"] count] == 4 &&
                [[trace componentsSeparatedByString:@"child reaped grandchild; terminal state written"] count] == 4, "all three cancellations clean process tree before worker exits");
        Require(RunWorker("0", 0, SIGTERM, NO) == 143, "signal pending during spawn is delivered after group exists");
        Require(RunWorker("15", 0, 0, YES) == 143, "inherited ignored termination signal must not disable cancellation");
        Require(RunWorker("exit-0", 0, -SIGTERM, NO) == 143, "stop before spawn prevents child launch");
        Require(RunWorker("stop-success", 0, 0, NO) == 143, "child success cannot erase a stop request");
        puts("PASS: process groups, HUP/INT/TERM, child reaping, signal restoration and startup races");
        Require([NSFileManager.defaultManager removeItemAtPath:@(directory) error:nil], "scratch fixture cleanup");
    }
    return 0;
}
