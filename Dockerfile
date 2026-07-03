# Reuse the shared snapdragon-gateway code as a base image; this repo only
# layers the fe-gateway identity + route config on top.
ARG GATEWAY_IMAGE=snapdragon-systems/gateway:dev
FROM ${GATEWAY_IMAGE}
ENV SPRING_APPLICATION_NAME=snapdragon-fe-gateway
COPY application-fe.yml /app/config/application-fe.yml
COPY liquibase/changelog /app/liquibase/changelog
ENV SPRING_CONFIG_ADDITIONAL_LOCATION=file:/app/config/
# NOTE: application-fe.yml is a profile-specific file (application-{profile}.yml).
# Spring Boot only scans an additional-location directory for application-fe.yml
# when profile "fe" is active. This overlay does not set SPRING_PROFILES_ACTIVE
# here, so the base snapdragon-gateway image is expected to activate the "fe"
# profile itself (e.g. from SPRING_APPLICATION_NAME or another convention).
# Verify this against snapdragon-gateway before relying on the Casdoor
# issuer-uri override or the fe-default route actually loading.
EXPOSE 8080
