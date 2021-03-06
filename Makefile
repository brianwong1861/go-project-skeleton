VERBOSE_ORIGINS := "command line" "environment"
ifdef V
  ifeq ($(filter $(VERBOSE_ORIGINS),$(origin V)),)
    BUILD_VERBOSE := $(V)
  endif
endif

ifndef BUILD_VERBOSE
  BUILD_VERBOSE := 0
endif

ifeq ($(BUILD_VERBOSE),1)
  Q :=
else
  Q := @
endif

PHONY += all test clean docker docker-push dockers dockers-push
CURDIR := $(shell pwd)
BUILD_DIR ?= $(CURDIR)/build
GOBIN_DIR := $(BUILD_DIR)/bin
HOST_DIR := $(BUILD_DIR)/host
HOSTBIN_DIR := $(HOST_DIR)/bin
GOTOOLSBIN_DIR := $(HOSTBIN_DIR)
GOTOOLS_DIR := $(CURDIR)/tools
TMP_DIR := $(BUILD_DIR)/tmp
DIRS := \
	$(GOBIN_DIR) \
	$(HOST_DIR) \
	$(HOSTBIN_DIR) \
	$(TMP_DIR)

HOST_OS := $(shell uname -s)

# Define your docker repository
DOCKER_REPOSITORY ?= quay.io/alan/$(notdir $(CURDIR))
REV ?= $(shell git rev-parse --short HEAD 2> /dev/null)
GOPATH ?= $(shell go env GOPATH)

export PATH:=$(GOTOOLS_DIR):$(HOSTBIN_DIR):$(PATH)
export REV

define app-docker-image-name
$(if $(filter-out all,$(1)), \
  $(DOCKER_REPOSITORY)-$(1):$(REV), \
  $(DOCKER_REPOSITORY):$(REV)\
)
endef

define find-subdir
$(shell find $(1) -maxdepth 1 -mindepth 1 -type d -o -type l)
endef

APPS := $(sort $(notdir $(call find-subdir,cmd)))
PHONY += $(APPS)

all: $(APPS)

.SECONDEXPANSION:
$(APPS): $(addprefix $(GOBIN_DIR)/,$$@)

$(DIRS) :
	$(Q)mkdir -p $@

$(GOBIN_DIR)/%: $(GOBIN_DIR) FORCE
	$(Q)go build -o $@ ./cmd/$(notdir $@)
	@echo "Done building."
	@echo "Run \"$(subst $(CURDIR),.,$@)\" to launch $(notdir $@)."

include $(wildcard build/*.mk)

CODEGEN_DEPS := \
	$(GOTOOLS_DIR)/mockgen \
	$(GOTOOLS_DIR)/protoc-gen-go \
	$(PROTOC)

.PHONY: gen
gen: $(CODEGEN_DEPS)
	$(Q)go generate -x ./...

dockers: $(addsuffix -docker,$(APPS))
%-docker:
	$(eval APP=$(subst -docker,,$@))
	$(Q)docker build --build-arg APP=$(APP) -t $(call app-docker-image-name,$(APP)) .

docker:
	$(Q)docker build -t $(DOCKER_REPOSITORY):$(REV) .

dockers-push: $(addsuffix -docker-push,$(APPS))
%-docker-push:
	$(eval APP=$(subst -docker,,$@))
	$(Q)docker push $(call app-docker-image-name,$(APP))

docker-push:
	$(Q)docker push $(DOCKER_REPOSITORY):$(REV)

test:
	$(Q)go test -v ./...

clean:
	$(Q)rm -fr $(GOBIN_DIR) $(HOST_DIR)

.PHONY: help
help:
	@echo  'Generic targets:'
	@echo  '  all                         - Build all targets marked with [*]'
	@for app in $(APPS); do \
		printf "* %s\n" $$app; done
	@echo  ''
	@echo  'Code generation targets:'
	@echo  '  gen                         - Generate API code from .proto files and mocks'
	@echo  ''
	@echo  'Docker targets:'
	@echo  '  dockers                     - Build docker images marked with [*]'
	@for app in $(APPS); do \
		printf "* %-20s        - Build %s\n" $$app-docker $(call app-docker-image-name,$$app); done
	@echo  '  docker                      - Build single docker image which includes all executables'
	@echo  ''
	@echo  '  dockers-push                - Push docker images marked with [*]'
	@for app in $(APPS); do \
		printf "* %-20s        - Push %s\n" $$app-docker-push $(call app-docker-image-name,$$app); done
	@echo  '  docker-push                 - Push $(DOCKER_REPOSITORY):$(REV)'
	@echo  ''
	@echo  'Test targets:'
	@echo  '  test                        - Run all tests'
	@echo  ''
	@echo  'Cleaning targets:'
	@echo  '  clean                       - Remove built executables'
	@echo  ''
	@echo  'Execute "make" or "make all" to build all targets marked with [*] '
	@echo  'For further info see the ./README.md file'

.PHONY: $(PHONY)

.PHONY: FORCE
FORCE:
