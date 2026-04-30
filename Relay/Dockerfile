FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o turn-server .

FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /app/turn-server .

EXPOSE 3478/udp
EXPOSE 3478/tcp
EXPOSE 49152-65535/udp

CMD ["./turn-server"]
