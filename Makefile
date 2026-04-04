BINARY_NAME = basic-pitch-cli
BUILD_DIR = .build/release
INSTALL_DIR = .

.PHONY: build install clean test

build:
	swift build -c release --product $(BINARY_NAME)

install: build
	cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installed: $(INSTALL_DIR)/$(BINARY_NAME)"

test:
	swift test

clean:
	swift package clean
	rm -f $(INSTALL_DIR)/$(BINARY_NAME)
