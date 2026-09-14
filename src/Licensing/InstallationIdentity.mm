#import "InstallationIdentity.h"
#import <CommonCrypto/CommonDigest.h>
@interface AZInstallationIdentity ()
@property(nonatomic,readwrite,copy) NSString *installationID;
@property(nonatomic,readwrite,copy) NSString *publicKey;
@property(nonatomic) SecKeyRef privateKey;
@end
@implementation AZInstallationIdentity
- (void)dealloc { if(_privateKey)CFRelease(_privateKey); }
- (NSString *)service {return [@"AZ.GPS.PRO.licensing." stringByAppendingString:NSBundle.mainBundle.bundleIdentifier ?: @"unknown"];}
- (NSMutableDictionary *)query:(NSString *)account {
 return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:[self service],(__bridge id)kSecAttrAccount:account,(__bridge id)kSecAttrSynchronizable:@NO} mutableCopy];
}
- (NSString *)read:(NSString *)account {
 NSMutableDictionary *q=[self query:account];q[(__bridge id)kSecReturnData]=@YES;q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
 CFTypeRef value=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)q,&value);
 if(status!=errSecSuccess)return nil;NSData *data=CFBridgingRelease(value);return [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
}
- (BOOL)save:(NSString *)value account:(NSString *)account error:(NSError **)error {
 NSMutableDictionary *q=[self query:account];NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
 OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
 if(status==errSecItemNotFound){q[(__bridge id)kSecValueData]=data;q[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;status=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}
 if(status!=errSecSuccess&&error)*error=[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey:@"تعذر حفظ هوية الترخيص في Keychain. تحقق من توقيع التطبيق."}];return status==errSecSuccess;
}
- (BOOL)prepare:(NSError **)error {
 if(self.privateKey&&self.installationID.length)return YES;
 NSData *tag=[[self.service stringByAppendingString:@".signing-key"]dataUsingEncoding:NSUTF8StringEncoding];
 NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassKey,(__bridge id)kSecAttrApplicationTag:tag,(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,(__bridge id)kSecReturnRef:@YES};
 CFTypeRef key=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)q,&key);
 if(status==errSecSuccess)self.privateKey=(SecKeyRef)key;
 else if(status==errSecItemNotFound){
  CFErrorRef ce=NULL;
  SecAccessControlRef access=SecAccessControlCreateWithFlags(NULL,kSecAttrAccessibleWhenUnlockedThisDeviceOnly,kSecAccessControlPrivateKeyUsage,&ce);
  if(ce){CFRelease(ce);ce=NULL;}
  if(access){NSDictionary *attrs=@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,(__bridge id)kSecAttrKeySizeInBits:@256,(__bridge id)kSecAttrTokenID:(__bridge id)kSecAttrTokenIDSecureEnclave,(__bridge id)kSecPrivateKeyAttrs:@{(__bridge id)kSecAttrIsPermanent:@YES,(__bridge id)kSecAttrApplicationTag:tag,(__bridge id)kSecAttrAccessControl:(__bridge id)access}};
   self.privateKey=SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs,&ce);CFRelease(access);if(ce){CFRelease(ce);ce=NULL;}}
  if(!self.privateKey){NSDictionary *attrs=@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,(__bridge id)kSecAttrKeySizeInBits:@256,(__bridge id)kSecPrivateKeyAttrs:@{(__bridge id)kSecAttrIsPermanent:@YES,(__bridge id)kSecAttrApplicationTag:tag,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly}};self.privateKey=SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs,&ce);if(ce){if(error)*error=CFBridgingRelease(ce);else CFRelease(ce);}}
 }
 if(!self.privateKey){if(error&&!*error)*error=[NSError errorWithDomain:@"AZLicense" code:1 userInfo:@{NSLocalizedDescriptionKey:@"تعذر إنشاء هوية آمنة. تحقق من توقيع التطبيق وصلاحيات Keychain."}];return NO;}
 NSString *identifier=[self read:@"installation-id"];
 if(!identifier.length){identifier=NSUUID.UUID.UUIDString;if(![self save:identifier account:@"installation-id" error:error])return NO;}
 self.installationID=identifier.lowercaseString;
 SecKeyRef pub=SecKeyCopyPublicKey(self.privateKey);if(!pub)return NO;
 CFErrorRef ce=NULL;NSData *data=CFBridgingRelease(SecKeyCopyExternalRepresentation(pub,&ce));CFRelease(pub);if(ce)CFRelease(ce);
 if(data.length!=65)return NO;self.publicKey=[data base64EncodedStringWithOptions:0];return YES;
}
- (NSString *)installationIDForCode:(NSString *)code error:(NSError **)error {
 if(![self prepare:error])return nil;
 NSString *normalized=[[code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString];
 NSData *bytes=[normalized dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,hash);
 NSMutableString *account=[NSMutableString stringWithString:@"installation-code-"];for(NSUInteger i=0;i<sizeof(hash);i++)[account appendFormat:@"%02x",hash[i]];
 NSString *identifier=[self read:account];if(identifier.length)return identifier.lowercaseString;
 NSString *saved=[[self.savedCode stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]uppercaseString];
 identifier=[saved isEqualToString:normalized]?self.installationID:NSUUID.UUID.UUIDString.lowercaseString;
 if(![self save:identifier account:account error:error])return nil;return identifier;
}
- (NSString *)signMessage:(NSString *)message error:(NSError **)error {
 if(![self prepare:error])return nil;NSData *data=[message dataUsingEncoding:NSUTF8StringEncoding];CFErrorRef ce=NULL;
 NSData *signature=CFBridgingRelease(SecKeyCreateSignature(self.privateKey,kSecKeyAlgorithmECDSASignatureMessageX962SHA256,(__bridge CFDataRef)data,&ce));
 if(ce){if(error)*error=CFBridgingRelease(ce);else CFRelease(ce);}return [signature base64EncodedStringWithOptions:0];
}
- (NSString *)savedCode {return [self read:@"license-code"];}
- (BOOL)saveCode:(NSString *)code error:(NSError **)error {return [self save:code account:@"license-code" error:error];}
@end
