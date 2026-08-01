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
    NSString *account = components.user;
    NSString *path = components.path;
    if (![scheme isEqualToString:@"smb"] || !host.length || !account.length ||
        path.length <= 1 || components.password != nil || !credentialLookup ||
        (performMount && !mountOperation)) {
        return 64;
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
    BOOL interactionConfigured = GDTConfigureLegacyKeychainInteraction(
        allowUserInteraction,
        ^int(BOOL allowInteraction) {
            // This legacy API is intentionally paired with Finder's legacy
            // Internet-password items. Modern LAContext flags do not suppress
            // their ACL prompt on macOS.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            return SecKeychainSetUserInteractionAllowed(allowInteraction);
#pragma clang diagnostic pop
        });
    if (!interactionConfigured) {
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
            return CFBridgingRelease(result);
        }
        if (result) {
            CFRelease(result);
        }
        if (status != errSecItemNotFound) {
            return nil;
        }
    }
    return nil;
}

static int GDTNetFSMount(
    NSURL *url,
    NSString *account,
    NSData *passwordData) {
    CFStringRef password = CFStringCreateWithBytesNoCopy(
        kCFAllocatorDefault,
        passwordData.bytes,
        passwordData.length,
        kCFStringEncodingUTF8,
        false,
        kCFAllocatorNull);
    if (!password) {
        return EINVAL;
    }

    NSMutableDictionary *openOptions = [@{
        (__bridge id)kNAUIOptionKey: (__bridge id)kNAUIOptionNoUI
    } mutableCopy];
    CFArrayRef mountpoints = NULL;
    int result = NetFSMountURLSync(
        (__bridge CFURLRef)url,
        NULL,
        (__bridge CFStringRef)account,
        password,
        (__bridge CFMutableDictionaryRef)openOptions,
        NULL,
        &mountpoints);
    if (mountpoints) {
        CFRelease(mountpoints);
    }
    CFRelease(password);
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
