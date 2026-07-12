#import <Foundation/Foundation.h>

static int failures = 0;

static void Assert(BOOL condition, NSString *name) {
    printf("%s - %s\n", condition ? "ok" : "not ok", name.UTF8String);
    if (!condition) failures++;
}

static NSDictionary<NSString *, id> *Result(id json, NSInteger status) {
    NSData *data = json ? [NSJSONSerialization dataWithJSONObject:json options:0 error:nil] : nil;
    NSString *output = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    return @{ @"status": @(status), @"output": output ?: @"", @"timedOut": @NO };
}

static NSArray *CallList(id object, NSString *selectorName, NSString *relativePath, NSError **error) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    typedef NSArray *(*Method)(id, SEL, NSString *, NSError **);
    return ((Method)[object methodForSelector:selector])(object, selector, relativePath, error);
}

@interface GDTInspectingFileManager : NSFileManager
@property(nonatomic) BOOL trashedNonemptyFilesList;
@end

@implementation GDTInspectingFileManager
- (BOOL)trashItemAtURL:(NSURL *)url
      resultingItemURL:(NSURL **)outResultingURL
                 error:(NSError **)error {
    if ([url.lastPathComponent hasPrefix:@".gdrive-files-"]) {
        NSData *contents = [NSData dataWithContentsOfURL:url];
        self.trashedNonemptyFilesList |= contents.length > 0;
    } else {
        NSArray<NSURL *> *children = [self contentsOfDirectoryAtURL:url
                                          includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *child in children) {
            if ([child.lastPathComponent hasPrefix:@".gdrive-files-"]) {
                self.trashedNonemptyFilesList |= [NSData dataWithContentsOfURL:child].length > 0;
            }
        }
    }
    return [super trashItemAtURL:url resultingItemURL:outResultingURL error:error];
}
@end

