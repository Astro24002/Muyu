# Build the static Flutter web release and use the same Caddy image for TLS,
# SPA fallback, API proxying, and static asset delivery.
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /src
COPY client/pubspec.yaml client/pubspec.lock ./
RUN flutter pub get
COPY client ./
RUN flutter build web --release --dart-define=API_BASE_URL=/api/v1

FROM caddy:2.10-alpine
COPY --from=build /src/build/web /srv
