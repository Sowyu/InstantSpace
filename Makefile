.PHONY: build run install dmg clean

APP := build/SPACE.app
DMG := dist/SPACE.dmg

build:
	./build.sh

run: build
	open $(APP)

install: build
	cp -R $(APP) /Applications/

dmg: build
	chmod +x scripts/build-dmg.sh
	./scripts/build-dmg.sh

clean:
	rm -rf build dist
