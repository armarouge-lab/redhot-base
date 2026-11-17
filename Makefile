DC      ?= ldc2

DFLAGS      ?= -O -release -w -de
TEST_DFLAGS ?= -O -w -de

RING_FILES = src/domain.d src/services.d src/infra.d
APP_FILES  = src/entry.d

all: libredhot.a redhot-base

libredhot.a: $(RING_FILES)
	$(DC) $(DFLAGS) -lib -of=$@ $(RING_FILES)

redhot-base: $(APP_FILES) libredhot.a VERSION
	$(DC) $(DFLAGS) -Isrc -J. -of=$@ $(APP_FILES) libredhot.a

build/unit_domain: tests/unit_domain.d $(RING_FILES)
	mkdir -p build
	$(DC) $(TEST_DFLAGS) -Isrc -unittest -main -of=$@ \
		tests/unit_domain.d $(RING_FILES)

build/contract: tests/contract.d $(RING_FILES)
	mkdir -p build
	$(DC) $(TEST_DFLAGS) -Isrc -unittest -main -of=$@ \
		tests/contract.d $(RING_FILES)

test: build/unit_domain build/contract redhot-base
	./build/unit_domain
	./build/contract

clean:
	rm -rf libredhot.a redhot-base build

ensure-base:
	./scripts/ensure-base.sh

.PHONY: all test clean ensure-base
