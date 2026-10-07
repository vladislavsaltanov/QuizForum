# Coderunner: diff-fuzz execution service (phase 1: python/js/ruby).
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

RUN useradd -m runner
WORKDIR /app
COPY server.py runners.py ./
USER runner
ENV CODERUNNER_HOST=0.0.0.0 CODERUNNER_PORT=8001
EXPOSE 8001
HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=1m \
    CMD python3 -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:8001/up')))"
CMD ["python3", "server.py"]
