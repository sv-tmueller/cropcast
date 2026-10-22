.PHONY: app install uninstall test clean

app:
	scripts/bundle.sh

# Installs into /Applications; override with CROPCAST_INSTALL_DIR=<dir>.
# Refuses root up front so 'sudo make install' cannot leave root-owned build/.
install:
	@[ "$$(id -u)" -ne 0 ] || { echo "error: do not run as root (use CROPCAST_INSTALL_DIR=\"\$$HOME/Applications\" instead)" >&2; exit 1; }
	$(MAKE) app
	scripts/install.sh install

uninstall:
	scripts/install.sh uninstall

test:
	scripts/swift-test.sh .

clean:
	rm -rf build
