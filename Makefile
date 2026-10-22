.PHONY: app test clean

app:
	scripts/bundle.sh

test:
	scripts/swift-test.sh .

clean:
	rm -rf build
