SHELL := /bin/bash

format:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w install-docker.sh tests/smoke.sh; \
	else \
		echo "shfmt not installed; skipping"; \
	fi

lint:
	shellcheck install-docker.sh tests/smoke.sh

test:
	bash tests/smoke.sh
