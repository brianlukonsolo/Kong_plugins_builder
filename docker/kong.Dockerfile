FROM kong:3.4.2

USER root

COPY docker/kong-install-rocks.sh /usr/local/bin/kong-install-rocks.sh
RUN chmod +x /usr/local/bin/kong-install-rocks.sh

ENTRYPOINT ["/usr/local/bin/kong-install-rocks.sh"]
CMD ["kong", "docker-start"]
