#import <Foundation/Foundation.h>
#import <NetFS/NetFS.h>
#include <errno.h>

typedef NSData * _Nullable (^GDTTestCredentialLookup)(
    NSString *host, NSString *account, NSString *path, BOOL allowUserInteraction);
typedef int (^GDTTestMountOperation)(
    NSURL *url, NSString *account, NSData *passwordData);
typedef int (^GDTTestCLIHandler)(NSString *urlString, BOOL authorizeCredential);
typedef int (^GDTTestKeychainInteractionSetter)(BOOL allowInteraction);

extern int GDTHandleSMBURLWithHandlers(
    NSString *urlString,
    BOOL allowCredentialUI,
    BOOL performMount,
    GDTTestCredentialLookup credentialLookup,
    GDTTestMountOperation mountOperation);
extern int GDTHandleNetworkMountCLIArguments(
    NSArray<NSString *> *arguments,
    GDTTestCLIHandler handler,
    BOOL *handled);
extern BOOL GDTConfigureLegacyKeychainInteraction(
    BOOL allowInteraction,
    GDTTestKeychainInteractionSetter setter);
extern int GDTMountSMBURLFromKeychain(NSString *urlString);

static BOOL NetFSGuestModeWasSet = NO;
static BOOL NetFSNoUIWasSet = NO;
static BOOL NetFSReceivedEmptyCredentials = NO;
static NSUInteger NetFSMountCallCount = 0;

int NetFSMountURLSync(
    CFURLRef url,
    CFURLRef mountpath,
    CFStringRef user,
    CFStringRef passwd,
    CFMutableDictionaryRef openOptions,
    CFMutableDictionaryRef mountOptions,
    CFArrayRef *mountpoints) {
    (void)url;
    (void)mountpath;
    (void)mountOptions;
    (void)mountpoints;
    NSDictionary *options = (__bridge NSDictionary *)openOptions;
    NetFSGuestModeWasSet = [options[(__bridge id)kNetFSUseGuestKey] boolValue];
    NetFSNoUIWasSet = [options[(__bridge id)kNAUIOptionKey]
        isEqual:(__bridge id)kNAUIOptionNoUI];
    NSString *account = (__bridge NSString *)user;
    NSString *password = (__bridge NSString *)passwd;
    NetFSReceivedEmptyCredentials = account.length == 0 && password.length == 0;
    NetFSMountCallCount++;
    return 0;
}

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static BOOL DataIsZeroed(NSData *data) {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) {
        if (bytes[index] != 0) {
            return NO;
        }
    }
    return YES;
}

