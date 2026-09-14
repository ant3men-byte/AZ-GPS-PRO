#import <Foundation/Foundation.h>
/// Thread-safe gate. No cached/offline authorization across launches.
BOOL AZLicenseCanRun(void);
@interface AZLicenseManager : NSObject
+ (instancetype)sharedManager;
- (void)start;
- (void)verify;
- (void)activateCode:(NSString *)code;
- (void)showActivation;
@end
