# ---------- Stage 1: Build the Angular app ----------
FROM node:22.14.0-slim AS builder
WORKDIR /usr/src/app

ARG NPM_BUILD_CONFIG=docker

# Copy package.json and package-lock.json first for better caching
COPY client/web/package*.json ./

# Use npm ci for consistent installs
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Copy application code
COPY client/web/ ./

# Build the application
RUN npm run build -- --configuration=$NPM_BUILD_CONFIG

# ---------- Stage 2: SSR Server ----------
FROM node:22.14.0-alpine AS ssr
WORKDIR /usr/src/app

# Install only necessary packages
RUN apk add --no-cache wget=1.25.0-r0

# Copy built artifacts & package files
COPY --from=builder /usr/src/app/dist /usr/src/app/dist
COPY --from=builder /usr/src/app/package*.json ./

# Install only prod deps and clean up unnecessary files
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev && \
    rm -rf /tmp/* /usr/src/app/node_modules/.cache && \
    (find node_modules -type f \( \
      -name "*.md" -o -name "*.map" -o -name "*.ts" -o \
      -name "LICENSE*" -o -name "CHANGELOG*" -o -name "README*" -o \
      -name ".editorconfig" -o -name ".eslintrc*" -o -name ".npmignore" -o \
      -name "tsconfig*.json" -o -name ".package-lock.json" \
    \) -delete 2>/dev/null || true)

# Create a non-root user
USER node

# Expose SSR server port
EXPOSE 4000

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --spider -q http://localhost:4000/ || exit 1

# Launch SSR server
CMD ["node", "dist/web/server/server.mjs"]

# ---------- Stage 3: NGINX to reverse proxy SSR ----------
FROM nginx:1.31-alpine-slim AS nginx

# Install only necessary packages
RUN apk add --no-cache gettext=0.24.1-r1

# Copy only the specific static files needed
COPY --from=builder /usr/src/app/dist/web/browser/robots.txt /usr/share/nginx/html/browser/robots.txt
COPY --from=builder /usr/src/app/dist/web/browser/sitemap.xml /usr/share/nginx/html/browser/sitemap.xml

# Copy nginx config files
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf.template
COPY nginx/locations.conf /etc/nginx/locations.conf
COPY nginx/security/ /etc/nginx/security/
COPY nginx/includes/ /etc/nginx/includes/

# Copy the entrypoint script and make it executable
COPY docker-entrypoint.sh /

# Set permissions and create directories
RUN chmod +x /docker-entrypoint.sh && \
    chown nginx:nginx /docker-entrypoint.sh && \
    chown nginx:nginx /etc/nginx/conf.d/default.conf.template && \
    mkdir -p /var/cache/nginx/web_temp /var/run/nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/cache/nginx /var/log/nginx /var/run/nginx \
      /usr/share/nginx/html /etc/nginx/conf.d && \
    chown nginx:nginx /var/run/nginx.pid && \
    chmod 644 /var/run/nginx.pid

# Expose HTTPS port
EXPOSE 443

# Switch to nginx user
USER nginx

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --spider -q http://localhost || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
