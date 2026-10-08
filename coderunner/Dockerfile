# Coderunner: diff-fuzz execution service (python/js/ts/ruby + phase-2
# toolchains below: Go, JDK, g++ + nlohmann/json.hpp vendor, .NET SDK).
# Pinned: python:3.12-slim + nodejs 24.x (nodesource). Ruby comes from
# Debian (bookworm ships 3.x, not 4.x): phase-1 tasks must stay within
# safe-range ints / plain JSON values, which behave identically on ruby 3
# and 4; the phase-2 toolchain stage pins exact versions per spec section 2.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] \
        https://deb.nodesource.com/node_24.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs ruby-full g++ \
    && node --version && ruby --version \
    && apt-get purge -y curl gnupg && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Phase 2 slice 2: Go toolchain (pinned + checksummed). curl is reinstalled
# here because the node stage purges it, and purged again below.
ARG GO_VERSION=1.27.2
RUN apt-get update && apt-get install -y --no-install-recommends curl && arch=$(dpkg --print-architecture) && case "$arch" in amd64) sha256=ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5;; arm64) sha256=94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8;; *) echo "unsupported arch $arch" >&2; exit 1;; esac && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o /tmp/go.tgz && echo "${sha256}  /tmp/go.tgz" | sha256sum -c - && tar -xzf /tmp/go.tgz -C /usr/local && rm /tmp/go.tgz && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && /usr/local/go/bin/go version
ENV PATH=/usr/local/go/bin:${PATH} GOTOOLCHAIN=local

# Phase 2 slice 3: JDK 25 Temurin (pinned + checksummed, hotspot).
# dpkg arch -> Temurin arch: amd64->x64, arm64->aarch64.
ARG JDK_TAG=25.0.4.1_1
RUN apt-get update && apt-get install -y --no-install-recommends curl && arch=$(dpkg --print-architecture) && case "$arch" in amd64) tarch=x64; sha256=dbb698396d478e7fa2b1e50f4103324b2a99b90569ee27c33f2261f9215cf41e;; arm64) tarch=aarch64; sha256=69df11a02cfa3ef7d7ca645e03edce6778ec090e100f6ae2b42097865730ac52;; *) echo "unsupported arch $arch" >&2; exit 1;; esac && curl -fsSL "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_${tarch}_linux_hotspot_${JDK_TAG}.tar.gz" -o /tmp/jdk.tgz && echo "${sha256}  /tmp/jdk.tgz" | sha256sum -c - && mkdir -p /usr/local/lib/jvm && tar -xzf /tmp/jdk.tgz -C /usr/local/lib/jvm --strip-components=1 && rm /tmp/jdk.tgz && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && /usr/local/lib/jvm/bin/java -version
ENV PATH=/usr/local/lib/jvm/bin:${PATH}

# Phase 2 slice 5: .NET SDK (pinned + checksummed, Microsoft release metadata).
# libicu stays: the runtime needs it. DOTNET_ROOT guides SDK discovery.
ARG DOTNET_VERSION=10.0.401
ENV DOTNET_ROOT=/usr/share/dotnet DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
RUN apt-get update && apt-get install -y --no-install-recommends curl libicu72 && arch=$(dpkg --print-architecture) && case "$arch" in amd64) rid=linux-x64; sha512=51c8b999af9e8dd9998c9edc5944e19a90788862068acd38694e098889054ce8c23d4f0c5cccfa16bf187d044562359e5ee69a9f8ad0bbe913ba90311fbce25b;; arm64) rid=linux-arm64; sha512=58ace73ced6b4360754689a686bdfb8a317f4da6cb8bb416dbc7d0ba9f47e43e3c09f5eb1f1a1cfaacbd10df9558da4882bf2a5e195d6ab56a02c1f9f76102ed;; *) echo "unsupported arch $arch" >&2; exit 1;; esac && curl -fsSL "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_VERSION}/dotnet-sdk-${DOTNET_VERSION}-${rid}.tar.gz" -o /tmp/dotnet.tgz && echo "${sha512}  /tmp/dotnet.tgz" | sha512sum -c - && mkdir -p /usr/share/dotnet && tar -xzf /tmp/dotnet.tgz -C /usr/share/dotnet && rm /tmp/dotnet.tgz && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet && dotnet --version && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
ENV PATH=/usr/share/dotnet:${PATH}

RUN useradd -m runner
WORKDIR /app
# Vendored third-party headers (nlohmann/json.hpp, MIT) for the C++ harness.
COPY server.py runners.py vendor/ ./
USER runner
ENV CODERUNNER_HOST=0.0.0.0 CODERUNNER_PORT=8001
EXPOSE 8001
HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=1m \
    CMD python3 -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8001/up')))"
CMD ["python3", "server.py"]
