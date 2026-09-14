SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CXX := $(shell xcrun --sdk iphoneos -f clang++)
PRODUCT := AZ.GPS.PRO
IOS_MIN := 12.0
SOURCES := src/Location/Core.mm src/UI/UI.mm src/Audit/Audit.mm src/Shared/Portable.cpp src/Identity/Identity.mm
HEADERS := $(wildcard src/*/*.h)
INCLUDES := -Isrc/Location -Isrc/UI -Isrc/Audit -Isrc/Shared -Isrc/Identity
FLAGS := -isysroot $(SDK) -arch arm64 -miphoneos-version-min=$(IOS_MIN) -fobjc-arc -std=c++17 -O2 -Wall -Wextra
.PHONY: all test clean
all: build/$(PRODUCT).dylib
build/$(PRODUCT).dylib: $(SOURCES) $(HEADERS) Makefile
	mkdir -p build
	$(CXX) $(FLAGS) $(INCLUDES) -dynamiclib $(SOURCES) -framework Foundation -framework UIKit -framework CoreLocation -framework MapKit -framework CoreGraphics -framework QuartzCore -Wl,-install_name,@rpath/$(PRODUCT).dylib -o $@
	codesign --force --sign - $@
test:
	mkdir -p build
	c++ -std=c++17 -Wall -Wextra tests/AllTests.cpp src/Shared/Portable.cpp -o build/math-tests
	./build/math-tests
clean:
	rm -rf build

