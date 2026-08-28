.PHONY: all test clean worker-dev worker-test worker-typecheck worker-deploy

all: test

test:
	swift test --package-path SquareKit

# --- Cloudflare Worker backend (worker/), see BACKEND_PLAN.md ---------------
worker-dev:
	npm --prefix worker run dev

worker-test:
	npm --prefix worker test

worker-typecheck:
	npm --prefix worker run typecheck

worker-deploy:
	npm --prefix worker run deploy

clean:
	swift package --package-path SquareKit clean
	rm -rf SquareKit/.build worker/node_modules
