package main

import (
	"os"
	"strconv"
)

type Config struct {
	HTTPSPort  int
	QUICPort   int
	TLSCertFile string
	TLSKeyFile  string
	LogLevel   string
}

func LoadConfig() *Config {
	cfg := &Config{
		HTTPSPort:  443,
		QUICPort:   443,
		TLSCertFile: "cert.pem",
		TLSKeyFile:  "key.pem",
		LogLevel:   "info",
	}

	if port := os.Getenv("HTTPS_PORT"); port != "" {
		if p, err := strconv.Atoi(port); err == nil {
			cfg.HTTPSPort = p
		}
	}

	if port := os.Getenv("QUIC_PORT"); port != "" {
		if p, err := strconv.Atoi(port); err == nil {
			cfg.QUICPort = p
		}
	}

	if cert := os.Getenv("TLS_CERT_FILE"); cert != "" {
		cfg.TLSCertFile = cert
	}

	if key := os.Getenv("TLS_KEY_FILE"); key != "" {
		cfg.TLSKeyFile = key
	}

	if level := os.Getenv("LOG_LEVEL"); level != "" {
		cfg.LogLevel = level
	}

	return cfg
}
