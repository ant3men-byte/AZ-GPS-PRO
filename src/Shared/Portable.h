#pragma once
// Portable, dependency-free primitives shared by iOS and Linux tests.
#include <string>

namespace azgps {

struct Coordinate {
    double latitude  = 0.0;
    double longitude = 0.0;
    bool   isValid() const {
        return latitude >= -90.0 && latitude <= 90.0
            && longitude >= -180.0 && longitude <= 180.0;
    }
};

// --- Location schema validation (mirrors AZLocationModel rules, §27) ---
struct Favorite { std::string id, name; double lat, lon; };
bool validateFavorite(const std::string& schema, bool idIsString, bool nameIsString,
                      bool latIsNumber, bool lonIsNumber, double lat, double lon);

} // namespace azgps

