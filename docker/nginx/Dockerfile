# =============================================================================
# TechFix — Nginx Dockerfile
# Build context: project root (TechFix-main/)
#
# Runs as non-root user nginx-app (UID/GID 1001) to satisfy Kubernetes
# SecurityContext requirements (runAsNonRoot: true, runAsUser: 1001).
# Port 8080 is used so NET_BIND_SERVICE capability is not needed.
#
# Usage:
#   docker build -f docker/nginx/Dockerfile -t techfix/nginx:1.0.0 .
# =============================================================================

FROM nginx:1.25-alpine

# Create a non-root group and user (GID/UID 1001).
# Alpine's addgroup/adduser syntax differs from Debian groupadd/useradd.
RUN addgroup -g 1001 -S nginx-app \
    && adduser -u 1001 -S -D -H \
               -h /var/cache/nginx \
               -s /sbin/nologin \
               -G nginx-app \
               nginx-app

# Copy the site-level Nginx config (reverse proxy + static file rules).
# This file is the one generated in task 8.1 and listens on port 8080.
COPY docker/nginx/nginx.conf /etc/nginx/conf.d/default.conf

# Copy the compiled static assets from the Laravel public directory.
# The Nginx container serves CSS, JS and images directly without hitting PHP-FPM.
COPY --chown=nginx-app:nginx-app laraProject/public /var/www/html/public

# Patch the global nginx.conf so the master process runs as nginx-app:
#   1. Replace the "user  nginx;" directive with "user  nginx-app;"
#   2. Move the PID file to /tmp/nginx.pid so the non-root user can write it.
# We use sed in-place; if the directive is already absent we leave it unchanged.
RUN sed -i 's|user  nginx;|user  nginx-app;|g' /etc/nginx/nginx.conf \
    && sed -i 's|pid        /var/run/nginx.pid;|pid        /tmp/nginx.pid;|g' /etc/nginx/nginx.conf

# Give the runtime user ownership of directories Nginx writes to at runtime.
# /var/log/nginx  — access and error logs
# /var/cache/nginx — proxy and fastcgi caches
RUN chown -R nginx-app:nginx-app /var/cache/nginx /var/log/nginx

# Switch to the non-root runtime user
USER 1001

# Nginx listens on 8080 — matches nginx-service ClusterIP in k8s/services.yaml
EXPOSE 8080
