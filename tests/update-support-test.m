#import <Foundation/Foundation.h>

#import "UpdateSupport.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    if (condition) {
        printf("ok - %s\n", name.UTF8String);
        return;
    }
    printf("not ok - %s\n", name.UTF8String);
    failures++;
}

static NSData *JSONData(NSDictionary *dictionary) {
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
}

// Dynamic lookup lets the first regression run fail behaviorally on the old app.
@protocol AutomaticUpdates <NSObject>
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults checker:(GDTUpdateChecker *)checker
                   currentVersion:(NSString *)version;
@property(nonatomic, copy) NSDate *(^clock)(void);
@property(nonatomic, copy) void (^stateChanged)(void);
@property(nonatomic, readonly) BOOL answered;
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) NSString *availableVersion;
@property(nonatomic, readonly) NSString *generation;
- (void)setEnabled:(BOOL)enabled;
- (void)checkIfDue;
- (NSString *)claimNoticeVersion;
- (BOOL)acceptsNoticeVersion:(NSString *)version generation:(NSString *)generation;
- (NSArray<NSString *> *)takeObsoleteNoticeIdentifiers;
@end

static void TestAutomaticUpdates(void) {
    NSString *domain = [@"GDTUpdateTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:domain];
    GDTUpdateChecker *checker = [[GDTUpdateChecker alloc] init];
    __block NSInteger calls = 0;
    __block GDTUpdateDataCompletion pending;
    __block NSDate *now = [NSDate dateWithTimeIntervalSince1970:2000000000];
    checker.dataLoader = ^(NSURLRequest *request, GDTUpdateDataCompletion completion) {
        (void)request;
        calls++;
        pending = completion;
    };
    Class policyClass = NSClassFromString(@"GDTAutomaticUpdatePolicy");
    id<AutomaticUpdates> policy = [(id<AutomaticUpdates>)[policyClass alloc]
        initWithDefaults:defaults checker:checker currentVersion:@"2.0.0"];
    policy.clock = ^{ return now; };
    [policy checkIfDue];
    Assert(calls == 0 && !policy.answered, @"unanswered automatic preference makes zero requests");
    [policy setEnabled:NO];
    [policy checkIfDue];
    Assert(policy.answered && !policy.enabled && calls == 0,
           @"explicit refusal is durable and performs zero requests");
    [policy setEnabled:YES];
    [policy checkIfDue];
    [policy checkIfDue];
    Assert(calls == 1 && [defaults doubleForKey:@"GDTUpdates.lastAttempt"] == 2000000000,
           @"opt-in persists an attempt before HTTP and prevents overlapping checks");
    if (!policy) { [defaults removePersistentDomainForName:domain]; return; }
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:nil headerFields:nil];
    NSData *release = JSONData(@{@"tag_name": @"v2.1.0", @"draft": @NO, @"prerelease": @NO});
    GDTUpdateDataCompletion stale = pending;
    NSString *oldGeneration = policy.generation;
    [policy setEnabled:NO];
    [policy setEnabled:YES];
    stale(release, response, nil);
    Assert(!policy.availableVersion.length && ![policy.generation isEqual:oldGeneration],
           @"opt-out and re-enable discard the old request generation");
    now = [now dateByAddingTimeInterval:86400];
    [policy checkIfDue];
    pending(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]);
    [policy checkIfDue];
    Assert(calls == 2, @"offline attempts consume the daily cooldown");
    policy = [(id<AutomaticUpdates>)[policyClass alloc] initWithDefaults:defaults checker:checker currentVersion:@"2.0.0"];
    policy.clock = ^{ return now; };
    [policy checkIfDue];
    Assert(policy.enabled && policy.answered && calls == 2,
           @"controller restart and wake preserve consent and daily throttle");
    now = [now dateByAddingTimeInterval:86399]; [policy checkIfDue];
    Assert(calls == 2, @"automatic checks never run before 24 hours");
    now = [now dateByAddingTimeInterval:1]; [policy checkIfDue];
    pending(release, response, nil);
    Assert([policy.availableVersion isEqual:@"2.1.0"] && [[policy claimNoticeVersion] isEqual:@"2.1.0"] &&
           ![policy claimNoticeVersion], @"newer stable version is cached and claimed only once");
    NSString *generation = policy.generation;
    Assert([policy acceptsNoticeVersion:@"2.1.0" generation:generation] &&
           ![policy acceptsNoticeVersion:@"2.1.0;open" generation:generation] &&
           ![policy acceptsNoticeVersion:@"2.1.0" generation:oldGeneration],
           @"notification actions require validated known version and current consent generation");
    policy = [(id<AutomaticUpdates>)[policyClass alloc] initWithDefaults:defaults checker:checker currentVersion:@"2.0.0"];
    policy.clock = ^{ return now; };
    Assert([policy.availableVersion isEqual:@"2.1.0"] && ![policy claimNoticeVersion],
           @"menu cache and per-version notice deduplication survive restart");
    [policy setEnabled:NO];
    Assert(!policy.availableVersion.length && ![policy acceptsNoticeVersion:@"2.1.0" generation:generation],
           @"opt-out removes cached discovery and invalidates pending notices");
    if ([policy respondsToSelector:@selector(takeObsoleteNoticeIdentifiers)]) {
        NSArray *obsolete = [policy takeObsoleteNoticeIdentifiers];
        Assert(obsolete.count == 1 && [obsolete.firstObject hasSuffix:@".2.1.0"] &&
               [policy takeObsoleteNoticeIdentifiers].count == 0,
               @"opt-out after restart drains only persisted update-owned notice identifiers");
    } else {
        Assert(NO, @"opt-out after restart drains only persisted update-owned notice identifiers");
    }
    [policy setEnabled:YES];
    for (id bad in @[@"corrupt", @(-1), @(NAN), @([now timeIntervalSince1970] + 9999999)]) {
        [defaults setObject:bad forKey:@"GDTUpdates.lastAttempt"];
        NSInteger previous = calls;
        [policy checkIfDue]; [policy checkIfDue];
        Assert(calls == previous && [defaults doubleForKey:@"GDTUpdates.lastAttempt"] == now.timeIntervalSince1970,
               @"corrupt or future attempt dates normalize with a bounded cooldown");
        now = [now dateByAddingTimeInterval:86400];
        [policy checkIfDue]; pending(release, response, nil);
        Assert(calls == previous + 1, @"repaired timestamps do not permanently disable discovery");
    }
    policy = [(id<AutomaticUpdates>)[policyClass alloc] initWithDefaults:defaults checker:checker currentVersion:@"2.1.0"];
    Assert(!policy.availableVersion.length, @"installing the discovered version expires the passive menu cache");
    [defaults removePersistentDomainForName:domain];
}

