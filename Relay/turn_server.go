package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	log "github.com/sirupsen/logrus"
)

func main() {
	log.SetFormatter(&log.JSONFormatter{})
	log.SetOutput(os.Stdout)
	log.SetLevel(log.InfoLevel)

	cfg := LoadConfig()

	server := NewTURNServer(cfg)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		log.Infof("Starting TURN server on %s:%d", cfg.ListenAddr, cfg.Port)
		if err := server.Start(ctx); err != nil {
			log.Fatalf("TURN server error: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Info("Shutting down TURN server...")
	cancel()
	time.Sleep(1 * time.Second)
	log.Info("TURN server stopped")
}

type Config struct {
	ListenAddr string
	Port       int
	Realm      string
	AuthSecret string
}

func LoadConfig() *Config {
	cfg := &Config{
		ListenAddr: "0.0.0.0",
		Port:       3478,
		Realm:      "kage",
		AuthSecret: "default-secret-change-me",
	}

	if addr := os.Getenv("LISTEN_ADDR"); addr != "" {
		cfg.ListenAddr = addr
	}

	if port := os.Getenv("PORT"); port != "" {
		fmt.Sscanf(port, "%d", &cfg.Port)
	}

	if realm := os.Getenv("REALM"); realm != "" {
		cfg.Realm = realm
	}

	if secret := os.Getenv("AUTH_SECRET"); secret != "" {
		cfg.AuthSecret = secret
	}

	return cfg
}

type TURNServer struct {
	cfg      *Config
	listener *net.UDPConn
	sessions map[string]*Session
}

type Session struct {
	ID        string
	Client    *net.UDPAddr
	Relay     *net.UDPAddr
	RelayConn *net.UDPConn
	Created   time.Time
	Expires   time.Time
}

func NewTURNServer(cfg *Config) *TURNServer {
	return &TURNServer{
		cfg:      cfg,
		sessions: make(map[string]*Session),
	}
}

func (s *TURNServer) Start(ctx context.Context) error {
	addr := &net.UDPAddr{
		IP:   net.ParseIP(s.cfg.ListenAddr),
		Port: s.cfg.Port,
	}

	conn, err := net.ListenUDP("udp4", addr)
	if err != nil {
		return fmt.Errorf("failed to listen: %v", err)
	}

	s.listener = conn

	go s.cleanupSessions(ctx)

	for {
		select {
		case <-ctx.Done():
			return nil
		default:
			buffer := make([]byte, 1500)
			n, clientAddr, err := conn.ReadFromUDP(buffer)
			if err != nil {
				continue
			}

			go s.handlePacket(buffer[:n], clientAddr)
		}
	}
}

func (s *TURNServer) handlePacket(data []byte, clientAddr *net.UDPAddr) {
	if len(data) < 20 {
		return
	}

	messageType := (uint16(data[0]) << 8) | uint16(data[1])

	switch messageType {
	case 0x0001:
		s.handleBindingRequest(data, clientAddr)
	case 0x0003:
		s.handleAllocateRequest(data, clientAddr)
	case 0x0004:
		s.handleRefreshRequest(data, clientAddr)
	case 0x0006:
		s.handleSendIndication(data, clientAddr)
	default:
		log.Debugf("Unknown message type: 0x%04x from %s", messageType, clientAddr)
	}
}

func (s *TURNServer) handleBindingRequest(data []byte, clientAddr *net.UDPAddr) {
	response := make([]byte, 20)
	response[0] = 0x01
	response[1] = 0x01
	response[2] = 0x00
	response[3] = 0x00

	copy(response[4:8], data[4:8])

	response[8] = 0x00
	response[9] = 0x20

	ip := clientAddr.IP.To4()
	response[10] = 0x00
	response[11] = 0x01

	response[12] = (byte(clientAddr.Port >> 8)) ^ data[4]
	response[13] = (byte(clientAddr.Port)) ^ data[5]
	response[14] = ip[0] ^ data[4]
	response[15] = ip[1] ^ data[5]
	response[16] = ip[2] ^ data[6]
	response[17] = ip[3] ^ data[7]

	s.listener.WriteToUDP(response, clientAddr)
}

func (s *TURNServer) handleAllocateRequest(data []byte, clientAddr *net.UDPAddr) {
	relayAddr := &net.UDPAddr{
		IP:   net.ParseIP("0.0.0.0"),
		Port: 0,
	}

	relayConn, err := net.ListenUDP("udp4", relayAddr)
	if err != nil {
		log.Errorf("Failed to create relay: %v", err)
		return
	}

	relayAddr = relayConn.LocalAddr().(*net.UDPAddr)

	sessionID := fmt.Sprintf("%s:%d", clientAddr.IP, clientAddr.Port)
	session := &Session{
		ID:        sessionID,
		Client:    clientAddr,
		Relay:     relayAddr,
		RelayConn: relayConn,
		Created:   time.Now(),
		Expires:   time.Now().Add(10 * time.Minute),
	}

	s.sessions[sessionID] = session

	go s.relayLoop(session)

	response := make([]byte, 20)
	response[0] = 0x01
	response[1] = 0x03
	response[2] = 0x00
	response[3] = 0x00

	copy(response[4:8], data[4:8])

	response[8] = 0x00
	response[9] = 0x20

	ip := relayAddr.IP.To4()
	response[10] = 0x00
	response[11] = 0x01
	response[12] = (byte(relayAddr.Port >> 8)) ^ data[4]
	response[13] = (byte(relayAddr.Port)) ^ data[5]
	response[14] = ip[0] ^ data[4]
	response[15] = ip[1] ^ data[5]
	response[16] = ip[2] ^ data[6]
	response[17] = ip[3] ^ data[7]

	s.listener.WriteToUDP(response, clientAddr)

	log.Infof("Allocated relay %s:%d for client %s", ip, relayAddr.Port, clientAddr)
}

func (s *TURNServer) handleRefreshRequest(data []byte, clientAddr *net.UDPAddr) {
	sessionID := fmt.Sprintf("%s:%d", clientAddr.IP, clientAddr.Port)

	if session, ok := s.sessions[sessionID]; ok {
		session.Expires = time.Now().Add(10 * time.Minute)
	}

	response := make([]byte, 20)
	response[0] = 0x01
	response[1] = 0x04
	response[2] = 0x00
	response[3] = 0x00

	copy(response[4:8], data[4:8])

	s.listener.WriteToUDP(response, clientAddr)
}

func (s *TURNServer) handleSendIndication(data []byte, clientAddr *net.UDPAddr) {
	sessionID := fmt.Sprintf("%s:%d", clientAddr.IP, clientAddr.Port)

	session, ok := s.sessions[sessionID]
	if !ok {
		return
	}

	if len(data) < 24 {
		return
	}

	targetPort := (uint16(data[12]) << 8) | uint16(data[13])
	targetIP := net.IPv4(data[14], data[15], data[16], data[17])

	targetAddr := &net.UDPAddr{
		IP:   targetIP,
		Port: int(targetPort),
	}

	session.RelayConn.WriteToUDP(data[20:], targetAddr)
}

func (s *TURNServer) relayLoop(session *Session) {
	defer session.RelayConn.Close()

	buffer := make([]byte, 1500)
	for {
		n, remoteAddr, err := session.RelayConn.ReadFromUDP(buffer)
		if err != nil {
			return
		}

		if time.Now().After(session.Expires) {
			return
		}

		response := make([]byte, 20+n)
		response[0] = 0x00
		response[1] = 0x07

		ip := remoteAddr.IP.To4()
		response[8] = 0x00
		response[9] = 0x20
		response[10] = 0x00
		response[11] = 0x01
		response[12] = byte(remoteAddr.Port >> 8)
		response[13] = byte(remoteAddr.Port)
		response[14] = ip[0]
		response[15] = ip[1]
		response[16] = ip[2]
		response[17] = ip[3]

		copy(response[20:], buffer[:n])

		s.listener.WriteToUDP(response, session.Client)
	}
}

func (s *TURNServer) cleanupSessions(ctx context.Context) {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			now := time.Now()
			for id, session := range s.sessions {
				if now.After(session.Expires) {
					session.RelayConn.Close()
					delete(s.sessions, id)
					log.Infof("Cleaned up expired session: %s", id)
				}
			}
		}
	}
}
