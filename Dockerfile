# Reuse the shared hugmesh-gateway code as a base image; this repo only
# layers the fe-gateway identity + route config on top.
ARG GATEWAY_IMAGE=hugmesh-systems/hugmesh-gateway:dev
FROM ${GATEWAY_IMAGE}
ENV SPRING_APPLICATION_NAME=hugmesh-fe-gateway
COPY application-fe.yml /app/config/application-fe.yml
COPY liquibase/changelog /app/liquibase/changelog
ENV SPRING_CONFIG_ADDITIONAL_LOCATION=file:/app/config/
# application-fe.yml is a profile-specific document (application-{profile}.yml).
# SPRING_CONFIG_ADDITIONAL_LOCATION above only adds a SEARCH DIRECTORY — it does
# NOT activate a profile — so Boot reads that file only when profile "fe" is
# active, and the shared hugmesh-gateway base image activates no profile at
# all (verified on its origin/main: no SPRING_PROFILES_ACTIVE / spring.profiles /
# setAdditionalProfiles reference anywhere in that repo). Without the line below
# the overlay is silently never read and the image falls back to the base
# application.yml's api-default route (/api/** -> api:8080) — i.e. the WRONG
# route table rather than an obvious failure. Mirrors the canonical fix in
# hugmesh-generator's hugmesh-gateway chart (SPRING_PROFILES_ACTIVE=routes).
#
# This ENV is a DEFAULT only: `docker run -e SPRING_PROFILES_ACTIVE=…` or a k8s
# env entry REPLACES it (replaces, not appends — pass "fe,other" to keep this
# file loading alongside another profile).
ENV SPRING_PROFILES_ACTIVE=fe
EXPOSE 8080
