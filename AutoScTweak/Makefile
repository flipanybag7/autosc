TARGET := AutoScTweak.dylib
SDK := /Applications/Xcode_15.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.5.sdk

all: $(TARGET)

$(TARGET): AutoScTweak.c
	clang -arch arm64 \
		-isysroot $(SDK) \
		-dynamiclib \
		-current_version 1.0 \
		-compatibility_version 1.0 \
		-framework CoreFoundation \
		-o $(TARGET) AutoScTweak.c

clean:
	rm -f $(TARGET)
