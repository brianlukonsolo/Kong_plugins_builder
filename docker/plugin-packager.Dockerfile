FROM kong:3.4.2

USER root

ARG INSTALL_NATIVE_BUILD_DEPS=false

RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        zip; \
      if [ "$INSTALL_NATIVE_BUILD_DEPS" = "true" ]; then \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          build-essential \
          pkg-config; \
      fi; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache \
        ca-certificates \
        zip; \
      if [ "$INSTALL_NATIVE_BUILD_DEPS" = "true" ]; then \
        apk add --no-cache \
          build-base \
          linux-headers \
          pkgconf; \
      fi; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y \
        ca-certificates \
        zip; \
      if [ "$INSTALL_NATIVE_BUILD_DEPS" = "true" ]; then \
        microdnf install -y \
          gcc \
          gcc-c++ \
          make \
          pkgconf-pkg-config; \
      fi; \
      microdnf clean all; \
    else \
      echo "No supported package manager found" >&2; \
      exit 1; \
    fi

COPY docker/package-plugins.sh /usr/local/bin/package-plugins.sh
RUN chmod +x /usr/local/bin/package-plugins.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/package-plugins.sh"]
