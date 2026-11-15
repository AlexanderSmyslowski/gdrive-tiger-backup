#import "NetworkMountSupport.h"

#import <NetFS/NetFS.h>
#import <Security/Security.h>
#include <errno.h>
#include <string.h>

static void GDTZeroCredentialData(NSMutableData *data) {
    if (data.length > 0) {
        (void)memset_s(data.mutableBytes, data.length, 0, data.length);
    }
}

BOOL GDTConfigureLegacyKeychainInteraction(
    BOOL allowInteraction,
    GDTLegacyKeychainInteractionSetter setter) {
    return setter && setter(allowInteraction) == errSecSuccess;
}

int GDTHandleSMBURLWithHandlers(
    NSString *urlString,
    BOOL allowCredentialUI,
    BOOL performMount,
    GDTNASCredentialLookup credentialLookup,
    GDTNASMountOperation mountOperation) {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host;
    NSString *account = components.user ?: @"";
    NSString *path = components.path;
    BOOL hasEmptyUserInfo = components.percentEncodedUser != nil && !account.length;
    BOOL hasNoShare = path.length <= 1 || [path characterAtIndex:1] == '/';
    if (![scheme isEqualToString:@"smb"] || !host.length || hasEmptyUserInfo ||
        hasNoShare || components.password != nil ||
        (account.length && !credentialLookup) ||
        (performMount && !mountOperation)) {
        return 64;
    }

    if (!account.length) {
        // An absent user means an explicit guest profile. It must bypass the
        // Keychain entirely so neither authorization nor an automatic retry
        // can provoke credential UI.
        if (!performMount) {
            return 0;
        }
        int result = mountOperation(components.URL, @"", [NSMutableData data]);
        return result == 0 ? 0 : 69;
    }

    if (performMount) {
        // Finder saves SMB passwords with Apple's "apple:" Keychain partition,
        // so Apple's NetAuth service may use them silently for any build of
        // this app. Reading the item ourselves needs a grant tied to the exact
        // build (apps without an Apple team ID get cdhash partitions), which
        // every update loses. Let NetFS resolve the stored password first and
        // keep our own Keychain read only as the fallback.
        int systemResult = mountOperation(components.URL, account, nil);
        if (systemResult == 0) {
            return 0;
        }
        fprintf(stderr, "NAS diagnostic stage=system_credential_mount status=%d\n", systemResult);
    }

    NSData *credential = credentialLookup(
        host, account, path, allowCredentialUI);
    if (!credential.length) {
        return 69;
    }

    NSMutableData *workingCredential =
        [credential isKindOfClass:NSMutableData.class]
            ? (NSMutableData *)credential
            : [credential mutableCopy];
    int result = 0;
    if (performMount) {
        result = mountOperation(components.URL, account, workingCredential);
    }
    GDTZeroCredentialData(workingCredential);
    return result == 0 ? 0 : 69;
}

static NSData *GDTLookupSMBPassword(
    NSString *host,
    NSString *account,
    NSString *path,
    BOOL allowUserInteraction) {
    __block OSStatus interactionStatus = errSecSuccess;
    BOOL interactionConfigured = GDTConfigureLegacyKeychainInteraction(
        allowUserInteraction,
        ^int(BOOL allowInteraction) {
            // This legacy API is intentionally paired with Finder's legacy
            // Internet-password items. Modern LAContext flags do not suppress
            // their ACL prompt on macOS.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            interactionStatus = SecKeychainSetUserInteractionAllowed(allowInteraction);
            return interactionStatus;
#pragma clang diagnostic pop
        });
    if (!interactionConfigured) {
        fprintf(stderr, "NAS diagnostic stage=keychain_configuration status=%d\n", (int)interactionStatus);
        return nil;
    }

    NSArray<NSString *> *candidatePaths = [path hasPrefix:@"/"] && path.length > 1
        ? @[path, [path substringFromIndex:1]]
        : @[path];

    for (NSString *candidatePath in candidatePaths) {
        NSMutableDictionary *query = [@{
            (__bridge id)kSecClass: (__bridge id)kSecClassInternetPassword,
            (__bridge id)kSecAttrServer: host,
            (__bridge id)kSecAttrAccount: account,
            (__bridge id)kSecAttrPath: candidatePath,
            (__bridge id)kSecAttrProtocol: (__bridge id)kSecAttrProtocolSMB,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
            (__bridge id)kSecReturnData: @YES
        } mutableCopy];
        if (!allowUserInteraction) {
            // LAContext.interactionNotAllowed applies only to Data Protection
            // items on macOS. Finder's SMB passwords use the legacy keychain,
            // where UISkip is the only query option that cannot spawn a prompt.
            query[(__bridge id)kSecUseAuthenticationUI] =
                (__bridge id)kSecUseAuthenticationUISkip;
        }

        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching(
            (__bridge CFDictionaryRef)query, &result);
        if (status == errSecSuccess && result) {
            NSData *data = CFBridgingRelease(result);
            if (!data.length) fprintf(stderr, "NAS diagnostic stage=credential_data status=0\n");
            return data;
        }
        if (result) {
            CFRelease(result);
        }
        if (status != errSecItemNotFound) {
            fprintf(stderr, "NAS diagnostic stage=keychain_lookup status=%d\n", (int)status);
            return nil;
        }
    }
    fprintf(stderr, "NAS diagnostic stage=keychain_lookup status=%d\n", (int)errSecItemNotFound);
    return nil;
}

