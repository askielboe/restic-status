.PHONY: build bundle install clean run

APP_NAME := ResticStatus

build:
	swift build -c release

bundle: build
	rm -rf $(APP_NAME).app
	mkdir -p $(APP_NAME).app/Contents/MacOS
	mkdir -p $(APP_NAME).app/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/
	cp Info.plist $(APP_NAME).app/Contents/
	cp AppIcon.icns $(APP_NAME).app/Contents/Resources/

install: bundle
	rm -rf /Applications/$(APP_NAME).app
	cp -r $(APP_NAME).app /Applications/

clean:
	rm -rf .build $(APP_NAME).app

run:
	swift build && .build/debug/$(APP_NAME)
