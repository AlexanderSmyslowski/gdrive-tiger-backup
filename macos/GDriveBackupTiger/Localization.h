#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ConfiguredLanguage(void);
FOUNDATION_EXPORT NSString *T(NSString *language, NSString *key);
FOUNDATION_EXPORT NSArray<NSString *> *SupportedLanguageCodes(void);
FOUNDATION_EXPORT NSString *LanguageDisplayName(NSString *code);

NS_ASSUME_NONNULL_END
