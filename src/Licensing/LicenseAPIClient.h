#import <Foundation/Foundation.h>
@interface AZLicenseAPIClient : NSObject
- (void)post:(NSString *)path body:(NSDictionary *)body completion:(void (^)(NSDictionary *,NSError *))completion;
- (NSDictionary *)validateLease:(NSDictionary *)envelope installation:(NSString *)installation bundle:(NSString *)bundle error:(NSError **)error;
@end
