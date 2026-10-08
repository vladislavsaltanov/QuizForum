# Coderunner: diff-fuzz execution service (phase 1: python/js/ruby + TS;
# phase 2 slice 2 adds the Go toolchain below).
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
    && apt-get install -y --no-install-recommends nodejs ruby-full \
    && node --version && ruby --version \
    && apt-get purge -y curl gnupg && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Phase 2 slice 2: Go toolchain (pinned + checksummed). curl is reinstalled
# here because the node stage purges it, and purged again below.
ARG GO_VERSION=1.27.2
RUN apt-get update && apt-get install -y --no-install-recommends curl && arch=$(dpkg --print-architecture) && case "$arch" in amd64) sha256=ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5;; arm64) sha256=94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8;; *) echo "unsupported arch $arch" >&2; exit 1;; esac && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o /tmp/go.tgz && echo "${sha256}  /tmp/go.tgz" | sha256sum -c - && tar -xzf /tmp/go.tgz -C /usr/local && rm /tmp/go.tgz && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && /usr/local/go/bin/go version
ENV PATH=/usr/local/go/bin:${PATH} GOTOOLCHAIN=local

RUN useradd -m runner
WORKDIR /app
COPY server.py runners.py ./
USER runner
ENV CODERUNNER_HOST=0.0.0.0 CODERUNNER_PORT=8001
EXPOSE 8001
HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=1m \
    CMD python3 -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8001/up')))"
CMD ["python3", "server.py"]
