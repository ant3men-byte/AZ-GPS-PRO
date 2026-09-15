#pragma once
namespace azgps {
inline bool licenseNeedsForegroundVerification(bool verified,double backgroundAt,double now){
 if(!verified)return true;
 return backgroundAt>0&&now-backgroundAt>=1800.0;
}
inline double licensedSessionDeadline(double monotonicNow,double serverTime,double expiresAt,double requestElapsed){
 return monotonicNow+(expiresAt-serverTime)-requestElapsed;
}
}
#define AZLicenseNeedsForegroundVerification azgps::licenseNeedsForegroundVerification
