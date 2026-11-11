FROM debian:trixie-slim
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-system-misc qemu-utils opensbi u-boot-qemu \
 && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["/bin/sh", "-c"]
