CC      ?= cc
AR      ?= ar
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -O2 -g
CPPFLAGS?= -Iinclude -Isrc
LDFLAGS ?=
LDLIBS  ?=

BUILD   := build
LIBNAME := prairie

SRC     := $(wildcard src/*.c)
OBJ     := $(patsubst src/%.c,$(BUILD)/%.o,$(SRC))

PUBLIC_HEADERS := $(wildcard include/prairie/*.h)

.PHONY: all clean test install uninstall

all: $(BUILD)/lib$(LIBNAME).a

# Build directory
$(BUILD):
	@mkdir -p $(BUILD)

# Object files
$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

# Static library
$(BUILD)/lib$(LIBNAME).a: $(OBJ)
	$(AR) rcs $@ $^

clean:
	rm -rf $(BUILD)

PREFIX ?= /usr/local
install: all
	install -d $(DESTDIR)$(PREFIX)/include/prairie
	install -m 0644 $(PUBLIC_HEADERS) $(DESTDIR)$(PREFIX)/include/prairie/
	install -d $(DESTDIR)$(PREFIX)/lib
	install -m 0644 $(BUILD)/lib$(LIBNAME).a $(DESTDIR)$(PREFIX)/lib/

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/lib$(LIBNAME).a
	rm -rf $(DESTDIR)$(PREFIX)/include/prairie