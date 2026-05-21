FROM kong:3.4.2

USER root

ARG INSTALL_NATIVE_BUILD_DEPS=false
ENV KONG_NATIVE_LIB_DIR=/usr/local/lib/kong-plugins

RUN set -eux; \
    mkdir -p "$KONG_NATIVE_LIB_DIR"; \
    chown -R kong:kong "$KONG_NATIVE_LIB_DIR"; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        libxml2 \
        libxmlsec1 \
        libxmlsec1-openssl \
        zlib1g; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache \
        ca-certificates \
        libxml2 \
        openssl \
        xmlsec \
        zlib; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y \
        ca-certificates \
        libxml2 \
        openssl \
        xmlsec1 \
        xmlsec1-openssl \
        zlib; \
      microdnf clean all; \
    else \
      echo "No supported package manager found" >&2; \
      exit 1; \
    fi; \
    if [ "$INSTALL_NATIVE_BUILD_DEPS" = "true" ]; then \
      if command -v apt-get >/dev/null 2>&1; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          build-essential \
          ca-certificates \
          libssl-dev \
          libxml2-dev \
          libxmlsec1-dev \
          libxmlsec1-openssl \
          pkg-config \
          zlib1g-dev; \
        rm -rf /var/lib/apt/lists/*; \
      elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
          build-base \
          ca-certificates \
          libxml2-dev \
          openssl-dev \
          linux-headers \
          pkgconf \
          xmlsec-dev \
          zlib-dev; \
      elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y \
          ca-certificates \
          gcc \
          gcc-c++ \
          libxml2-devel \
          make \
          openssl-devel \
          xmlsec1-devel \
          xmlsec1-openssl-devel \
          zlib-devel \
          pkgconf-pkg-config; \
        microdnf clean all; \
      else \
        echo "No supported package manager found for INSTALL_NATIVE_BUILD_DEPS=true" >&2; \
        exit 1; \
      fi; \
    fi

COPY docker/kong-install-rocks.sh /usr/local/bin/kong-install-rocks.sh
RUN chmod +x /usr/local/bin/kong-install-rocks.sh

ENTRYPOINT ["/usr/local/bin/kong-install-rocks.sh"]
CMD ["kong", "docker-start"]
