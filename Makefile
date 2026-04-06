BUILD_DIR = .build/release
DOCS_DIR  = docs
TARGET  = BasicPitch
BIN_DIR   = bin
SWIFTC    = swiftc -O -framework Metal -framework Accelerate
SWIFTC_LIB = $(SWIFTC) -parse-as-library

.PHONY: build install clean test docs docs-llm stemroll stemroll-open

build:
	swift build -c release --disable-sandbox
	./scripts/build_mlx_metallib.sh release

docs:
	@mkdir -p $(DOCS_DIR)
	swift package --allow-writing-to-directory $(DOCS_DIR) \
		generate-documentation \
		--target $(TARGET) \
		--output-path $(DOCS_DIR)/$(TARGET).doccarchive

docs-llm:
	@mkdir -p $(DOCS_DIR)
	swift build --target $(TARGET) \
		-Xswiftc -enable-library-evolution \
		-Xswiftc -emit-module-interface-path \
		-Xswiftc $(PWD)/$(DOCS_DIR)/$(TARGET).swiftinterface \
		-Xswiftc -no-verify-emitted-module-interface
	@echo "Swift interface written to $(DOCS_DIR)/$(TARGET).swiftinterface"

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

stemroll:
	cd Stemroll && xcodebuild -scheme Stemroll -configuration Debug -derivedDataPath ../.build/stemroll build

stemroll-open: stemroll
	open .build/stemroll/Build/Products/Debug/Stemroll.app
