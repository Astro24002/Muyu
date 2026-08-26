# Build the independent TypeScript SPA and use the same Caddy image for TLS,
# SPA fallback, API proxying, and static asset delivery.
FROM node:22-alpine AS web-build
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web ./
ARG VITE_API_BASE_URL=/
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build

FROM caddy:2.10-alpine
COPY --from=web-build /src/web/dist /srv
