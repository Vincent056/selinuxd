BIN=$(BINDIR)/selinuxdctl
BINDIR=bin
POLICYDIR=/etc/selinux.d

SRC=$(shell find . -name "*.go")

# External Helper variables

GOLANGCI_LINT_VERSION=1.33.0
GOLANGCI_LINT_OS=linux
ifeq ($(OS_NAME), Darwin)
    GOLANGCI_LINT_OS=darwin
endif
GOLANGCI_LINT_URL=https://github.com/golangci/golangci-lint/releases/download/v$(GOLANGCI_LINT_VERSION)/golangci-lint-$(GOLANGCI_LINT_VERSION)-$(GOLANGCI_LINT_OS)-amd64.tar.gz

CONTAINTER_RUNTIME?=podman

IMAGE_NAME=selinuxd
IMAGE_TAG=latest

IMAGE_REF=$(IMAGE_NAME):$(IMAGE_TAG)

IMAGE_REPO?=quay.io/jaosorior/$(IMAGE_REF)
CENTOS_IMAGE_REPO?=quay.io/jaosorior/$(IMAGE_NAME)-centos:$(IMAGE_TAG)
FEDORA_IMAGE_REPO?=quay.io/jaosorior/$(IMAGE_NAME)-fedora:$(IMAGE_TAG)

# Targets

.PHONY: all
all: build

.PHONY: build
build: $(BIN)

$(BIN): $(BINDIR) $(SRC) pkg/semodule/semanage/callbacks.c
	go build -o $(BIN) .

.PHONY: test
test:
	go test -race github.com/JAORMX/selinuxd/pkg/...

.PHONY: e2e
e2e:
	/bin/true

.PHONY: run
run: $(BIN) $(POLICYDIR)
	sudo $(BIN) daemon

.PHONY: runc
runc: image $(POLICYDIR)
	sudo $(CONTAINTER_RUNTIME) run -ti \
		--privileged \
		-v /sys/fs/selinux:/sys/fs/selinux \
		-v /var/lib/selinux:/var/lib/selinux \
		-v /etc/selinux.d:/etc/selinux.d \
		$(IMAGE_REPO) daemon

$(BINDIR):
	mkdir -p $(BINDIR)

$(POLICYDIR):
	mkdir -p $(POLICYDIR)

.PHONY: verify
verify: mod-verify verify-go-lint ## Run code lint checks

.PHONY: mod-verify
mod-verify:
	@go mod verify

.PHONY: verify-go-lint
verify-go-lint: golangci-lint ## Verify the golang code by linting
	GOLANGCI_LINT_CACHE=/tmp/golangci-cache $(GOPATH)/bin/golangci-lint run

# Install external dependencies
.PHONY: golangci-lint
golangci-lint: $(GOPATH)/bin/golangci-lint

$(GOPATH)/bin/golangci-lint:
	curl -L --output - $(GOLANGCI_LINT_URL) | \
		tar xz --strip-components 1 -C $(GOPATH)/bin/ golangci-lint-$(GOLANGCI_LINT_VERSION)-$(GOLANGCI_LINT_OS)-amd64/golangci-lint || \
		(echo "curl returned $$? trying to fetch golangci-lint. please install golangci-lint and try again"; exit 1); \
	GOLANGCI_LINT_CACHE=/tmp/golangci-cache $(GOPATH)/bin/golangci-lint version
	GOLANGCI_LINT_CACHE=/tmp/golangci-cache $(GOPATH)/bin/golangci-lint linters

.PHONY: image
image: default-image centos-image fedora-image

.PHONY: default-image
default-image:
	$(CONTAINTER_RUNTIME) build -f images/Dockerfile.centos -t $(IMAGE_REPO) .

.PHONY: centos-image
centos-image:
	$(CONTAINTER_RUNTIME) build -f images/Dockerfile.centos -t $(CENTOS_IMAGE_REPO) .

.PHONY: fedora-image
fedora-image:
	$(CONTAINTER_RUNTIME) build -f images/Dockerfile.fedora -t $(FEDORA_IMAGE_REPO) .

.PHONY: push
push:
	$(CONTAINTER_RUNTIME) push $(IMAGE_REPO)

.PHONY: vagrant-up
vagrant-up: ## Boot the vagrant based test VM
	if [ ! -f image.tar ]; then \
		make image IMAGE=$(IMAGE) && \
		$(CONTAINER_RUNTIME) save -o image.tar $(IMAGE); \
	fi
	ln -sf hack/ci/Vagrantfile .
	vagrant up
