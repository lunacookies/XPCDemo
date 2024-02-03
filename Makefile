all: app tidy

app: clean Sources/XPCDemo.m Sources/XPCDemo-Info.plist Sources/XPCDemo.entitlements Sources/MyService.m Sources/MyService-Info.plist Sources/MyService.entitlements
	mkdir -p Products/XPCDemo.app/Contents/MacOS
	mkdir -p Products/XPCDemo.app/Contents/XPCServices/MyService.xpc/Contents/MacOS
	#
	cp Sources/XPCDemo-Info.plist   Products/XPCDemo.app/Contents/Info.plist
	cp Sources/MyService-Info.plist Products/XPCDemo.app/Contents/XPCServices/MyService.xpc/Contents/Info.plist
	#
	plutil -convert binary1 Products/XPCDemo.app/Contents/Info.plist
	plutil -convert binary1 Products/XPCDemo.app/Contents/XPCServices/MyService.xpc/Contents/Info.plist
	#
	clang -framework Foundation -o Products/XPCDemo.app/Contents/MacOS/XPCDemo                                      Sources/XPCDemo.m
	clang -framework Foundation -o Products/XPCDemo.app/Contents/XPCServices/MyService.xpc/Contents/MacOS/MyService Sources/MyService.m
	#
	codesign --sign - --entitlements Sources/XPCDemo.entitlements   --options runtime Products/XPCDemo.app/Contents/MacOS/XPCDemo
	codesign --sign - --entitlements Sources/MyService.entitlements --options runtime Products/XPCDemo.app/Contents/XPCServices/MyService.xpc/Contents/MacOS/MyService

clean:
	rm -rf Products

tidy: Sources/XPCDemo.m Sources/MyService.m
	clang-format -i $^

.PHONY: all app clean tidy