int main(void) {
    @autoreleasepool {
        __block BOOL lookupCalled = NO;
        __block BOOL mountCalled = NO;
        NSMutableData *password = [[@"test-secret"
            dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        int result = GDTHandleSMBURLWithHandlers(
            @"smb://backup-user@nas.local/Backups",
            NO,
            YES,
            ^NSData *(NSString *host, NSString *account, NSString *path,
                      BOOL allowUserInteraction) {
                lookupCalled = YES;
                Assert([host isEqualToString:@"nas.local"], @"host reaches credential lookup");
                Assert([account isEqualToString:@"backup-user"], @"account reaches credential lookup");
                Assert([path isEqualToString:@"/Backups"], @"share path reaches credential lookup");
                Assert(!allowUserInteraction, @"automatic mounts must forbid credential UI");
                return password;
            },
            ^int(NSURL *url, NSString *account, NSData *passwordData) {
                mountCalled = YES;
                Assert([url.absoluteString isEqualToString:
                    @"smb://backup-user@nas.local/Backups"],
                    @"the validated URL reaches the mount operation");
                Assert([account isEqualToString:@"backup-user"],
                    @"the validated account reaches the mount operation");
                Assert([passwordData isEqualToData:
                    [@"test-secret" dataUsingEncoding:NSUTF8StringEncoding]],
                    @"the credential reaches the mount operation only in memory");
                return 0;
            });
        Assert(result == 0 && lookupCalled && mountCalled,
            @"a complete account-qualified SMB request mounts successfully");
        Assert(DataIsZeroed(password),
            @"credential bytes are cleared after the mount operation");

        __block BOOL guestLookupCalled = NO;
        __block BOOL guestMountCalled = NO;
        result = GDTHandleSMBURLWithHandlers(
            @"smb://nas.local/Backups",
            NO,
            YES,
            ^NSData *(NSString *host, NSString *account, NSString *path,
                      BOOL allowUserInteraction) {
                (void)host;
                (void)account;
                (void)path;
                (void)allowUserInteraction;
                guestLookupCalled = YES;
                return [[@"must-not-be-used"
                    dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            },
            ^int(NSURL *url, NSString *account, NSData *passwordData) {
                guestMountCalled = YES;
                Assert([url.absoluteString isEqualToString:
                    @"smb://nas.local/Backups"],
                    @"the accountless URL reaches the guest mount operation");
                Assert(account.length == 0,
                    @"a guest mount receives an empty account");
                Assert(passwordData.length == 0,
                    @"a guest mount receives an empty password");
                return 0;
            });
        Assert(result == 0 && !guestLookupCalled && guestMountCalled,
            @"an accountless SMB request mounts as guest without Keychain access");

        guestLookupCalled = NO;
        result = GDTHandleSMBURLWithHandlers(
            @"smb://nas.local/Backups",
            NO,
            YES,
            ^NSData *(NSString *host, NSString *account, NSString *path,
                      BOOL allowUserInteraction) {
                (void)host;
                (void)account;
                (void)path;
                (void)allowUserInteraction;
                guestLookupCalled = YES;
                return [NSData data];
            },
            ^int(NSURL *url, NSString *account, NSData *passwordData) {
                (void)url;
                (void)account;
                (void)passwordData;
                return EACCES;
            });
        Assert(result == 69 && !guestLookupCalled,
            @"a failed guest attempt remains a safe mount failure without Keychain fallback");

        __block BOOL guestAuthorizationLookupCalled = NO;
        __block BOOL guestAuthorizationMountCalled = NO;
        result = GDTHandleSMBURLWithHandlers(
            @"smb://nas.local/Backups",
            YES,
            NO,
            ^NSData *(NSString *host, NSString *account, NSString *path,
                      BOOL allowUserInteraction) {
                (void)host;
                (void)account;
                (void)path;
                (void)allowUserInteraction;
                guestAuthorizationLookupCalled = YES;
                return [NSData data];
            },
            ^int(NSURL *url, NSString *account, NSData *passwordData) {
                (void)url;
                (void)account;
                (void)passwordData;
                guestAuthorizationMountCalled = YES;
                return 0;
            });
        Assert(result == 0 && !guestAuthorizationLookupCalled &&
                   !guestAuthorizationMountCalled,
            @"explicit authorization is a no-op for an accountless guest URL");

        NSArray<NSString *> *malformedGuestURLs = @[
            @"smb:///Backups",
            @"smb://nas.local",
            @"smb://nas.local//",
            @"smb://@nas.local/Backups",
            @"https://nas.local/Backups"
        ];
        for (NSString *malformedURL in malformedGuestURLs) {
            __block BOOL malformedLookupCalled = NO;
            __block BOOL malformedMountCalled = NO;
            result = GDTHandleSMBURLWithHandlers(
                malformedURL,
                NO,
                YES,
                ^NSData *(NSString *host, NSString *account, NSString *path,
                          BOOL allowUserInteraction) {
                    (void)host;
                    (void)account;
                    (void)path;
                    (void)allowUserInteraction;
                    malformedLookupCalled = YES;
                    return [NSData data];
                },
                ^int(NSURL *url, NSString *account, NSData *passwordData) {
                    (void)url;
                    (void)account;
                    (void)passwordData;
                    malformedMountCalled = YES;
                    return 0;
                });
            Assert(result == 64 && !malformedLookupCalled && !malformedMountCalled,
                [NSString stringWithFormat:
                    @"malformed guest URL is rejected before credentials or mount: %@",
                    malformedURL]);
        }

        result = GDTMountSMBURLFromKeychain(@"smb://nas.local/Backups");
        Assert(result == 0 && NetFSMountCallCount == 1,
            @"the production accountless path reaches NetFS exactly once");
        Assert(NetFSGuestModeWasSet,
            @"the production accountless path enables NetFS guest mode");
        Assert(NetFSNoUIWasSet,
            @"the production accountless path retains the NetFS no-UI policy");
        Assert(NetFSReceivedEmptyCredentials,
            @"the production accountless path gives NetFS empty credentials");

        __block BOOL unsafeLookupCalled = NO;
        result = GDTHandleSMBURLWithHandlers(
            @"smb://backup-user:must-not-be-accepted@nas.local/Backups",
            NO,
            YES,
            ^NSData *(NSString *host, NSString *account, NSString *path,
                      BOOL allowUserInteraction) {
                (void)host;
                (void)account;
                (void)path;
                (void)allowUserInteraction;
                unsafeLookupCalled = YES;
                return [NSData data];
            },
            ^int(NSURL *url, NSString *account, NSData *passwordData) {
                (void)url;
                (void)account;
                (void)passwordData;
                return 0;
            });
        Assert(result == 64 && !unsafeLookupCalled,
            @"passwords embedded in NAS URLs fail before Keychain access");

        __block BOOL authorizationMountCalled = NO;
        result = GDTHandleSMBURLWithHandlers(
            @"smb://backup-user@nas.local/Backups",
            YES,
            NO,
            ^NSData *(NSString *host, NSString *account, NSString *path,
                      BOOL allowUserInteraction) {
                (void)host;
                (void)account;
                (void)path;
                Assert(allowUserInteraction,
                    @"explicit setup authorization may show the Keychain prompt");
                return [[@"test-secret" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            },
            ^int(NSURL *url, NSString *account, NSData *passwordData) {
                (void)url;
                (void)account;
                (void)passwordData;
                authorizationMountCalled = YES;
                return 0;
            });
        Assert(result == 0 && !authorizationMountCalled,
            @"credential authorization never mounts the share");

        __block BOOL cliCalled = NO;
        __block BOOL cliAuthorized = YES;
        result = GDTHandleNetworkMountCLIArguments(
            @[@"GDriveBackupTiger", @"--mount-network-url",
              @"smb://backup-user@nas.local/Backups"],
            ^int(NSString *urlString, BOOL authorizeCredential) {
                cliCalled = YES;
                cliAuthorized = authorizeCredential;
                Assert([urlString isEqualToString:
                    @"smb://backup-user@nas.local/Backups"],
                    @"the CLI passes the configured SMB URL to the native helper");
                return 0;
            },
            NULL);
        Assert(result == 0 && cliCalled && !cliAuthorized,
            @"the automatic CLI selects a no-UI mount");

        BOOL handled = NO;
        cliCalled = NO;
        result = GDTHandleNetworkMountCLIArguments(
            @[@"GDriveBackupTiger", @"--authorize-network-url",
              @"smb://backup-user@nas.local/Backups"],
            ^int(NSString *urlString, BOOL authorizeCredential) {
                (void)urlString;
                cliCalled = YES;
                cliAuthorized = authorizeCredential;
                return 0;
            },
            &handled);
        Assert(result == 0 && handled && cliCalled && cliAuthorized,
            @"explicit setup can request one credential authorization");

        handled = NO;
        cliCalled = NO;
        result = GDTHandleNetworkMountCLIArguments(
            @[@"GDriveBackupTiger", @"--menubar"],
            ^int(NSString *urlString, BOOL authorizeCredential) {
                (void)urlString;
                (void)authorizeCredential;
                cliCalled = YES;
                return 0;
            },
            &handled);
        Assert(result == 0 && !handled && !cliCalled,
            @"ordinary app modes continue to the graphical application");

        handled = NO;
        result = GDTHandleNetworkMountCLIArguments(
            @[@"GDriveBackupTiger", @"--mount-network-url"],
            ^int(NSString *urlString, BOOL authorizeCredential) {
                (void)urlString;
                (void)authorizeCredential;
                return 0;
            },
            &handled);
        Assert(result == 64 && handled,
            @"an incomplete mount command fails before the graphical app starts");

        __block BOOL interactionAllowed = YES;
        BOOL interactionConfigured = GDTConfigureLegacyKeychainInteraction(
            NO,
            ^int(BOOL allowInteraction) {
                interactionAllowed = allowInteraction;
                return 0;
            });
        Assert(interactionConfigured && !interactionAllowed,
            @"automatic lookup disables legacy Keychain UI before reading credentials");
    }
    NSLog(@"Network mount support tests passed.");
    return 0;
}