int main(void) {
    @autoreleasepool {
        NSString *older = @"2026-07-09T08-00-00+0200-11111111-1111-1111-1111-111111111111";
        NSString *newer = @"2026-07-10T20-00-00+0200-22222222-2222-2222-2222-222222222222";
        NSMutableArray<NSArray<NSString *> *> *calls = [NSMutableArray array];
        NSDictionary<NSString *, id> *(^catalogRunner)(NSString *, NSArray<NSString *> *) =
            ^NSDictionary *(NSString *command, NSArray<NSString *> *arguments) {
                [calls addObject:[@[command ?: @""] arrayByAddingObjectsFromArray:arguments ?: @[]]];
                if (![command isEqualToString:@"rclone"] || arguments.count < 2 ||
                    ![arguments[0] isEqualToString:@"lsjson"]) return Result(nil, 64);
                NSString *path = arguments[1];
                if ([path isEqualToString:@"backup-crypt:.gdrive-versions"]) {
                    return Result(@[
                        @{ @"Name": older, @"Path": older, @"IsDir": @YES },
                        @{ @"Name": newer, @"Path": newer, @"IsDir": @YES }
                    ], 0);
                }
                if ([path isEqualToString:@"backup-crypt:"]) {
                    return Result(@[
                        @{ @"Name": @"My Drive", @"Path": @"My Drive", @"IsDir": @YES },
                        @{ @"Name": @".gdrive-versions", @"Path": @".gdrive-versions", @"IsDir": @YES }
                    ], 0);
                }
                if ([path hasSuffix:[@":.gdrive-versions/" stringByAppendingString:older]] ||
                    [path hasSuffix:[@":.gdrive-versions/" stringByAppendingString:newer]]) {
                    return Result(@[@{ @"Name": @"My Drive", @"Path": @"My Drive", @"IsDir": @YES }], 0);
                }
                if ([path isEqualToString:@"backup-crypt:My Drive"]) {
                    return Result(@[
                        @{ @"Name": @"current.txt", @"Path": @"current.txt", @"IsDir": @NO,
                           @"Size": @7, @"ModTime": @"2026-07-11T10:00:00Z" },
                        @{ @"Name": @"shared.txt", @"Path": @"shared.txt", @"IsDir": @NO,
                           @"Size": @8, @"ModTime": @"2026-07-11T10:00:00Z" },
                        @{ @"Name": @"meeting:notes.txt", @"Path": @"meeting:notes.txt",
                           @"IsDir": @NO, @"Size": @12 }
                    ], 0);
                }
                if ([path hasSuffix:[newer stringByAppendingString:@"/My Drive"]]) {
                    return Result(@[
                        @{ @"Name": @"shared.txt", @"Path": @"shared.txt", @"IsDir": @NO, @"Size": @9 },
                        @{ @"Name": @"history.txt", @"Path": @"history.txt", @"IsDir": @NO, @"Size": @10 }
                    ], 0);
                }
                if ([path hasSuffix:[older stringByAppendingString:@"/My Drive"]]) {
                    return Result(@[@{ @"Name": @"shared.txt", @"Path": @"shared.txt",
                                      @"IsDir": @NO, @"Size": @11 }], 0);
                }
                if ([path isEqualToString:@"backup-crypt:My Drive/shared.txt"]) {
                    return Result(@{ @"Name": @"shared.txt", @"Path": @"shared.txt",
                                    @"IsDir": @NO, @"Size": @8 }, 0);
                }
                if ([path containsString:[newer stringByAppendingString:@"/My Drive/shared.txt"]]) {
                    return Result(@{ @"Name": @"shared.txt", @"Path": @"shared.txt",
                                    @"IsDir": @NO, @"Size": @9 }, 0);
                }
                if ([path containsString:[older stringByAppendingString:@"/My Drive/shared.txt"]]) {
                    return Result(@{ @"Name": @"shared.txt", @"Path": @"shared.txt",
                                    @"IsDir": @NO, @"Size": @11 }, 0);
                }
                return Result(nil, 3);
            };

        Class catalogClass = NSClassFromString(@"GDTCryptRestoreCatalog");
        Class copierClass = NSClassFromString(@"GDTCryptRestoreCopier");
        Assert(catalogClass != Nil && copierClass != Nil,
               @"crypt restore catalog and copier are available");

        if (catalogClass) {
            SEL initSelector = NSSelectorFromString(@"initWithRemoteName:versionsSubdirectory:commandRunner:");
            typedef id (*Init)(id, SEL, NSString *, NSString *, id);
            id catalog = ((Init)[catalogClass instanceMethodForSelector:initSelector])(
                [catalogClass alloc], initSelector, @"backup-crypt", @".gdrive-versions", catalogRunner);
            NSError *error = nil;
            NSArray *root = CallList(catalog, @"childrenAtRelativePath:error:", @"", &error);
            NSSet *rootNames = [NSSet setWithArray:[root valueForKey:@"name"]];
            Assert(!error && [rootNames containsObject:@"My Drive"] &&
                   ![rootNames containsObject:@".gdrive-versions"],
                   @"crypt catalog hides its internal version tree");

            NSArray *children = CallList(catalog, @"childrenAtRelativePath:error:", @"My Drive", &error);
            NSSet *names = [NSSet setWithArray:[children valueForKey:@"name"]];
            Assert(!error && [names containsObject:@"current.txt"] &&
                   [names containsObject:@"history.txt"] && [names containsObject:@"shared.txt"] &&
                   [names containsObject:@"meeting:notes.txt"],
                   @"crypt catalog lazily merges current and sparse historical entries");

            NSArray *versions = CallList(catalog, @"versionsForRelativePath:error:",
                                         @"My Drive/shared.txt", &error);
            Assert(!error && versions.count == 3 &&
                   [versions[0][@"kind"] isEqualToString:@"current"] &&
                   [versions[1][@"runID"] isEqualToString:newer] &&
                   [versions[2][@"runID"] isEqualToString:older] &&
                   [versions[0][@"remotePath"] isEqualToString:@"backup-crypt:My Drive/shared.txt"],
                   @"crypt file versions carry safe logical remote paths newest first");

            error = nil;
            NSArray *unsafe = CallList(catalog, @"childrenAtRelativePath:error:", @"../private", &error);
            Assert(unsafe.count == 0 && error != nil,
                   @"crypt catalog rejects traversal before invoking rclone");
        }

        NSURL *physicalRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:@"gdrive-crypt-physical"] isDirectory:YES];
        NSURL *output = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:[@"gdrive-crypt-output-" stringByAppendingString:NSUUID.UUID.UUIDString]]
                                      isDirectory:YES];
        GDTInspectingFileManager *fm = [[GDTInspectingFileManager alloc] init];
        [fm createDirectoryAtURL:physicalRoot withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtURL:output withIntermediateDirectories:YES attributes:nil error:nil];
        [@"existing" writeToURL:[output URLByAppendingPathComponent:@"shared.txt"]
                      atomically:YES encoding:NSUTF8StringEncoding error:nil];

        __block BOOL cryptcheckSucceeds = YES;
        NSMutableArray<NSArray<NSString *> *> *restoreCalls = [NSMutableArray array];
        NSDictionary<NSString *, id> *(^restoreRunner)(NSString *, NSArray<NSString *> *) =
            ^NSDictionary *(NSString *command, NSArray<NSString *> *arguments) {
                [restoreCalls addObject:[@[command ?: @""] arrayByAddingObjectsFromArray:arguments ?: @[]]];
                if ([arguments.firstObject isEqualToString:@"copyto"] && arguments.count >= 3) {
                    [@"restored plaintext" writeToFile:arguments[2] atomically:YES
                                               encoding:NSUTF8StringEncoding error:nil];
                    return Result(nil, 0);
                }
                if ([arguments.firstObject isEqualToString:@"cryptcheck"]) {
                    return Result(nil, cryptcheckSucceeds ? 0 : 1);
                }
                return Result(nil, 64);
            };

        if (copierClass) {
            SEL initSelector = NSSelectorFromString(@"initWithRemoteName:backupRootURL:fileManager:commandRunner:");
            typedef id (*Init)(id, SEL, NSString *, NSURL *, NSFileManager *, id);
            id copier = ((Init)[copierClass instanceMethodForSelector:initSelector])(
                [copierClass alloc], initSelector, @"backup-crypt", physicalRoot, fm, restoreRunner);
            SEL restoreSelector = NSSelectorFromString(@"restoreRemotePath:name:toDirectoryURL:error:");
            typedef NSDictionary *(*Restore)(id, SEL, NSString *, NSString *, NSURL *, NSError **);
            Restore restore = (Restore)[copier methodForSelector:restoreSelector];
            NSError *error = nil;
            NSDictionary *result = restore(copier, restoreSelector,
                @"backup-crypt:My Drive/shared.txt", @"shared.txt", output, &error);
            NSURL *destination = result[@"destinationURL"];
            Assert(!error && [destination.lastPathComponent isEqualToString:@"shared restored.txt"] &&
                   [result[@"sha256"] length] == 64,
                   @"crypt restore collision-proofs and publishes only a verified plaintext file");
            BOOL usedCopy = NO, usedCryptcheck = NO, exposedSecret = NO;
            for (NSArray<NSString *> *call in restoreCalls) {
                usedCopy |= [call containsObject:@"copyto"];
                usedCryptcheck |= [call containsObject:@"cryptcheck"];
                for (NSString *argument in call) {
                    exposedSecret |= [argument.lowercaseString containsString:@"password"];
                }
            }
            Assert(usedCopy && usedCryptcheck && !exposedSecret,
                   @"crypt restore delegates decryption and integrity checking to rclone without passwords");
            Assert(!fm.trashedNonemptyFilesList,
                   @"crypt restore clears its temporary plaintext file list before Trash");

            NSUInteger before = [fm contentsOfDirectoryAtURL:output
                                  includingPropertiesForKeys:nil options:0 error:nil].count;
            fm.trashedNonemptyFilesList = NO;
            cryptcheckSucceeds = NO;
            error = nil;
            NSDictionary *failed = restore(copier, restoreSelector,
                @"backup-crypt:My Drive/shared.txt", @"shared.txt", output, &error);
            NSUInteger after = [fm contentsOfDirectoryAtURL:output
                                 includingPropertiesForKeys:nil options:0 error:nil].count;
            Assert(!failed && error.code == 4 && before == after,
                   @"failed cryptcheck never publishes a restored file");
            Assert(!fm.trashedNonemptyFilesList,
                   @"failed cryptcheck also clears its temporary plaintext file list");

            NSUInteger callsBefore = restoreCalls.count;
            error = nil;
            NSDictionary *unsafe = restore(copier, restoreSelector,
                @"backup-crypt:../private.txt", @"private.txt", output, &error);
            Assert(!unsafe && error != nil && restoreCalls.count == callsBefore,
                   @"crypt copier rejects unsafe remote paths before invoking rclone");
        }

        if (catalogClass) {
            NSString *fakeBin = [output.path stringByAppendingPathComponent:@"fake-bin"];
            [fm createDirectoryAtPath:fakeBin withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *fakeRclone = [fakeBin stringByAppendingPathComponent:@"rclone"];
            NSString *script =
                @"#!/bin/sh\n"
                 "if [ \"$2\" = \"backup-crypt:.gdrive-versions\" ]; then\n"
                 "  printf '[]'\n"
                 "  exit 0\n"
                 "fi\n"
                 "/usr/bin/awk 'BEGIN { printf \"[\"; for (i=0; i<30000; i++) { "
                 "if (i) printf \",\"; printf \"{\\\"Name\\\":\\\"file-%05d.txt\\\","
                 "\\\"Path\\\":\\\"file-%05d.txt\\\",\\\"IsDir\\\":false}\", i, i; } "
                 "printf \"]\" }'\n";
            [script writeToFile:fakeRclone atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [fm setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:fakeRclone error:nil];
            NSString *originalPath = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
            setenv("PATH", fakeBin.fileSystemRepresentation, 1);
            SEL productionSelector = NSSelectorFromString(
                @"productionCatalogWithRemoteName:versionsSubdirectory:");
            typedef id (*ProductionCatalog)(id, SEL, NSString *, NSString *);
            id productionCatalog = ((ProductionCatalog)[catalogClass
                methodForSelector:productionSelector])(catalogClass, productionSelector,
                                                        @"backup-crypt", @".gdrive-versions");
            NSError *largeError = nil;
            NSArray *largeListing = CallList(productionCatalog,
                @"childrenAtRelativePath:error:", @"", &largeError);
            Assert(!largeError && largeListing.count == 30000,
                   @"production restore drains large rclone listings without a pipe deadlock");
            setenv("PATH", originalPath.fileSystemRepresentation, 1);
        }

        [fm trashItemAtURL:physicalRoot resultingItemURL:nil error:nil];
        [fm trashItemAtURL:output resultingItemURL:nil error:nil];
    }
    if (failures) {
        printf("%d crypt restore support test(s) failed.\n", failures);
        return 1;
    }
    printf("All crypt restore support tests passed.\n");
    return 0;
}
