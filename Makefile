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

test-new:
	@pkill -x Sirius 2>/dev/null || true
	@open dist/Sirius.app
	@echo "==> 已切换至新特性版本 (dist/Sirius.app)"

restore-stable:
	@pkill -x Sirius 2>/dev/null || true
	@open /Applications/Sirius.app
	@echo "==> 已切回已安装的正式版 (/Applications/Sirius.app)"

clean:
	swift package clean
	rm -rf dist .build
