# Replication environment (Doc 16.15). The Flutter version is pinned so results
# are comparable; change the tag together with the benchmark's pinned SDK.
FROM ghcr.io/cirruslabs/flutter:3.35.5

WORKDIR /flutterastest
COPY pubspec.yaml pubspec.lock ./
COPY bin ./bin
COPY lib ./lib
RUN dart pub get

# Usage:
#   docker build -t flutterastest .
#   docker run --rm -e GEMINI_API_KEY -v /path/to/app:/app -v "$PWD/out":/out \
#     flutterastest analyse /app --output /out
ENTRYPOINT ["dart", "run", "bin/flutterastest.dart"]
