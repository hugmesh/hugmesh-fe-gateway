# Reuse the shared snapdragon-gateway code as a base image; this repo only
# layers the fe-gateway identity + route config on top.
ARG GATEWAY_IMAGE=snapdragon-systems/gateway:dev
FROM ${GATEWAY_IMAGE}
ENV SPRING_APPLICATION_NAME=snapdragon-fe-gateway
COPY application-fe.yml /app/config/application-fe.yml
COPY liquibase/changelog /app/liquibase/changelog
ENV SPRING_CONFIG_ADDITIONAL_LOCATION=file:/app/config/
# TODO: application-fe.yml is a profile-specific file (application-{profile}.yml)
# and Spring Boot only loads it from an additional-location dir when profile "fe"
# is active — SPRING_PROFILES_ACTIVE is not set anywhere in this file. Confirmed
# against the current snapdragon-gateway base image (origin/main) that nothing
# there activates a profile from SPRING_APPLICATION_NAME either, so this file is
# likely never loaded by a standalone `docker run` of this image. See README
# "Known gaps" for the full evidence trail and fix options.
EXPOSE 8080
