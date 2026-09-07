FROM golang:1.27.1-alpine3.24 AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
ARG APP_VERSION=dev
ARG GIT_COMMIT_HASH=unknown
ARG BUILD_TIME=unknown
RUN CGO_ENABLED=0 go build -trimpath -o /out/taskfiles-demo ./cmd/taskfiles-demo

FROM alpine:3.24
COPY --from=build /out/taskfiles-demo /usr/local/bin/taskfiles-demo
ARG APP_VERSION=dev
ARG GIT_COMMIT_HASH=unknown
ARG BUILD_TIME=unknown
ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT_HASH=${GIT_COMMIT_HASH} \
    BUILD_TIME=${BUILD_TIME}
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/taskfiles-demo"]
