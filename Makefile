# 常用工程动作的快捷入口
APP := src/build/国内金价.app
BIN := $(APP)/Contents/MacOS/GoldFloat
SOURCES := $(shell find src -name '*.swift' -not -path 'src/build/*' | sort)

.PHONY: build typecheck run clean history-export

build:
	cd src && ./build.sh

typecheck:
	xcrun swiftc -typecheck -warnings-as-errors -target arm64-apple-macos12.0 \
		-module-name GoldFloat -module-cache-path src/build/.modulecache $(SOURCES)

run: build
	open "$(APP)"

history-export:
	"$(BIN)" --export-history "$(HOME)/Desktop/gold-history.csv"

clean:
	rm -rf src/build
