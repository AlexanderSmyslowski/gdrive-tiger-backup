#import "UpdateSupport.h"

#import <CommonCrypto/CommonDigest.h>

static NSString * const GDTUpdateAPIURLString =
    @"https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest";
static NSString * const GDTUpdateReleaseURLString =
    @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest";
static NSUInteger const GDTMaximumUpdateResponseBytes = 256 * 1024;

static NSDictionary<NSString *, NSString *> *GDTUnavailableUpdateResult(NSString *reason) {
    return @{ @"reason": reason, @"status": @"unavailable" };
}

static NSArray<NSNumber *> *GDTVersionComponents(NSString *version) {
    if (![version isKindOfClass:NSString.class]) return nil;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^v?([0-9]{1,6})\\.([0-9]{1,6})\\.([0-9]{1,6})$"
                             options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:version
                                                         options:0
                                                           range:NSMakeRange(0, version.length)];
    if (!match || !NSEqualRanges(match.range, NSMakeRange(0, version.length))) return nil;
    NSMutableArray<NSNumber *> *components = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger index = 1; index <= 3; index++) {
        [components addObject:@([[version substringWithRange:[match rangeAtIndex:index]] integerValue])];
    }
    return components;
}

static NSComparisonResult GDTCompareVersions(NSArray<NSNumber *> *left,
                                              NSArray<NSNumber *> *right) {
    for (NSUInteger index = 0; index < 3; index++) {
        NSComparisonResult result = [left[index] compare:right[index]];
        if (result != NSOrderedSame) return result;
    }
    return NSOrderedSame;
}

static BOOL GDTTrustedUpdateResponseURL(NSURL *url) {
    return [url.scheme.lowercaseString isEqualToString:@"https"] &&
        [url.host.lowercaseString isEqualToString:@"api.github.com"] &&
        [url.path isEqualToString:
            @"/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"] &&
        !url.user.length && !url.password.length && !url.port && !url.query.length && !url.fragment.length;
}

@interface GDTUpdateChecker ()
@property(nonatomic, strong) NSURLSession *session;
@end

@implementation GDTUpdateChecker

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 10.0;
    configuration.timeoutIntervalForResource = 15.0;
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:self
                                        delegateQueue:nil];
    NSURLSession *session = _session;
    _dataLoader = ^(NSURLRequest *request, GDTUpdateDataCompletion completion) {
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                completion(data, response, error);
            }];
        [task resume];
    };
    return self;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
  completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session;
    (void)task;
    (void)response;
    completionHandler(GDTTrustedUpdateResponseURL(request.URL) ? request : nil);
}

+ (NSDictionary<NSString *, NSString *> *)resultForResponseData:(NSData *)data
                                                    responseURL:(NSURL *)responseURL
                                                 currentVersion:(NSString *)currentVersion {
    if (!data || data.length == 0 || data.length > GDTMaximumUpdateResponseBytes ||
        !GDTTrustedUpdateResponseURL(responseURL)) {
        return GDTUnavailableUpdateResult(@"invalid_response");
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class]) {
        return GDTUnavailableUpdateResult(@"invalid_response");
    }
    NSDictionary *release = object;
    if (![release[@"tag_name"] isKindOfClass:NSString.class] ||
        ![release[@"draft"] isKindOfClass:NSNumber.class] ||
        ![release[@"prerelease"] isKindOfClass:NSNumber.class] ||
        [release[@"draft"] boolValue] || [release[@"prerelease"] boolValue]) {
        return GDTUnavailableUpdateResult(@"invalid_response");
    }
    NSArray<NSNumber *> *latest = GDTVersionComponents(release[@"tag_name"]);
    NSArray<NSNumber *> *current = GDTVersionComponents(currentVersion);
    if (!latest || !current) return GDTUnavailableUpdateResult(@"invalid_response");
    NSString *normalized = [NSString stringWithFormat:@"%@.%@.%@",
        latest[0], latest[1], latest[2]];
    if (GDTCompareVersions(latest, current) != NSOrderedDescending) {
        return @{ @"status": @"current", @"version": normalized };
    }
    return @{
        @"status": @"updateAvailable",
        @"version": normalized,
        @"releaseURL": GDTUpdateReleaseURLString
    };
}

