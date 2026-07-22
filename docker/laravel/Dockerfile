# =============================================================================
# TechFix — Laravel multi-stage Dockerfile
# Build context: project root (TechFix-main/)
#
# SECURITY NOTE: include/connect.php (hardcoded credentials tweb/tweb) lives
# at <project-root>/include/ and is NEVER referenced in any COPY instruction
# below. Only laraProject/ content reaches the image. Verified by design.
#
# Usage:
#   docker build -f docker/laravel/Dockerfile -t techfix/laravel-app:1.0.0 .
# =============================================================================


# -----------------------------------------------------------------------------
# Stage 1 — builder
# Installs system libraries, PHP extensions, Composer dependencies, and
# generates the optimised autoloader. No runtime-only base needed here; we
# use php:8.2-cli to keep the toolchain consistent with the local dev PHP.
# -----------------------------------------------------------------------------
FROM php:8.2-cli AS builder

# Install build-time system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        unzip \
        zip \
        libzip-dev \
        libpng-dev \
        libonig-dev \
        libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required PHP extensions
RUN docker-php-ext-install \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip

# Copy Composer 2.6 binary from the official image — avoids a curl/verify loop
COPY --from=composer:2.6 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copy only the dependency manifests first to exploit Docker layer caching:
# this layer is rebuilt only when composer.json or composer.lock changes.
COPY laraProject/composer.json laraProject/composer.lock ./

# Install PHP dependencies without running Composer scripts or building the
# autoloader yet — scripts may call `php artisan` which requires the full
# application code to be present.
RUN composer install \
        --no-interaction \
        --no-scripts \
        --no-autoloader

# Copy the full Laravel application.
# NOTE: include/connect.php lives at <project-root>/include/ and is NOT inside
# laraProject/, so this COPY instruction cannot reach it by construction.
COPY laraProject/ ./

# Allow Composer to run as root inside the build container
ENV COMPOSER_ALLOW_SUPERUSER=1

# Re-install without dev dependencies and generate the optimised autoloader.
# --no-scripts prevents artisan package:discover from running during build
# (it requires DB/env vars). Package discovery runs at container startup instead.
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts


# -----------------------------------------------------------------------------
# Stage 2 — production
# Minimal PHP-FPM runtime image. Only the compiled application from the builder
# stage is copied — no Composer binary, no PHP-CLI, no build tools.
# Runs as non-root UID 1001 to satisfy Kubernetes SecurityContext requirements.
# -----------------------------------------------------------------------------
FROM php:8.2-fpm AS production

# Install only the runtime shared libraries needed by the PHP extensions
# (same packages as builder, minus git which is a build-time-only tool).
RUN apt-get update && apt-get install -y --no-install-recommends \
        unzip \
        zip \
        libzip-dev \
        libpng-dev \
        libonig-dev \
        libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Install the same PHP extensions in the FPM image
RUN docker-php-ext-install \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip

# Create a dedicated non-root group and user (GID/UID 1001) that matches the
# Kubernetes Pod securityContext (runAsUser: 1001, fsGroup: 1001).
RUN groupadd --gid 1001 www \
    && useradd --uid 1001 --gid www --no-create-home --shell /sbin/nologin www

# Copy the fully-built application from the builder stage.
# --chown ensures every file is owned by the runtime user from the start,
# avoiding a separate RUN chown layer that would double the layer size.
COPY --from=builder --chown=www:www /app /var/www/html

# Create the writable directories Laravel needs at runtime. These are the only
# paths that must be writable; everything else stays read-only (readOnlyRootFilesystem: true).
# In Kubernetes, emptyDir volumes are mounted over these paths, so the mkdir
# here ensures the directories exist when the image runs standalone (e.g. docker run).
RUN mkdir -p \
        /var/www/html/storage/logs \
        /var/www/html/storage/framework/cache \
        /var/www/html/storage/framework/sessions \
        /var/www/html/storage/framework/views \
        /var/www/html/bootstrap/cache \
    && chown -R www:www \
        /var/www/html/storage \
        /var/www/html/bootstrap/cache

# Switch to the non-root runtime user
USER 1001

# PHP-FPM listens on port 9000 — matches laravel-service ClusterIP in k8s/services.yaml
EXPOSE 9000

CMD ["php-fpm"]
