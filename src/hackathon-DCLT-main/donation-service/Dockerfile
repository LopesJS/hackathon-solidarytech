FROM golang:1.21-alpine AS builder

RUN apk add --no-cache ca-certificates git tzdata

WORKDIR /build

COPY go.mod ./

RUN go mod download && go mod verify

COPY *.go ./

RUN CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    go build \
      -ldflags="-s -w" \
      -trimpath \
      -o /bin/donation-service \
      .

FROM gcr.io/distroless/static-debian12:nonroot AS runtime

LABEL org.opencontainers.image.title="donation-service" \
      org.opencontainers.image.description="SolidaryTech — Processamento de doações" \
      org.opencontainers.image.version="1.0.0"

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /bin/donation-service /bin/donation-service

USER nonroot:nonroot

EXPOSE 8082

ENTRYPOINT ["/bin/donation-service"]
