.PHONY: all test clean

all: test

test:
	swift test --package-path SquareKit

clean:
	swift package --package-path SquareKit clean
	rm -rf SquareKit/.build
