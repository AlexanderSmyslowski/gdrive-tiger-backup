#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^GDTSetupCommandAvailability)(NSString *command);
typedef NSDictionary<NSString *, id> * _Nonnull (^GDTSetupCommandRunner)(NSString *command,
                                                                          NSArray<NSString *> *arguments);

/// Terminal command that installs the missing helper tools, including
/// Homebrew itself when it is not installed yet.
FOUNDATION_EXPORT NSString *GDTSetupInstallCommand(BOOL homebrewAvailable,
                                                   NSArray<NSString *> *missingCommands);

/// Google OAuth "Desktop app" client from the JSON file that the Google Cloud
/// console downloads: @{clientID, clientSecret}. Returns nil for anything
/// else; *reason is then "notDesktop" (a web or other client type) or
/// "invalid".
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
GDTGoogleOAuthClientFromJSONData(NSData *data, NSString * _Nullable * _Nullable reason);

/// Newest regular file named client_secret*.json directly in directory whose
/// modification date is at or after notBefore, or nil.
FOUNDATION_EXPORT NSString * _Nullable GDTNewestGoogleOAuthClientFile(NSString *directory,
                                                                      NSDate *notBefore,
                                                                      NSFileManager *fileManager);

@interface GDTSetupHealthChecker : NSObject

@property(nonatomic, copy, nullable) GDTSetupCommandAvailability commandAvailability;
@property(nonatomic, copy, nullable) GDTSetupCommandRunner commandRunner;
@property(nonatomic, strong) NSFileManager *fileManager;
/// Runs the long, browser-based Google sign-in. Separate from
/// commandRunner because the sign-in waits for the user for minutes.
@property(nonatomic, copy, nullable) GDTSetupCommandRunner interactiveCommandRunner;
/// Where the rclone in use comes from: "homebrew", "bundled" or "other".
@property(nonatomic, copy, nullable) NSString * _Nullable (^rcloneSourceProvider)(void);

+ (instancetype)productionChecker;
- (NSDictionary<NSString *, id> *)snapshotForConfig:(NSDictionary<NSString *, NSString *> *)config;
/// YES when Homebrew is installed.
- (BOOL)homebrewAvailable;
/// Lock file the backup engine holds exclusively while it runs. When set, an
/// existing remote is only changed while this process holds that lock, so a
/// running backup can never write its old token back next to the new client.
@property(nonatomic, copy, nullable) NSString *backupLockPath;
/// Connects the read-only Google Drive remote named in the config with the
/// user's own OAuth Desktop client instead of rclone's shared one, which
/// Google is retiring. rclone opens Google's sign-in page in the browser.
/// An existing remote is replaced only after a temporary remote signed in and
/// passed a read check, so a cancelled sign-in leaves it untouched.
/// Returns @{status, reason}; status 0 means connected. reason is one of
/// connected, invalidClient, signInFailed, verifyFailed, backupRunning,
/// updateFailed.
- (NSDictionary<NSString *, id> *)connectGoogleDriveForConfig:(NSDictionary<NSString *, NSString *> *)config
                                                      clientID:(NSString *)clientID
                                                  clientSecret:(NSString *)clientSecret;

@end

NS_ASSUME_NONNULL_END
