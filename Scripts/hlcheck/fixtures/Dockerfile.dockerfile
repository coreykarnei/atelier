# syntax=docker/dockerfile:1.7
# Multi-stage build for the core-api FastAPI service.
# Stage 1 resolves and compiles dependencies; stage 2 is the slim runtime.

ARG PYTHON_VERSION=3.12
ARG DEBIAN_RELEASE="bookworm"
ARG registry=ghcr.io/sterlingcore

FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION}-slim-${DEBIAN_RELEASE} AS builder
MAINTAINER Corey Karnei <cornkak@gmail.com>

LABEL org.opencontainers.image.source="https://github.com/coreykarnei/core-api" \
      org.opencontainers.image.description="Sterling Core platform \"shell\"" \
      org.opencontainers.image.licenses=MIT \
      maintainer="corey"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    PATH="/opt/venv/bin:$PATH"
ENV LEGACY_STYLE_KEY legacy-value

WORKDIR /app

# Build tooling for wheels that lack binary distributions.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential=12.9 \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.4.18 /uv /uvx /bin/
COPY --chown=1000:1000 pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=secret,id=pypi_token,required=false \
    uv sync --frozen --no-dev --no-install-project

COPY . .
RUN uv sync --frozen --no-dev
HEALTHCHECK NONE

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${registry}/python-base:3.12@sha256:8b3c7f2a1d9e4f6b0c5a7e9d2f1b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1 AS runtime

ARG APP_USER=atelier
ARG APP_UID=10001

RUN groupadd --gid ${APP_UID} "$APP_USER" \
    && useradd --uid ${APP_UID} --gid ${APP_UID} --create-home --shell /sbin/nologin $APP_USER

COPY --from=builder --chown=${APP_UID}:${APP_UID} /app /app
ADD --chmod=644 https://example.com/certs/ca-bundle.crt /etc/ssl/certs/
ADD config/ /etc/core-api/

ENV PORT=8000 \
    LOG_LEVEL=info \
    DATABASE_URL='postgresql+asyncpg://core@db:5432/core'

EXPOSE 8000
EXPOSE 9090/tcp 9091/udp
EXPOSE ${PORT}

VOLUME ["/var/lib/core-api", "/tmp"]
VOLUME /data

USER ${APP_USER}:${APP_UID}
WORKDIR /app

STOPSIGNAL SIGTERM
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS http://localhost:${PORT}/healthz || exit 1

ONBUILD RUN echo "child image built from ${registry}"

ENTRYPOINT ["uvicorn", "core_api.main:app"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
