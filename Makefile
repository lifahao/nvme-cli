_SOC_=NVME_CLI
INCDIR = -I ../../fw/Share/InterProcess
INCDIR += -I ../../fw/Share/Inc


CFLAGS ?= -O2 -g -Wall -Werror
CFLAGS += -std=gnu99 $(INCDIR)
CPPFLAGS += -D_GNU_SOURCE -D__CHECK_ENDIAN__
LIBUUID = $(shell $(LD) -o /dev/null -luuid >/dev/null 2>&1; echo $$?)
#INCDIR = $(shell find ../../fw -name '*.h' -exec dirname '{}' ';' | sort -u)
NVME = nvme
INSTALL ?= install
DESTDIR =
PREFIX ?= /usr/local
SYSCONFDIR = /etc
SBINDIR = $(PREFIX)/sbin
LIB_DEPENDS =
ifeq ($(LIBUUID),0)
	override LDFLAGS += -luuid
	override CFLAGS += -DLIBUUID
	override LIB_DEPENDS += uuid
endif

RPMBUILD = rpmbuild
TAR = tar
RM = rm -f
ZIP = zip -r


SRC_DIR = $(shell pwd)

DEST_DIR = $(SRC_DIR)/_out
OBJ_DIR = $(DEST_DIR)/obj



SUB_DIRS=dapu

DIRS := $(shell find dapu -maxdepth 3 -type d)

VPATH = $(DIRS)

