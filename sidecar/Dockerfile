# QuizForum sidecar: Laya moderation (/v1/judge) + OpenJev jury (/v1/grade).
# CPU-only torch keeps the image small. Weights live in the `weights`
# volume (HF_HOME); first boot downloads ~4GB and can take 15 minutes.
# /up answers only when both models are loaded.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/weights

WORKDIR /sidecar

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY grade.py server.py ./

EXPOSE 8000

CMD ["python", "server.py", "8000"]
