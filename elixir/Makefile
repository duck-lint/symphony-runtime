.PHONY: help all setup deps audit build artifact fmt fmt-check lint test coverage ci dialyzer e2e

MIX ?= mix

# mix.exs owns the default OS-separated build root. Keeping that decision at
# Mix's project boundary protects direct `mix ...` invocations as well as these
# Make targets. MIX_BUILD_ROOT remains available as an explicit override.

help:
	@echo "Targets: setup, deps, audit, build, artifact, fmt, fmt-check, lint, test, coverage, dialyzer, e2e, ci"

setup:
	$(MIX) setup

deps:
	$(MIX) deps.get

audit:
	$(MIX) hex.audit

build:
	$(MIX) build

artifact:
	bash scripts/check_artifact_prereqs.sh
	MIX_ENV=prod BURRITO_TARGET=linux_x86_64 $(MIX) release symphony --overwrite
	mkdir -p bin
	install -m 0755 burrito_out/symphony_linux_x86_64 bin/symphony

fmt:
	$(MIX) format

fmt-check:
	$(MIX) format --check-formatted

lint:
	$(MIX) lint

coverage:
	$(MIX) test --cover

test:
	$(MIX) test

dialyzer:
	$(MIX) deps.get
	$(MIX) dialyzer --format short

e2e:
	SYMPHONY_RUN_LIVE_E2E=1 $(MIX) test test/symphony_elixir/live_e2e_test.exs

ci:
	$(MAKE) setup
	$(MAKE) audit
	$(MAKE) build
	$(MAKE) fmt-check
	$(MAKE) lint
	$(MAKE) coverage
	$(MAKE) dialyzer

all: ci
