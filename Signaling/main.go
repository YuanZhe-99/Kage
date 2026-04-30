package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	log "github.com/sirupsen/logrus"
)

func main() {
	log.SetFormatter(&log.JSONFormatter{})
	log.SetOutput(os.Stdout)
	log.SetLevel(log.InfoLevel)

	cfg := LoadConfig()

	registry := NewRegistry()

	router := mux.NewRouter()
	handler := NewHandler(registry)

	router.HandleFunc("/v1/chat/completions", handler.HandleChatCompletions).Methods("POST")
	router.HandleFunc("/v1/models", handler.HandleListModels).Methods("GET")
	router.HandleFunc("/health", handler.HandleHealth).Methods("GET")

	router.Use(loggingMiddleware)
	router.Use(corsMiddleware)

	httpServer := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.HTTPSPort),
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
		TLSConfig: &tls.Config{
			MinVersion: tls.VersionTLS13,
		},
	}

	quicServer := NewQUICServer(cfg, handler)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		log.Infof("Starting HTTPS signaling server on port %d", cfg.HTTPSPort)
		if err := httpServer.ListenAndServeTLS(cfg.TLSCertFile, cfg.TLSKeyFile); err != http.ErrServerClosed {
			log.Fatalf("HTTPS server error: %v", err)
		}
	}()

	go func() {
		log.Infof("Starting QUIC signaling server on port %d", cfg.QUICPort)
		if err := quicServer.Start(ctx); err != nil {
			log.Fatalf("QUIC server error: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Info("Shutting down servers...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Errorf("HTTPS server shutdown error: %v", err)
	}

	cancel()

	log.Info("Servers stopped")
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.WithFields(log.Fields{
			"method":     r.Method,
			"path":       r.URL.Path,
			"duration":   time.Since(start),
			"remote":     r.RemoteAddr,
			"user_agent": r.UserAgent(),
		}).Info("Request processed")
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}
