BUILD_DIR = .build/release

.PHONY: build install clean test

build:
	swift build -c release --disable-sandbox
	./scripts/build_mlx_metallib.sh release

install: build
	cp $(BUILD_DIR)/basic-pitch-cli .
	cp $(BUILD_DIR)/basic-pitch-demucs-cli .
	cp $(BUILD_DIR)/mlx.metallib .
	@echo "Installed: basic-pitch-cli, basic-pitch-demucs-cli"

test:
	swift test

clean:
	swift package clean
	rm -f basic-pitch-cli basic-pitch-demucs-cli mlx.metallib
