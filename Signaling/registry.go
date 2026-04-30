package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	log "github.com/sirupsen/logrus"
)

type DeviceInfo struct {
	UUID        string    `json:"uuid"`
	PublicKey   string    `json:"public_key"`
	IPAddress   string    `json:"ip_address"`
	NATType     string    `json:"nat_type"`
	LastSeen    time.Time `json:"last_seen"`
	Registered  time.Time `json:"registered"`
	IsActive    bool      `json:"is_active"`
}

type SignalingMessage struct {
	Type      string `json:"type"`
	DeviceID  string `json:"device_id"`
	TargetID  string `json:"target_id,omitempty"`
	Payload   string `json:"payload"`
	Timestamp int64  `json:"timestamp"`
}

type Registry struct {
	mu      sync.RWMutex
	devices map[string]*DeviceInfo
}

func NewRegistry() *Registry {
	return &Registry{
		devices: make(map[string]*DeviceInfo),
	}
}

func (r *Registry) RegisterDevice(uuid, publicKey, ipAddress, natType string) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if existing, ok := r.devices[uuid]; ok {
		existing.LastSeen = time.Now()
		existing.IPAddress = ipAddress
		existing.NATType = natType
		existing.IsActive = true

		if existing.PublicKey != publicKey {
			log.Warnf("Public key changed for device %s", uuid)
			existing.PublicKey = publicKey
		}

		return nil
	}

	r.devices[uuid] = &DeviceInfo{
		UUID:       uuid,
		PublicKey:  publicKey,
		IPAddress:  ipAddress,
		NATType:    natType,
		LastSeen:   time.Now(),
		Registered: time.Now(),
		IsActive:   true,
	}

	log.Infof("Device registered: %s from %s", uuid, ipAddress)
	return nil
}

func (r *Registry) GetDevice(uuid string) (*DeviceInfo, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	device, ok := r.devices[uuid]
	if !ok {
		return nil, fmt.Errorf("device not found: %s", uuid)
	}

	return device, nil
}

func (r *Registry) UpdateDeviceStatus(uuid string, isActive bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	device, ok := r.devices[uuid]
	if !ok {
		return fmt.Errorf("device not found: %s", uuid)
	}

	device.IsActive = isActive
	device.LastSeen = time.Now()

	return nil
}

func (r *Registry) IsSignalingPayload(content string) bool {
	decoded, err := base64.StdEncoding.DecodeString(content)
	if err != nil {
		return false
	}

	var msg SignalingMessage
	if err := json.Unmarshal(decoded, &msg); err != nil {
		return false
	}

	validTypes := map[string]bool{
		"register":    true,
		"offer":       true,
		"answer":      true,
		"candidate":   true,
		"turn-request": true,
		"heartbeat":   true,
	}

	return validTypes[msg.Type]
}

func (r *Registry) ProcessSignalingMessage(content string) (string, error) {
	decoded, err := base64.StdEncoding.DecodeString(content)
	if err != nil {
		return "", fmt.Errorf("invalid base64: %v", err)
	}

	var msg SignalingMessage
	if err := json.Unmarshal(decoded, &msg); err != nil {
		return "", fmt.Errorf("invalid message format: %v", err)
	}

	switch msg.Type {
	case "register":
		return r.handleRegister(msg)
	case "offer":
		return r.handleOffer(msg)
	case "answer":
		return r.handleAnswer(msg)
	case "candidate":
		return r.handleCandidate(msg)
	case "turn-request":
		return r.handleTURNRequest(msg)
	case "heartbeat":
		return r.handleHeartbeat(msg)
	default:
		return "", fmt.Errorf("unknown message type: %s", msg.Type)
	}
}

func (r *Registry) handleRegister(msg SignalingMessage) (string, error) {
	var regData struct {
		UUID      string `json:"uuid"`
		PublicKey string `json:"public_key"`
		NATType   string `json:"nat_type"`
	}

	if err := json.Unmarshal([]byte(msg.Payload), &regData); err != nil {
		return "", fmt.Errorf("invalid registration data: %v", err)
	}

	if err := r.RegisterDevice(regData.UUID, regData.PublicKey, "", regData.NATType); err != nil {
		return "", err
	}

	response := map[string]interface{}{
		"status":   "registered",
		"uuid":     regData.UUID,
		"server_time": time.Now().Unix(),
	}

	responseJSON, _ := json.Marshal(response)
	return base64.StdEncoding.EncodeToString(responseJSON), nil
}

func (r *Registry) handleOffer(msg SignalingMessage) (string, error) {
	targetDevice, err := r.GetDevice(msg.TargetID)
	if err != nil {
		return "", err
	}

	_ = targetDevice

	response := map[string]interface{}{
		"status":  "forwarded",
		"target":  msg.TargetID,
		"payload": msg.Payload,
	}

	responseJSON, _ := json.Marshal(response)
	return base64.StdEncoding.EncodeToString(responseJSON), nil
}

func (r *Registry) handleAnswer(msg SignalingMessage) (string, error) {
	targetDevice, err := r.GetDevice(msg.TargetID)
	if err != nil {
		return "", err
	}

	_ = targetDevice

	response := map[string]interface{}{
		"status":  "forwarded",
		"target":  msg.TargetID,
		"payload": msg.Payload,
	}

	responseJSON, _ := json.Marshal(response)
	return base64.StdEncoding.EncodeToString(responseJSON), nil
}

func (r *Registry) handleCandidate(msg SignalingMessage) (string, error) {
	targetDevice, err := r.GetDevice(msg.TargetID)
	if err != nil {
		return "", err
	}

	_ = targetDevice

	response := map[string]interface{}{
		"status":  "forwarded",
		"target":  msg.TargetID,
		"payload": msg.Payload,
	}

	responseJSON, _ := json.Marshal(response)
	return base64.StdEncoding.EncodeToString(responseJSON), nil
}

func (r *Registry) handleTURNRequest(msg SignalingMessage) (string, error) {
	turnConfig := map[string]interface{}{
		"urls": []string{
			"turn:turn.example.com:443?transport=udp",
			"turn:turn.example.com:443?transport=tcp",
		},
		"username":   fmt.Sprintf("%s:%d", msg.DeviceID, time.Now().Add(24*time.Hour).Unix()),
		"credential": "auto-generated-credential",
	}

	response := map[string]interface{}{
		"status": "turn_allocated",
		"ice_servers": []map[string]interface{}{
			turnConfig,
		},
	}

	responseJSON, _ := json.Marshal(response)
	return base64.StdEncoding.EncodeToString(responseJSON), nil
}

func (r *Registry) handleHeartbeat(msg SignalingMessage) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if device, ok := r.devices[msg.DeviceID]; ok {
		device.LastSeen = time.Now()
		device.IsActive = true
	}

	response := map[string]interface{}{
		"status":      "alive",
		"server_time": time.Now().Unix(),
	}

	responseJSON, _ := json.Marshal(response)
	return base64.StdEncoding.EncodeToString(responseJSON), nil
}
