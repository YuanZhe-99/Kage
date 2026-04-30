package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"

	"github.com/quic-go/quic-go"
	log "github.com/sirupsen/logrus"
)

type QUICServer struct {
	cfg     *Config
	handler *Handler
	server  *quic.Listener
}

func NewQUICServer(cfg *Config, handler *Handler) *QUICServer {
	return &QUICServer{
		cfg:     cfg,
		handler: handler,
	}
}

func (s *QUICServer) Start(ctx context.Context) error {
	tlsCert, err := tls.LoadX509KeyPair(s.cfg.TLSCertFile, s.cfg.TLSKeyFile)
	if err != nil {
		return fmt.Errorf("failed to load TLS certificate: %v", err)
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{tlsCert},
		NextProtos:   []string{"h3", "hq-29"},
	}

	addr := fmt.Sprintf(":%d", s.cfg.QUICPort)
	listener, err := quic.ListenAddr(addr, tlsConfig, &quic.Config{
		MaxIdleTimeout:  30 * 1000 * 1000 * 1000,
		KeepAlivePeriod: 10 * 1000 * 1000 * 1000,
	})
	if err != nil {
		return fmt.Errorf("failed to start QUIC listener: %v", err)
	}

	s.server = listener

	for {
		conn, err := listener.Accept(ctx)
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				log.Errorf("Failed to accept QUIC connection: %v", err)
				continue
			}
		}

		go s.handleConnection(ctx, conn)
	}
}

func (s *QUICServer) handleConnection(ctx context.Context, conn quic.Connection) {
	log.Infof("New QUIC connection from %s", conn.RemoteAddr())

	for {
		stream, err := conn.AcceptStream(ctx)
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				log.Errorf("Failed to accept stream: %v", err)
				return
			}
		}

		go s.handleStream(stream)
	}
}

func (s *QUICServer) handleStream(stream quic.Stream) {
	defer stream.Close()

	req, err := http.ReadRequest(io.Reader(stream))
	if err != nil {
		log.Errorf("Failed to read HTTP request: %v", err)
		return
	}

	log.Infof("QUIC request: %s %s", req.Method, req.URL.Path)

	rw := newQUICResponseWriter(stream)
	s.handler.HandleChatCompletions(rw, req)
}

type quicResponseWriter struct {
	stream   quic.Stream
	header   http.Header
	written  bool
}

func newQUICResponseWriter(stream quic.Stream) *quicResponseWriter {
	return &quicResponseWriter{
		stream: stream,
		header: make(http.Header),
	}
}

func (w *quicResponseWriter) Header() http.Header {
	return w.header
}

func (w *quicResponseWriter) Write(data []byte) (int, error) {
	if !w.written {
		w.WriteHeader(http.StatusOK)
	}
	return w.stream.Write(data)
}

func (w *quicResponseWriter) WriteHeader(statusCode int) {
	if w.written {
		return
	}
	w.written = true

	resp := &http.Response{
		StatusCode: statusCode,
		Status:     fmt.Sprintf("%d %s", statusCode, http.StatusText(statusCode)),
		Header:     w.header,
		Proto:      "HTTP/3",
		ProtoMajor: 3,
	}

	resp.Write(w.stream)
}

func (w *quicResponseWriter) Flush() {
	if flusher, ok := w.stream.(http.Flusher); ok {
		flusher.Flush()
	}
}
