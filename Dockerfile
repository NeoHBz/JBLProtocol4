FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk-headless apktool tshark python3 python3-pip python3-venv \
    binutils file xxd git curl ca-certificates unzip ripgrep jq \
 && rm -rf /var/lib/apt/lists/*
ARG JADX_VERSION=1.5.1
RUN curl -fsSL -o /tmp/jadx.zip https://github.com/skylot/jadx/releases/download/v${JADX_VERSION}/jadx-${JADX_VERSION}.zip \
 && unzip -q /tmp/jadx.zip -d /opt/jadx && rm /tmp/jadx.zip \
 && ln -s /opt/jadx/bin/jadx /usr/local/bin/jadx
ENV BUN_INSTALL=/opt/bun
RUN curl -fsSL https://bun.sh/install | bash && ln -s /opt/bun/bin/bun /usr/local/bin/bun && ln -s /opt/bun/bin/bunx /usr/local/bin/bunx
RUN pip3 install --break-system-packages pytest
WORKDIR /work
CMD ["sleep","infinity"]
