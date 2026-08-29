.PHONY: all test check hooks clean worker-dev worker-test worker-typecheck worker-deploy

all: test

test:
	swift test --package-path ClanTabKit

# Enable the pre-push hook (ClanTabKit + worker + iOS build/tests, run locally).
hooks:
	git config core.hooksPath .githooks
	@echo "pre-push hook enabled. Bypass with SKIP_CHECKS=1 or SKIP_APP_CHECK=1."

# Run every pre-push check now, unconditionally.
check:
	./.githooks/pre-push < /dev/null

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
	swift package --package-path ClanTabKit clean
	rm -rf ClanTabKit/.build worker/node_modules
