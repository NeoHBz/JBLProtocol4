# JBL Control: local build, test, sign, install. Same targets run locally and in GitHub Actions.
#
#   make                    build Debug, sign, relaunch  (the inner loop)
#   make help               every target
#   make build:test         chain targets with colons; runs them in order
#
# NOTHING PERSONAL LIVES IN THIS FILE OR IN THE REPO. Anything that is yours comes from the environment:
#
#   JBL_SIGN_IDENTITY   name of the signing certificate   (default: "JBL Control Dev Signing")
#   JBL_BUNDLE_ID       bundle identifier                 (default: local.jblcontrol)
#   JBL_VERSION         shown in About and the zip name   (default: 0.1.0)
#
# Locally, put overrides in mac/JBLControl/local.mk (git-ignored, see local.mk.example) or in your shell profile.
# On GitHub they come from Actions secrets/variables (.github/workflows/build.yml), and the signing certificate
# itself arrives as the secret JBL_CERT_P12_BASE64. With no secrets the workflow still builds, signed ad-hoc.
#
# WHY A CERTIFICATE AT ALL: macOS files the Bluetooth permission under the app's signature. Ad-hoc signatures change
# on every build, so every rebuild would ask for Bluetooth access again. One self-signed certificate (`make cert`,
# no Apple account) keeps the app the same app across builds.

-include local.mk

APP_NAME      := JBLControl
# `$(or ...)` instead of `?=`: GitHub Actions passes an unset variable as an EMPTY string, which `?=` would keep.
JBL_SIGN_IDENTITY := $(or $(JBL_SIGN_IDENTITY),JBL Control Dev Signing)
JBL_BUNDLE_ID     := $(or $(JBL_BUNDLE_ID),local.jblcontrol)
JBL_VERSION       := $(or $(JBL_VERSION),0.1.0)
export JBL_SIGN_IDENTITY JBL_BUNDLE_ID JBL_VERSION

OUT       := build
DEBUG_APP := $(OUT)/Debug/$(APP_NAME).app
REL_APP   := $(OUT)/Release/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app
SCRIPTS   := scripts

.DEFAULT_GOAL := dev
.PHONY: help dev run stop test build sign install zip cert cert-status cert-export clean

# colon-chained goals: `make build:test` runs build, then test, stopping at the first failure.
CHAINED := $(strip $(foreach g,$(MAKECMDGOALS),$(if $(findstring :,$(g)),$(g))))
ifneq ($(CHAINED),)
.PHONY: $(subst :,\:,$(CHAINED))
$(subst :,\:,$(CHAINED)):
	@$(MAKE) --no-print-directory -j1 $(subst :, ,$@)
endif

## help — list every target
help:
	@echo "JBL Control"; echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
	@echo ""; echo "  Signed with:  $(JBL_SIGN_IDENTITY)"
	@printf '  Status:       '
	@$(SCRIPTS)/signing-cert.sh status >/dev/null 2>&1 && echo "installed" || echo "NOT INSTALLED, run 'make cert' once"

## dev — build Debug, sign, relaunch. This is what plain `make` does.
dev:
	@$(SCRIPTS)/bundle.sh debug "$(DEBUG_APP)"
	@$(SCRIPTS)/sign-app.sh "$(DEBUG_APP)"
	@$(MAKE) --no-print-directory stop
	@sleep 1
	@open "$(DEBUG_APP)"
	@echo "→ $(APP_NAME) relaunched (Debug). It lives in the menu bar, there is no window."

## run — relaunch the last Debug build without rebuilding
run: stop
	@sleep 1
	@open "$(DEBUG_APP)"

## stop — quit a running copy (dev build or installed)
stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

## test — replay the captured frames against the encoder
test:
	@mkdir -p $(OUT)
	@swift test > $(OUT)/test.log 2>&1 || { tail -20 $(OUT)/test.log; echo "❌ tests failed"; exit 1; }
	@grep -E "Executed [0-9]+ tests" $(OUT)/test.log | tail -1

## build — build Release and sign it. Refuses to ship under a substitute identity.
build:
	@$(SCRIPTS)/signing-cert.sh preflight
	@$(SCRIPTS)/bundle.sh release "$(REL_APP)"
	@JBL_STRICT_SIGN=1 $(SCRIPTS)/sign-app.sh "$(REL_APP)"

## sign — re-sign the Release build with the stable identity
sign:
	@JBL_STRICT_SIGN=1 $(SCRIPTS)/sign-app.sh "$(REL_APP)"

## install — replace /Applications/JBLControl.app with a fresh signed Release build
install: build
	@$(MAKE) --no-print-directory stop
	@rm -rf "$(INSTALLED)"
	@cp -R "$(REL_APP)" /Applications/
	@open "$(INSTALLED)"
	@echo "→ Installed to $(INSTALLED) and launched."

## zip — package the signed Release build into build/JBLControl-<version>.zip
zip: build
	@cd $(OUT)/Release && ditto -c -k --keepParent $(APP_NAME).app ../$(APP_NAME)-$(JBL_VERSION).zip
	@echo "→ $(OUT)/$(APP_NAME)-$(JBL_VERSION).zip"

## cert — create the signing certificate in your login keychain (once, no Apple account)
cert:
	@$(SCRIPTS)/signing-cert.sh create

## cert-status — is the certificate installed, and when does it expire
cert-status:
	@$(SCRIPTS)/signing-cert.sh status

## cert-export — write the certificate to a .p12 and print the commands that store it as GitHub secrets
cert-export:
	@$(SCRIPTS)/signing-cert.sh export

## clean — remove build output (never touches the certificate)
clean:
	rm -rf $(OUT) .build
