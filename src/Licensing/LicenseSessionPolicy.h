#pragma once
namespace azgps {
enum class LicenseRevealAction { ShowTool, WaitForVerification, ShowActivation, VerifyThenShow };
inline LicenseRevealAction licenseRevealAction(bool authorized,bool hasSavedCode,bool verificationBusy,bool attempted){
 if(authorized)return LicenseRevealAction::ShowTool;
 if(!hasSavedCode)return LicenseRevealAction::ShowActivation;
 if(verificationBusy)return LicenseRevealAction::WaitForVerification;
 return attempted?LicenseRevealAction::ShowActivation:LicenseRevealAction::VerifyThenShow;
}
inline bool licenseNeedsForegroundVerification(bool verified,double backgroundAt,double now){
 if(!verified)return true;
 return backgroundAt>0&&now-backgroundAt>=1800.0;
}
inline double licensedSessionDeadline(double monotonicNow,double serverTime,double expiresAt,double requestElapsed){
 return monotonicNow+(expiresAt-serverTime)-requestElapsed;
}
}
#define AZLicenseNeedsForegroundVerification azgps::licenseNeedsForegroundVerification
