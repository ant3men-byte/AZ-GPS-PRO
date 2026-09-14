#include "Portable.h"
#include <cmath>

namespace azgps {

bool validateFavorite(const std::string& schema, bool idIsString, bool nameIsString,
                      bool latIsNumber, bool lonIsNumber, double lat, double lon) {
    if (schema != "azgps.location/1") return false;
    if (!idIsString || !nameIsString)  return false;
    if (!latIsNumber || !lonIsNumber)  return false;   // type validation
    if (lat < -90.0 || lat > 90.0)     return false;   // range validation
    if (lon < -180.0 || lon > 180.0)   return false;
    return true;
}

} // namespace azgps