- (void)checkCurrentVersion:(NSString *)currentVersion
                 completion:(void (^)(NSDictionary<NSString *, NSString *> *))completion {
    NSURL *url = [NSURL URLWithString:GDTUpdateAPIURLString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"GDrive-Backup-Tiger" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    if (!self.dataLoader) {
        completion(GDTUnavailableUpdateResult(@"network"));
        return;
    }
    self.dataLoader(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class] ||
            ((NSHTTPURLResponse *)response).statusCode != 200) {
            completion(GDTUnavailableUpdateResult(@"network"));
            return;
        }
        completion([GDTUpdateChecker resultForResponseData:data
                                               responseURL:response.URL
                                            currentVersion:currentVersion]);
    });
}

@end

// Empty until the project has an Apple Developer ID; then set to its team ID
// so only packages signed by that team are installed.
NSString * const GDTUpdateTrustedTeamID = @"";

static NSString * const GDTUpdateDownloadPrefix =
    @"/AlexanderSmyslowski/gdrive-tiger-backup/releases/download/";
static unsigned long long const GDTMaximumPackageBytes = 300ULL * 1024 * 1024;
static unsigned long long const GDTMaximumSumsBytes = 16 * 1024;

NSString *GDTUpdatePackageName(NSString *version) {
    return [NSString stringWithFormat:@"GDrive-Backup-Tiger-%@.pkg", version];
}

NSURL *GDTUpdateAssetURL(NSString *version, NSString *name) {
    NSArray<NSNumber *> *components = GDTVersionComponents(version);
    if (!components || [version hasPrefix:@"v"]) return nil;
    if (![name isEqualToString:@"SHA256SUMS.txt"] && ![name isEqualToString:GDTUpdatePackageName(version)]) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com%@v%@/%@",
        GDTUpdateDownloadPrefix, version, name]];
}

BOOL GDTTrustedUpdateDownloadURL(NSURL *url) {
    if (!url || ![url.scheme.lowercaseString isEqualToString:@"https"] ||
        url.user.length || url.password.length || url.port || url.fragment.length) return NO;
    NSString *host = url.host.lowercaseString;
    if ([host isEqualToString:@"github.com"]) {
        return [url.path hasPrefix:GDTUpdateDownloadPrefix] && !url.query.length;
    }
    // GitHub answers asset downloads with a short-lived signed redirect.
    return [host isEqualToString:@"release-assets.githubusercontent.com"] ||
        [host isEqualToString:@"objects.githubusercontent.com"];
}

NSString *GDTExpectedSHA256(NSString *sums, NSString *fileName) {
    NSString *found = nil;
    for (NSString *line in [sums componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange space = [line rangeOfString:@"  "];
        if (space.location != 64) continue;
        NSString *hash = [line substringToIndex:64].lowercaseString;
        NSString *name = [line substringFromIndex:NSMaxRange(space)];
        if ([name hasPrefix:@"*"]) name = [name substringFromIndex:1];
        if (![name isEqualToString:fileName]) continue;
        if ([hash rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
                @"0123456789abcdef"].invertedSet].location != NSNotFound) return nil;
        if (found && ![found isEqualToString:hash]) return nil;
        found = hash;
    }
    return found;
}

