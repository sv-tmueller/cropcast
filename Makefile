.PHONY: app install uninstall test clean

app:
	scripts/bundle.sh

# Installs into /Applications; override with CROPCAST_INSTALL_DIR=<dir>.
install: app
	scripts/install.sh install

uninstall:
	scripts/install.sh uninstall

test:
	scripts/swift-test.sh .

clean:
	rm -rf build