static int GDTNetFSMount(
    NSURL *url,
    NSString *account,
    NSData * _Nullable passwordData) {
    BOOL useGuest = !account.length;
    CFStringRef password = NULL;
    // A nil password with an account asks NetFS to use the stored credential.
    if (!useGuest && passwordData) {
        password = CFStringCreateWithBytesNoCopy(
            kCFAllocatorDefault,
            passwordData.bytes,
            passwordData.length,
            kCFStringEncodingUTF8,
            false,
            kCFAllocatorNull);
        if (!password) {
            fprintf(stderr, "NAS diagnostic stage=credential_encoding status=%d\n", EINVAL);
            return EINVAL;
        }
    }

    NSMutableDictionary *openOptions = [@{
        (__bridge id)kNAUIOptionKey: (__bridge id)kNAUIOptionNoUI
    } mutableCopy];
    if (useGuest) {
        openOptions[(__bridge id)kNetFSUseGuestKey] = @YES;
    }
    CFArrayRef mountpoints = NULL;
    int result = NetFSMountURLSync(
        (__bridge CFURLRef)url,
        NULL,
        useGuest ? NULL : (__bridge CFStringRef)account,
        password,
        (__bridge CFMutableDictionaryRef)openOptions,
        NULL,
        &mountpoints);
    // Stage and numeric code identify the failure without exposing NAS or credential details.
    if (result != 0) fprintf(stderr, "NAS diagnostic stage=netfs_mount status=%d\n", result);
    if (mountpoints) {
        CFRelease(mountpoints);
    }
    if (password) {
        CFRelease(password);
    }
    return result;
}

int GDTAuthorizeSMBCredentialForURL(NSString *urlString) {
    return GDTHandleSMBURLWithHandlers(
        urlString,
        YES,
        NO,
        ^NSData *(NSString *host, NSString *account, NSString *path,
                  BOOL allowUserInteraction) {
            return GDTLookupSMBPassword(
                host, account, path, allowUserInteraction);
        },
        nil);
}

int GDTMountSMBURLFromKeychain(NSString *urlString) {
    return GDTHandleSMBURLWithHandlers(
        urlString,
        NO,
        YES,
        ^NSData *(NSString *host, NSString *account, NSString *path,
                  BOOL allowUserInteraction) {
            return GDTLookupSMBPassword(
                host, account, path, allowUserInteraction);
        },
        ^int(NSURL *url, NSString *account, NSData *passwordData) {
            return GDTNetFSMount(url, account, passwordData);
        });
}

int GDTHandleNetworkMountCLIArguments(
    NSArray<NSString *> *arguments,
    GDTNetworkMountCLIHandler handler,
    BOOL *handled) {
    if (handled) {
        *handled = NO;
    }
    if (arguments.count < 2) {
        return 0;
    }

    NSString *command = arguments[1];
    BOOL authorizeCredential =
        [command isEqualToString:@"--authorize-network-url"];
    BOOL mountNetworkURL =
        [command isEqualToString:@"--mount-network-url"];
    if (!authorizeCredential && !mountNetworkURL) {
        return 0;
    }
    if (handled) {
        *handled = YES;
    }
    if (arguments.count != 3 || ![arguments[2] length] || !handler) {
        return 64;
    }
    return handler(arguments[2], authorizeCredential);
}
