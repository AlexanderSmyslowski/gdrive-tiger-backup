#import <Foundation/Foundation.h>

extern NSString *GDTNASRemountURLForMountedSMBSource(NSString *source);
extern NSString *GDTPreferredNASRemountURL(
    NSString *resourceURLString,
    NSString *mountedSource,
    BOOL isSMBMount);

static void AssertEqual(NSString *actual, NSString *expected, NSString *message) {
    if (![actual isEqualToString:expected]) {
        NSLog(@"FAIL: %@\nexpected: <%@>\nactual:   <%@>", message, expected, actual);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        AssertEqual(
            GDTNASRemountURLForMountedSMBSource(@"//backup-user@nas.local/Backups"),
            @"smb://backup-user@nas.local/Backups",
            @"the remount URL must retain the SMB account so Keychain can select credentials");
        AssertEqual(
            GDTNASRemountURLForMountedSMBSource(
                @"//backup-user:must-not-be-stored@nas.local/Backups"),
            @"smb://backup-user@nas.local/Backups",
            @"the remount URL must never retain a password");
        AssertEqual(
            GDTNASRemountURLForMountedSMBSource(@"//nas.local/Backups"),
            @"smb://nas.local/Backups",
            @"guest mounts remain valid without user information");
        AssertEqual(
            GDTPreferredNASRemountURL(
                @"smb://nas.local/Backups",
                @"//backup-user@nas.local/Backups",
                YES),
            @"smb://backup-user@nas.local/Backups",
            @"an account-qualified mount source must repair an accountless resource URL");
        AssertEqual(
            GDTPreferredNASRemountURL(
                @"smb://saved-user@nas.local/Backups",
                @"//nas.local/Backups",
                YES),
            @"smb://saved-user@nas.local/Backups",
            @"an accountless mount source must not discard a saved account");
        AssertEqual(
            GDTPreferredNASRemountURL(
                @"smb://saved-user:must-not-be-stored@nas.local/Backups",
                @"//nas.local/Backups",
                YES),
            @"smb://saved-user@nas.local/Backups",
            @"the resource URL fallback must never retain a password");
        AssertEqual(
            GDTPreferredNASRemountURL(
                @"afp://nas.local/Backups",
                @"//backup-user@nas.local/Backups",
                NO),
            @"afp://nas.local/Backups",
            @"an AFP mount source must never be rewritten as SMB");
    }
    NSLog(@"NAS mount URL tests passed.");
    return 0;
}
