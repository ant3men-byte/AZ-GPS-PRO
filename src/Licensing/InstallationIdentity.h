#import <Foundation/Foundation.h>
#import <Security/Security.h>
@interface AZInstallationIdentity : NSObject
@property(nonatomic,readonly,copy) NSString *installationID;
@property(nonatomic,readonly,copy) NSString *publicKey;
- (BOOL)prepare:(NSError **)error;
- (NSString *)installationIDForCode:(NSString *)code error:(NSError **)error;
- (NSString *)signMessage:(NSString *)message error:(NSError **)error;
- (NSString *)savedCode;
- (BOOL)saveCode:(NSString *)code error:(NSError **)error;
@end