int main(void) {
    @autoreleasepool {
        TestAutomaticUpdates();
        NSURL *apiURL = [NSURL URLWithString:
            @"https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"];
        NSDictionary *available = [GDTUpdateChecker resultForResponseData:JSONData(@{
            @"tag_name": @"v2.10.0",
            @"draft": @NO,
            @"prerelease": @NO,
            @"html_url": @"https://evil.invalid/fake.pkg",
            @"body": @"token=private-secret"
        }) responseURL:apiURL currentVersion:@"2.9.9"];
        Assert([available[@"status"] isEqualToString:@"updateAvailable"] &&
               [available[@"version"] isEqualToString:@"2.10.0"] &&
               [available[@"releaseURL"] isEqualToString:
                   @"https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"] &&
               ![[available description] containsString:@"evil.invalid"] &&
               ![[available description] containsString:@"private-secret"],
               @"update results use numeric versions and one hard-coded official release page");

        NSDictionary *current = [GDTUpdateChecker resultForResponseData:JSONData(@{
            @"tag_name": @"2.0.0", @"draft": @NO, @"prerelease": @NO
        }) responseURL:apiURL currentVersion:@"2.0.0"];
        NSDictionary *older = [GDTUpdateChecker resultForResponseData:JSONData(@{
            @"tag_name": @"v1.99.0", @"draft": @NO, @"prerelease": @NO
        }) responseURL:apiURL currentVersion:@"2.0.0"];
        Assert([current[@"status"] isEqualToString:@"current"] &&
               [older[@"status"] isEqualToString:@"current"],
               @"equal or older releases never become a downgrade offer");

        NSArray<NSDictionary *> *invalidResults = @[
            [GDTUpdateChecker resultForResponseData:JSONData(@{
                @"tag_name": @"v2.1.0-beta.1", @"draft": @NO, @"prerelease": @YES
            }) responseURL:apiURL currentVersion:@"2.0.0"],
            [GDTUpdateChecker resultForResponseData:JSONData(@{
                @"tag_name": @"2.1.0\nhttps://evil.invalid", @"draft": @NO, @"prerelease": @NO
            }) responseURL:apiURL currentVersion:@"2.0.0"],
            [GDTUpdateChecker resultForResponseData:JSONData(@{
                @"tag_name": @"v2.1.0", @"draft": @NO, @"prerelease": @NO
            }) responseURL:[NSURL URLWithString:@"https://evil.invalid/releases/latest"]
               currentVersion:@"2.0.0"],
            [GDTUpdateChecker resultForResponseData:[NSMutableData dataWithLength:300 * 1024]
                                        responseURL:apiURL currentVersion:@"2.0.0"]
        ];
        BOOL rejected = YES;
        NSSet<NSString *> *safeUnavailableKeys = [NSSet setWithArray:@[@"reason", @"status"]];
        for (NSDictionary *result in invalidResults) {
            rejected = rejected && [result[@"status"] isEqualToString:@"unavailable"] &&
                [[NSSet setWithArray:result.allKeys] isEqualToSet:safeUnavailableKeys];
        }
        Assert(rejected,
               @"prereleases, malformed versions, foreign responses, and oversized bodies fail closed");

        __block NSInteger loadCalls = 0;
        __block NSURLRequest *capturedRequest = nil;
        GDTUpdateChecker *checker = [[GDTUpdateChecker alloc] init];
        checker.dataLoader = ^(NSURLRequest *request, GDTUpdateDataCompletion completion) {
            loadCalls++;
            capturedRequest = request;
            NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
                initWithURL:apiURL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
            completion(JSONData(@{
                @"tag_name": @"v2.1.0", @"draft": @NO, @"prerelease": @NO
            }), response, nil);
        };
        Assert(loadCalls == 0, @"constructing the checker never contacts the network");
        __block NSDictionary *checkedResult = nil;
        [checker checkCurrentVersion:@"2.0.0" completion:^(NSDictionary *result) {
            checkedResult = result;
        }];
        Assert(loadCalls == 1 &&
               [capturedRequest.URL isEqual:apiURL] &&
               [capturedRequest.HTTPMethod isEqualToString:@"GET"] &&
               [capturedRequest valueForHTTPHeaderField:@"Authorization"] == nil &&
               [checkedResult[@"status"] isEqualToString:@"updateAvailable"],
               @"one explicit check makes one unauthenticated request to the fixed API endpoint");

        SEL redirectSelector = NSSelectorFromString(
            @"URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:");
        __block NSURLRequest *allowedRedirect = nil;
        __block NSURLRequest *blockedRedirect = (NSURLRequest *)[NSNull null];
        if ([checker respondsToSelector:redirectSelector]) {
            typedef void (*RedirectMethod)(id, SEL, NSURLSession *, NSURLSessionTask *,
                NSHTTPURLResponse *, NSURLRequest *, void (^)(NSURLRequest *));
            RedirectMethod redirect = (RedirectMethod)[checker methodForSelector:redirectSelector];
            NSHTTPURLResponse *redirectResponse = [[NSHTTPURLResponse alloc]
                initWithURL:apiURL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
            NSURLRequest *sameEndpoint = [NSURLRequest requestWithURL:apiURL];
            NSURLRequest *foreignEndpoint = [NSURLRequest requestWithURL:
                [NSURL URLWithString:@"https://evil.invalid/collect"]];
            redirect(checker, redirectSelector, nil, nil, redirectResponse, sameEndpoint,
                ^(NSURLRequest *request) { allowedRedirect = request; });
            redirect(checker, redirectSelector, nil, nil, redirectResponse, foreignEndpoint,
                ^(NSURLRequest *request) { blockedRedirect = request; });
        }
        Assert([allowedRedirect.URL isEqual:apiURL] && blockedRedirect == nil,
               @"redirect handling never contacts a foreign or modified endpoint");
    }

    if (failures > 0) {
        printf("%d update support test(s) failed.\n", failures);
        return 1;
    }
    printf("All update support tests passed.\n");
    return 0;
}
