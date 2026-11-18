DC      ?= ldc2
JAVAC   ?= javac
JAR     ?= jar
JAVA    ?= java

DFLAGS      ?= -O -release -w -de
TEST_DFLAGS ?= -O -w -de

RING_FILES = src/domain.d src/services.d src/infra.d
APP_FILES  = src/entry.d

JAVA_SOURCES      = $(wildcard java/redhot/core/*.java)
JAVA_MAIN_SOURCES = $(filter-out %Test.java,$(JAVA_SOURCES))
JAVA_TEST_SOURCES = $(wildcard java/redhot/core/*Test.java)

REDHOT_CORE_JAR_ABSOLUTE = $(abspath redhot-core.jar)

all: libredhot.a redhot-base redhot-core.jar

# --- D layer ---------------------------------------------------------------

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

# --- Java layer ------------------------------------------------------------

redhot-core.jar: $(JAVA_MAIN_SOURCES)
	mkdir -p build/java
	$(JAVAC) --release 17 -d build/java $(JAVA_MAIN_SOURCES)
	cd build/java && $(JAR) --create --file ../../$@ .

# Application Class-Data Sharing archive. Regenerated after installation at
# the final install path; the dev-time .jsa is a smoke check only.
redhot.jsa: redhot-core.jar
	$(JAVA) -Xshare:off -XX:DumpLoadedClassList=build/classes.lst \
		-cp $(REDHOT_CORE_JAR_ABSOLUTE) redhot.core.WarmupMain >/dev/null
	$(JAVA) -Xshare:dump \
		-XX:SharedClassListFile=build/classes.lst \
		-XX:SharedArchiveFile=redhot.jsa \
		-cp $(REDHOT_CORE_JAR_ABSOLUTE) >/dev/null

build/java_test: $(JAVA_MAIN_SOURCES) $(JAVA_TEST_SOURCES)
	mkdir -p build/java_test
	$(JAVAC) --release 17 -d build/java_test \
		$(JAVA_MAIN_SOURCES) $(JAVA_TEST_SOURCES)

# --- Test targets ----------------------------------------------------------

test-d: build/unit_domain build/contract redhot-base
	./build/unit_domain
	./build/contract

test-java: build/java_test
	$(JAVA) -cp build/java_test redhot.core.RParseTest

test: test-d test-java

clean:
	rm -rf libredhot.a redhot-base redhot-core.jar redhot.jsa build

ensure-base:
	./scripts/ensure-base.sh

.PHONY: all test test-d test-java clean ensure-base

# --- Install ---------------------------------------------------------------
# Copies library artifacts to /usr/local/. Requires root (doas/sudo).
# redhot.jsa is regenerated at the final path, not copied — CDS archives
# embed absolute paths and would be invalid after the move.
INSTALL_PREFIX         = /usr/local
INSTALL_LIBDIR         = $(INSTALL_PREFIX)/lib/redhot
INSTALL_BINDIR         = $(INSTALL_PREFIX)/bin

install: all
	mkdir -p $(INSTALL_LIBDIR) $(INSTALL_BINDIR)
	install -m 0644 libredhot.a       $(INSTALL_LIBDIR)/libredhot.a
	install -m 0644 redhot-core.jar   $(INSTALL_LIBDIR)/redhot-core.jar
	install -m 0755 redhot-base       $(INSTALL_BINDIR)/redhot-base
	$(JAVA) -Xshare:off -XX:DumpLoadedClassList=/tmp/redhot-classes.lst \
		-cp $(INSTALL_LIBDIR)/redhot-core.jar redhot.core.WarmupMain >/dev/null
	$(JAVA) -Xshare:dump \
		-XX:SharedClassListFile=/tmp/redhot-classes.lst \
		-XX:SharedArchiveFile=$(INSTALL_LIBDIR)/redhot.jsa \
		-cp $(INSTALL_LIBDIR)/redhot-core.jar >/dev/null
	rm -f /tmp/redhot-classes.lst
	mkdir -p $(INSTALL_LIBDIR)/src
	install -m 0644 src/*.d $(INSTALL_LIBDIR)/src/
	@echo "[ OK ] installed to $(INSTALL_LIBDIR) and $(INSTALL_BINDIR)"

uninstall:
	rm -f $(INSTALL_LIBDIR)/libredhot.a
	rm -f $(INSTALL_LIBDIR)/redhot-core.jar
	rm -f $(INSTALL_LIBDIR)/redhot.jsa
	rm -f $(INSTALL_BINDIR)/redhot-base
	@echo "[ OK ] uninstalled"

.PHONY: install uninstall
