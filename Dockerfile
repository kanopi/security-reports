FROM php:8.3-cli-alpine

RUN set -xe; \
      apk add --update --no-cache \
        libgcc \
        libstdc++ \
        libx11 \
        git \
        glib \
        libxrender \
        libxext \
        libintl \
        ttf-dejavu \
        ttf-droid \
        ttf-freefont \
        ttf-liberation \
        unzip \
        zip

ENV SONARQUBE_HOST=""
ENV SONARQUBE_USER=""
ENV SONARQUBE_PASS=""
ENV SONARQUBE_PROJECTS=""
ENV SONARQUBE_EXTRA_PARAMS=""
ENV DEBUG_REPORT=""

COPY --from=surnet/alpine-wkhtmltopdf:3.17.0-0.12.6-small \
    /bin/wkhtmltopdf /bin/wkhtmltopdf

ENV SONARQUBE_REPORT_DIR=/mnt/reports/ \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_VERSION=2.4.3

WORKDIR /root

COPY . .

RUN set -xe; \
        curl -fsSL -o /usr/local/bin/composer https://github.com/composer/composer/releases/download/${COMPOSER_VERSION}/composer.phar; \
        chmod +x /usr/local/bin/composer; \
        composer install --no-dev;

VOLUME /mnt/reports

CMD ["php", "-d", "memory_limit=-1", "/root/run.php"]