SOURCES   = $(foreach dir, $(DIRS), $(wildcard $(dir)/*.c))
SUB_OBJS   = $(addprefix $(OBJ_DIR)/,$(patsubst %.c,%.o,$(notdir $(SOURCES))))

default: $(NVME)

NVME-VERSION-FILE: FORCE
	@$(SHELL_PATH) ./NVME-VERSION-GEN
-include NVME-VERSION-FILE
override CFLAGS += -DNVME_VERSION='"$(NVME_VERSION)"'
NVME_DPKG_VERSION=1~`lsb_release -sc`

OBJS := argconfig.o suffix.o parser.o nvme-print.o nvme-ioctl.o \
	nvme-lightnvm.o fabrics.o json.o plugin.o nvme-models.o \
	dapu-nvme.o dapumat-nvme.o ${SUB_OBJS}
#OBJS := argconfig.o suffix.o parser.o nvme-print.o nvme-ioctl.o \
	nvme-lightnvm.o fabrics.o json.o plugin.o nvme-models.o \
	dapumat-nvme.o ${SUB_OBJS}


nvme: nvme.c nvme.h $(OBJS) NVME-VERSION-FILE
	$(CC) $(CPPFLAGS) $(CFLAGS) nvme.c -o $(NVME) $(OBJS) $(LDFLAGS)

nvme.o: nvme.c nvme.h nvme-print.h nvme-ioctl.h argconfig.h suffix.h nvme-lightnvm.h fabrics.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $<

$(SRC_DIR)/%.o:%.c %.h nvme.h linux/nvme_ioctl.h nvme-ioctl.h nvme-print.h argconfig.h
	$(CC) -c $(CPPFLAGS) $(CFLAGS) -o $@ $<

$(OBJ_DIR)/%.o:%.c %.h nvme.h linux/nvme_ioctl.h nvme-ioctl.h nvme-print.h argconfig.h
	@if [ ! -d $(OBJ_DIR) ]; then mkdir -p $(OBJ_DIR); fi;\
	$(CC) -c $(CPPFLAGS) $(CFLAGS) -o $@ $<

doc: $(NVME)
	$(MAKE) -C Documentation

test:
	$(MAKE) -C tests/ run

all: doc

clean:
	rm -rf $(DEST_DIR)
	$(RM) $(NVME) *.o *~ a.out NVME-VERSION-FILE *.tar* nvme.spec version control nvme-*.deb
	$(MAKE) -C Documentation clean
	$(RM) tests/*.pyc

clobber: clean
	$(MAKE) -C Documentation clobber

install-man:
	$(MAKE) -C Documentation install-no-build

install-bin:
	$(INSTALL) -d $(DESTDIR)$(SBINDIR)
	$(INSTALL) -m 755 nvme $(DESTDIR)$(SBINDIR)

install-bash-completion:
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/bash-completion/completions
	$(INSTALL) -m 644 -T ./completions/bash-nvme-completion.sh $(DESTDIR)$(PREFIX)/share/bash-completion/completions/nvme

install: install-bin install-bash-completion


dapu: FORCE
	$(ZIP) nvme-$(NVME_VERSION).zip ./$(NVME) ./completions ./Makefile ./$(NVME) NVME-VERSION-GEN

nvme.spec: nvme.spec.in NVME-VERSION-FILE
	sed -e 's/@@VERSION@@/$(NVME_VERSION)/g' < $< > $@+
	mv $@+ $@

dist: nvme.spec
	git archive --format=tar --prefix=nvme-$(NVME_VERSION)/ HEAD > nvme-$(NVME_VERSION).tar
	@echo $(NVME_VERSION) > version
	$(TAR) rf  nvme-$(NVME_VERSION).tar nvme.spec version
	gzip -f -9 nvme-$(NVME_VERSION).tar

control: nvme.control.in NVME-VERSION-FILE
	sed -e 's/@@VERSION@@/$(NVME_VERSION)/g' < $< > $@+
	mv $@+ $@
	sed -e 's/@@DEPENDS@@/$(LIB_DEPENDS)/g' < $@ > $@+
	mv $@+ $@

pkg: control nvme.control.in
	mkdir -p nvme-$(NVME_VERSION)$(SBINDIR)
	mkdir -p nvme-$(NVME_VERSION)$(PREFIX)/share/man/man1
	mkdir -p nvme-$(NVME_VERSION)/DEBIAN/
	cp Documentation/*.1 nvme-$(NVME_VERSION)$(PREFIX)/share/man/man1
	cp nvme nvme-$(NVME_VERSION)$(SBINDIR)
	cp control nvme-$(NVME_VERSION)/DEBIAN/

# Make a reproducible tar.gz in the super-directory. Uses
# git-restore-mtime if available to adjust timestamps.
../nvme-cli_$(NVME_VERSION).orig.tar.gz:
	find . -type f -perm -u+rwx -exec chmod 0755 '{}' +
	find . -type f -perm -u+rw '!' -perm -u+x -exec chmod 0644 '{}' +
	if which git-restore-mtime >/dev/null; then git-restore-mtime; fi
	git ls-files | tar cf ../nvme-cli_$(NVME_VERSION).orig.tar \
	  --owner=root --group=root \
	  --transform='s#^#nvme-cli-$(NVME_VERSION)/#' --files-from -
	touch -d "`git log --format=%ci -1`" ../nvme-cli_$(NVME_VERSION).orig.tar
	gzip -f -9 ../nvme-cli_$(NVME_VERSION).orig.tar

dist-orig: ../nvme-cli_$(NVME_VERSION).orig.tar.gz

# Create a throw-away changelog, which dpkg-buildpackage uses to
# determine the package version.
deb-changelog:
	printf '%s\n\n  * Auto-release.\n\n %s\n' \
          "nvme-cli ($(NVME_VERSION)-$(NVME_DPKG_VERSION)) `lsb_release -sc`; urgency=low" \
          "-- $(AUTHOR)  `git log -1 --format=%cD`" \
	  > debian/changelog

deb: deb-changelog dist-orig
	dpkg-buildpackage -uc -us -sa

# After this target is build you need to do a debsign and dput on the
# ../<name>.changes file to upload onto the relevant PPA. For example:
#
#  > make AUTHOR='First Last <first.last@company.com>' \
#        NVME_DPKG_VERSION='0ubuntu1' deb-ppa
#  > debsign <name>.changes
#  > dput ppa:<lid>/ppa <name>.changes
#
# where lid is your launchpad.net ID.
deb-ppa: deb-changelog dist-orig
	debuild -uc -us -S

deb-light: $(NVME) pkg nvme.control.in
	dpkg-deb --build nvme-$(NVME_VERSION)

rpm: dist
	$(RPMBUILD) -ta nvme-$(NVME_VERSION).tar.gz

.PHONY: default doc all clean clobber install-man install-bin install
.PHONY: dist pkg dist-orig deb deb-light rpm FORCE test

