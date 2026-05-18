FROM kong:3.4.2

USER root

ARG INSTALL_NATIVE_BUILD_DEPS=false
ENV KONG_NATIVE_LIB_DIR=/usr/local/lib/kong-plugins

RUN set -eux; \
    mkdir -p "$KONG_NATIVE_LIB_DIR"; \
    chown -R kong:kong "$KONG_NATIVE_LIB_DIR"; \
    if [ "$INSTALL_NATIVE_BUILD_DEPS" = "true" ]; then \
      if command -v apt-get >/dev/null 2>&1; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          build-essential \
          ca-certificates \
          pkg-config; \
        rm -rf /var/lib/apt/lists/*; \
      elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
          build-base \
          ca-certificates \
          linux-headers \
          pkgconf; \
      elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y \
          ca-certificates \
          gcc \
          gcc-c++ \
          make \
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
