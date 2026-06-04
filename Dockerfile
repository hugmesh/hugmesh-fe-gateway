# Reuse the shared snapdragon-gateway code as a base image; this repo only
# layers the fe-gateway identity + route config on top.
ARG GATEWAY_IMAGE=snapdragon-systems/gateway:dev
FROM ${GATEWAY_IMAGE}
ENV SPRING_APPLICATION_NAME=snapdragon-fe-gateway
COPY application-fe.yml /app/config/application-fe.yml
COPY liquibase/changelog /app/liquibase/changelog
ENV SPRING_CONFIG_ADDITIONAL_LOCATION=file:/app/config/
EXPOSE 8080
