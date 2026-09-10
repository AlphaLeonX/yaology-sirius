.PHONY: all build release run test check app clean

all: build

build:
	swift build

release:
	swift build -c release

run:
	swift run Sirius

test: release
	./.build/release/Sirius --test

check: release
	./.build/release/Sirius --check

app:
	bash scripts/build_app.sh

dmg:
	bash scripts/package_dmg.sh

clean:
	swift package clean
	rm -rf dist .build