NSString *GDTSHA256OfFile(NSString *path) {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    if (!stream) return nil;
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[64 * 1024];
    NSInteger read = 0;
    while ((read = [stream read:buffer maxLength:sizeof buffer]) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)read);
    }
    [stream close];
    if (read < 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (int index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [hex appendFormat:@"%02x", digest[index]];
    return hex;
}

NSString *GDTUpdateSignatureProblem(int status, NSString *output, NSString *trustedTeamID) {
    if (!trustedTeamID.length) return nil;
    if (status != 0 || ![output containsString:@"Status: signed by a developer certificate issued by Apple"] ||
        ![output containsString:@"Developer ID Installer:"]) return @"unsigned";
    NSString *team = [NSString stringWithFormat:@"(%@)", trustedTeamID];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if ([line containsString:@"Developer ID Installer:"]) {
            return [line hasSuffix:team] ? nil : @"untrusted_signature";
        }
    }
    return @"untrusted_signature";
}

@interface GDTUpdateDownloader ()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionTask *currentTask;
@end

@implementation GDTUpdateDownloader

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 30.0 * 60.0;
    _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    return self;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
  completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session;
    (void)task;
    (void)response;
    completionHandler(GDTTrustedUpdateDownloadURL(request.URL) ? request : nil);
}

- (void)cancel {
    [self.currentTask cancel];
}

- (void)fetch:(NSURL *)url
           to:(NSString *)destination
     maxBytes:(unsigned long long)maxBytes
   completion:(void (^)(BOOL ok))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"GDrive-Backup-Tiger" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Accept"];
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSFileManager *manager = NSFileManager.defaultManager;
            NSDictionary *attributes = location ? [manager attributesOfItemAtPath:location.path error:nil] : nil;
            BOOL ok = !error && location &&
                [response isKindOfClass:NSHTTPURLResponse.class] &&
                ((NSHTTPURLResponse *)response).statusCode == 200 &&
                GDTTrustedUpdateDownloadURL(response.URL) &&
                [attributes[NSFileSize] unsignedLongLongValue] > 0 &&
                [attributes[NSFileSize] unsignedLongLongValue] <= maxBytes;
            if (ok) {
                [manager removeItemAtPath:destination error:nil];
                ok = [manager moveItemAtPath:location.path toPath:destination error:nil] &&
                    [manager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:destination error:nil];
            }
            completion(ok);
        }];
    self.currentTask = task;
    [task resume];
}

- (void)downloadVersion:(NSString *)version
            toDirectory:(NSString *)directory
             completion:(GDTUpdateDownloadCompletion)completion {
    NSString *packageName = GDTUpdatePackageName(version);
    NSURL *sumsURL = GDTUpdateAssetURL(version, @"SHA256SUMS.txt");
    NSURL *packageURL = GDTUpdateAssetURL(version, packageName);
    if (!sumsURL || !packageURL) {
        completion(nil, @"invalid_version");
        return;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager removeItemAtPath:directory error:nil];
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @0700} error:nil]) {
        completion(nil, @"storage");
        return;
    }
    NSString *sumsPath = [directory stringByAppendingPathComponent:@"SHA256SUMS.txt"];
    NSString *packagePath = [directory stringByAppendingPathComponent:packageName];
    __weak typeof(self) weakSelf = self;
    [self fetch:sumsURL to:sumsPath maxBytes:GDTMaximumSumsBytes completion:^(BOOL sumsOK) {
        NSString *sums = sumsOK ? [NSString stringWithContentsOfFile:sumsPath encoding:NSUTF8StringEncoding error:nil] : nil;
        NSString *expected = sums ? GDTExpectedSHA256(sums, packageName) : nil;
        if (!expected) {
            completion(nil, sumsOK ? @"checksum_missing" : @"network");
            return;
        }
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, @"cancelled");
            return;
        }
        [strongSelf fetch:packageURL to:packagePath maxBytes:GDTMaximumPackageBytes completion:^(BOOL packageOK) {
            if (!packageOK) {
                completion(nil, @"network");
                return;
            }
            if (![GDTSHA256OfFile(packagePath) isEqualToString:expected]) {
                [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];
                completion(nil, @"checksum_mismatch");
                return;
            }
            completion(packagePath, nil);
        }];
    }];
}

@end
