#ifndef GDT_SCHEDULED_BACKUP_SUPPORT_H
#define GDT_SCHEDULED_BACKUP_SUPPORT_H

#include <errno.h>
#include <pwd.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <time.h>

static volatile sig_atomic_t GDTScheduledHangup, GDTScheduledInterrupt, GDTScheduledTerminate;

static void GDTScheduledSignal(int signalNumber) {
    if (signalNumber == SIGHUP) GDTScheduledHangup = 1;
    if (signalNumber == SIGINT) GDTScheduledInterrupt = 1;
    if (signalNumber == SIGTERM) GDTScheduledTerminate = 1;
}

static inline int GDTScheduledPendingSignal(void) {
    if (GDTScheduledTerminate) { GDTScheduledTerminate = 0; return SIGTERM; }
    if (GDTScheduledInterrupt) { GDTScheduledInterrupt = 0; return SIGINT; }
    if (GDTScheduledHangup) { GDTScheduledHangup = 0; return SIGHUP; }
    return 0;
}

// This entry point runs before AppKit and keeps the native executable alive as
// the responsible parent. It cannot select an engine or profile from argv/env.
static inline int GDTHandleScheduledBackupArguments(int argc, const char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "--run-scheduled-backup") != 0) return -1;
    if (argc != 2) {
        fputs("Usage: GDriveBackupTiger --run-scheduled-backup\n", stderr);
        return 64;
    }
    const char *oneShotKeys[] = {
        "GDRIVE_BACKUP_RUN_TARGET", "GDRIVE_BACKUP_RUN_VOLUME_UUID",
        "GDRIVE_BACKUP_APPROVE_VOLUME_CREATION"
    };
    for (size_t i = 0; i < sizeof(oneShotKeys) / sizeof(oneShotKeys[0]); i++) {
        if (getenv(oneShotKeys[i]) != NULL) {
            fputs("Scheduled backups reject one-shot destination approvals.\n", stderr);
            return 64;
        }
    }
    if (getuid() != geteuid() || getgid() != getegid()) return 77;

    // HOME comes from the account database, not the launchd manager environment.
    // Build a fresh allowlist so BASH_ENV, exported functions, DYLD_* and engine
    // test/config/helper overrides never reach Bash or the saved-profile loader.
    struct passwd account, *found = NULL;
    char accountBuffer[16384];
    if (getpwuid_r(getuid(), &account, accountBuffer, sizeof(accountBuffer), &found) != 0 ||
        !found || !account.pw_dir || account.pw_dir[0] != '/') return 78;
    char *home = NULL;
    if (asprintf(&home, "HOME=%s", account.pw_dir) < 0) return 71;
    char *environment[] = {
        home,
        "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/libexec/gdrive-tiger-backup/bin",
        "GDRIVE_BACKUP_TRIGGER=schedule",
        "BACKUP_ASSUME_YES=1",
        "BACKUP_PROGRESS_FOREGROUND=0",
        NULL
    };
    char *arguments[] = {"/bin/bash", "/usr/local/bin/backup-google-drive.sh", "--run", NULL};

    // Native account/framework code can have other threads. Handlers only set
    // flags, so delivery on any thread is safe; the owning thread forwards to
    // the group while its unreaped child still reserves the PID/group ID.
    const int signals[] = {SIGHUP, SIGINT, SIGTERM, SIGCHLD};
    struct sigaction action = {0}, previous[4];
    action.sa_handler = GDTScheduledSignal;
    sigemptyset(&action.sa_mask);
    sigset_t watched, oldMask, empty;
    sigemptyset(&watched);
    sigemptyset(&empty);
    for (size_t i = 0; i < 4; i++) sigaddset(&watched, signals[i]);
    GDTScheduledHangup = GDTScheduledInterrupt = GDTScheduledTerminate = 0;
    size_t installed = 0;
    for (; installed < 4; installed++) {
        if (sigaction(signals[installed], &action, &previous[installed]) != 0) break;
    }
    if (installed != 4 || sigprocmask(SIG_UNBLOCK, &watched, &oldMask) != 0) {
        while (installed) { installed--; sigaction(signals[installed], &previous[installed], NULL); }
        free(home);
        return 71;
    }

    posix_spawnattr_t attributes;
    int error = posix_spawnattr_init(&attributes);
    int attributesReady = error == 0;
    if (!error) error = posix_spawnattr_setpgroup(&attributes, 0);
    if (!error) error = posix_spawnattr_setsigmask(&attributes, &empty);
    if (!error) error = posix_spawnattr_setsigdefault(&attributes, &watched);
    if (!error) error = posix_spawnattr_setflags(&attributes,
        POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    int stopSignal = GDTScheduledPendingSignal();
    pid_t child = -1;
    if (!error && !stopSignal) error = posix_spawn(&child, "/bin/bash", NULL, &attributes, arguments, environment);
    if (attributesReady) posix_spawnattr_destroy(&attributes);
    free(home);

    int status = 0;
    int result = stopSignal ? 128 + stopSignal : (error == ENOENT ? 127 : (error == EACCES ? 126 : 71));
    if (!error && child > 0) {
        for (;;) {
            int pending;
            while ((pending = GDTScheduledPendingSignal()) != 0) {
                if (!stopSignal) stopSignal = pending;
                kill(-child, pending);
            }
            pid_t waited = waitpid(child, &status, WNOHANG);
            if (waited == child) {
                result = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
                if (!stopSignal) stopSignal = GDTScheduledPendingSignal();
                if (result == 0 && stopSignal) result = 128 + stopSignal;
                break;
            }
            if (waited < 0 && errno != EINTR) {
                // Ownership is no longer provable: never signal a reused PID.
                result = 71;
                break;
            }
            // Bounded waiting also works when a runtime thread receives the
            // signal instead of interrupting this thread's system call.
            struct timespec interval = {0, 50 * 1000 * 1000};
            nanosleep(&interval, NULL);
        }
    } else if (error) {
        fprintf(stderr, "Scheduled backup launch failed: %s\n", strerror(error));
    }
    for (size_t i = 0; i < 4; i++) sigaction(signals[i], &previous[i], NULL);
    sigprocmask(SIG_SETMASK, &oldMask, NULL);
    return result;
}
#endif
