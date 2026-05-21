CC ?= gcc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2 -fPIC -Wall -Wextra
LDFLAGS ?= -shared

XMLSEC_CFLAGS := $(shell $(PKG_CONFIG) --cflags libxml-2.0 xmlsec1-openssl)
XMLSEC_LIBS := $(shell $(PKG_CONFIG) --libs libxml-2.0 xmlsec1-openssl openssl) -lz

TARGET = libkong_saml_jwe_auth.so
SRC = kong_saml_jwe_auth.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(XMLSEC_CFLAGS) -o $@ $(SRC) $(LDFLAGS) $(XMLSEC_LIBS)

clean:
	rm -f $(TARGET)
