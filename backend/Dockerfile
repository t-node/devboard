# syntax=docker/dockerfile:1

########################
# Build stage
########################
FROM dhi.io/golang:1-alpine-dev AS builder

WORKDIR /app

# Cache dependency downloads separately from source changes
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Static, stripped binary: no CGO, no debug symbols, reproducible paths
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o devboard-backend .

########################
# Runtime stage (minimal, non-dev DHI image)
########################
FROM dhi.io/golang:1-alpine

WORKDIR /app

# Copy binary with correct ownership so nonroot can execute it (no separate chmod layer needed)
COPY --from=builder --chown=nonroot:nonroot /app/devboard-backend ./devboard-backend

# DHI image runs as nonroot by default; explicit for clarity and defense-in-depth
USER nonroot

EXPOSE 8080

# Use exec form for proper signal handling (SIGTERM propagation, no shell wrapping)
ENTRYPOINT ["./devboard-backend"]
