#include "../src/Shared/Portable.h"
#include "../src/Licensing/LicenseSessionPolicy.h"
#include <cstdio>
#include <cmath>
#include <string>

static int wf_failures = 0;
static int wf_checks   = 0;

#define AZ_CHECK(cond, msg) do { ++wf_checks;                                   \
    if (!(cond)) { ++wf_failures;                                               \
        std::printf("FAIL: %s (line %d)\n", msg, __LINE__); } } while (0)

#define AZ_CHECK_NEAR(actual, expected, eps, msg) do { ++wf_checks;             \
    double _a = (actual), _e = (expected), _d = (eps);                          \
    if (!(std::fabs(_a - _e) <= _d)) { ++wf_failures;                           \
        std::printf("FAIL: %s (line %d): actual=%f expected=%f\n",              \
                    msg, __LINE__, _a, _e); } } while (0)

static int wf_report(const char *suite) {
    std::printf("[%s] %d checks, %d failures\n", suite, wf_checks, wf_failures);
    return wf_failures == 0 ? 0 : 1;
}

int main() {
    using namespace azgps;

    // ---- Location schema validation ----
    AZ_CHECK(validateFavorite("azgps.location/1", true, true, true, true, 52.52, 13.405),
             "valid favorite accepted");
    AZ_CHECK(!validateFavorite("wrong-schema/9", true, true, true, true, 0, 0),
             "wrong schema rejected");
    AZ_CHECK(!validateFavorite("azgps.location/1", false, true, true, true, 0, 0),
             "non-string id rejected");
    AZ_CHECK(!validateFavorite("azgps.location/1", true, true, false, true, 0, 0),
             "non-numeric latitude rejected");
    AZ_CHECK(!validateFavorite("azgps.location/1", true, true, true, false, 0, 0),
             "non-numeric longitude rejected");
    AZ_CHECK(!validateFavorite("azgps.location/1", true, true, true, true, 95.0, 0),
             "out-of-range latitude rejected");
    AZ_CHECK(!validateFavorite("azgps.location/1", true, true, true, true, 0, 200.0),
             "out-of-range longitude rejected");
    AZ_CHECK(validateFavorite("azgps.location/1", true, true, true, true, -90.0, 180.0),
             "boundary coordinates accepted");
    AZ_CHECK(!validateFavorite("azgps.location/1", true, true, true, true, 90.0001, 0),
             "just-outside boundary rejected");

    // ---- Licensing session lifecycle ----
    AZ_CHECK(!licenseNeedsForegroundVerification(true,100,1799), "short background does not reverify");
    AZ_CHECK(licenseNeedsForegroundVerification(true,100,1900), "30 minute background reverifies");
    AZ_CHECK(licenseNeedsForegroundVerification(false,0,100), "unverified process verifies");
    AZ_CHECK_NEAR(licensedSessionDeadline(500,1000,11800,2),11298,0.001,
                  "verified server time maps expiration to monotonic deadline");
    AZ_CHECK_NEAR(licensedSessionDeadline(500,1000,11800,2),11298,0.001,
                  "device wall clock is absent from deadline calculation");

    return wf_report("AZGPS-AllTests");
}

