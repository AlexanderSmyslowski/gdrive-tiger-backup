#import "UpdateSupport.h"

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
