#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^GDTSetupCommandAvailability)(NSString *command);
typedef NSDictionary<NSString *, id> * _Nonnull (^GDTSetupCommandRunner)(NSString *command,
                                                                          NSArray<NSString *> *arguments);

/// Terminal command that installs the missing helper tools, including
/// Homebrew itself when it is not installed yet.
FOUNDATION_EXPORT NSString *GDTSetupInstallCommand(BOOL homebrewAvailable,
                                                   NSArray<NSString *> *missingCommands);

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
/// Creates the read-only Google Drive remote named in the config. rclone
/// opens Google's sign-in page in the browser and returns after consent.
/// Returns @{status, output}; status 0 means connected.
- (NSDictionary<NSString *, id> *)connectGoogleDriveForConfig:(NSDictionary<NSString *, NSString *> *)config;

@end

NS_ASSUME_NONNULL_END
