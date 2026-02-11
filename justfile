app_name := "ResticStatus"

build:
    swift build -c release

bundle: build
    rm -rf {{app_name}}.app
    mkdir -p {{app_name}}.app/Contents/MacOS
    mkdir -p {{app_name}}.app/Contents/Resources
    cp .build/release/{{app_name}} {{app_name}}.app/Contents/MacOS/
    cp Info.plist {{app_name}}.app/Contents/
    cp AppIcon.icns {{app_name}}.app/Contents/Resources/

install: bundle
    rm -rf /Applications/{{app_name}}.app
    cp -r {{app_name}}.app /Applications/

clean:
    rm -rf .build {{app_name}}.app

run:
    swift build && .build/debug/{{app_name}}

test:
    swift test
