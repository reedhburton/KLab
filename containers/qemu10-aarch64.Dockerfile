FROM debian:trixie-slim
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-system-arm qemu-utils qemu-efi-aarch64 \
 && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["/bin/sh", "-c"]
