#import <Foundation/Foundation.h>

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
