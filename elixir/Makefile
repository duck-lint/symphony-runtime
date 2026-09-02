.PHONY: help all setup deps audit build artifact fmt fmt-check lint test coverage ci dialyzer e2e

MIX ?= mix

# Mix writes native dependency output below MIX_BUILD_ROOT. The source checkout
# is shared by Windows and WSL, so the root must be outside the checkout and
# include an OS discriminator. This prevents a Windows NIF from being reused by
# a Linux BEAM (or vice versa) without requiring manual cleanup.
ifeq ($(OS),Windows_NT)
MIX_PLATFORM := windows
MIX_STATE_ROOT ?= $(LOCALAPPDATA)/symphony-runtime/mix
else
MIX_PLATFORM := linux
MIX_STATE_ROOT ?= $(HOME)/.local/state/symphony-runtime/mix
endif

export MIX_BUILD_ROOT := $(MIX_STATE_ROOT)/$(MIX_PLATFORM)/_build

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
