package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	log "github.com/sirupsen/logrus"
)

type ChatCompletionRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
	Stream   bool      `json:"stream"`
}

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatCompletionResponse struct {
	ID      string   `json:"id"`
	Object  string   `json:"object"`
	Created int64    `json:"created"`
	Model   string   `json:"model"`
	Choices []Choice `json:"choices"`
}

type Choice struct {
	Index        int     `json:"index"`
	Message      Message `json:"message"`
	FinishReason string  `json:"finish_reason"`
}

type SSEChunk struct {
	ID      string       `json:"id"`
	Object  string       `json:"object"`
	Created int64        `json:"created"`
	Model   string       `json:"model"`
	Choices []SSEChoice  `json:"choices"`
}

type SSEChoice struct {
	Index        int         `json:"index"`
	Delta        SSEDelta    `json:"delta"`
	FinishReason *string     `json:"finish_reason"`
}

type SSEDelta struct {
	Role    string `json:"role,omitempty"`
	Content string `json:"content,omitempty"`
}

type Handler struct {
	registry *Registry
}

func NewHandler(registry *Registry) *Handler {
	return &Handler{
		registry: registry,
	}
}

func (h *Handler) HandleChatCompletions(w http.ResponseWriter, r *http.Request) {
	var req ChatCompletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if len(req.Messages) == 0 {
		http.Error(w, "Messages array is required", http.StatusBadRequest)
		return
	}

	lastMessage := req.Messages[len(req.Messages)-1]

	if h.registry.IsSignalingPayload(lastMessage.Content) {
		h.handleSignaling(w, r, lastMessage.Content, req.Stream)
		return
	}

	if req.Stream {
		h.handleStreamResponse(w, r, req)
	} else {
		h.handleNonStreamResponse(w, r, req)
	}
}

func (h *Handler) handleSignaling(w http.ResponseWriter, r *http.Request, content string, stream bool) {
	log.Info("Processing signaling payload")

	response, err := h.registry.ProcessSignalingMessage(content)
	if err != nil {
		log.Errorf("Signaling processing error: %v", err)
		http.Error(w, "Signaling error", http.StatusBadRequest)
		return
	}

	if stream {
		h.sendSSESignalingResponse(w, response)
	} else {
		h.sendJSONSignalingResponse(w, response)
	}
}

func (h *Handler) sendSSESignalingResponse(w http.ResponseWriter, payload string) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming not supported", http.StatusInternalServerError)
		return
	}

	chunk := SSEChunk{
		ID:      fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion.chunk",
		Created: time.Now().Unix(),
		Model:   "gpt-4o",
		Choices: []SSEChoice{
			{
				Index: 0,
				Delta: SSEDelta{
					Role:    "assistant",
					Content: payload,
				},
			},
		},
	}

	data, _ := json.Marshal(chunk)
	fmt.Fprintf(w, "data: %s\n\n", data)
	flusher.Flush()

	doneChunk := SSEChunk{
		ID:      chunk.ID,
		Object:  "chat.completion.chunk",
		Created: chunk.Created,
		Model:   "gpt-4o",
		Choices: []SSEChoice{
			{
				Index:        0,
				Delta:        SSEDelta{},
				FinishReason: strPtr("stop"),
			},
		},
	}

	data, _ = json.Marshal(doneChunk)
	fmt.Fprintf(w, "data: %s\n\n", data)
	fmt.Fprintf(w, "data: [DONE]\n\n")
	flusher.Flush()
}

func (h *Handler) sendJSONSignalingResponse(w http.ResponseWriter, payload string) {
	response := ChatCompletionResponse{
		ID:      fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion",
		Created: time.Now().Unix(),
		Model:   "gpt-4o",
		Choices: []Choice{
			{
				Index: 0,
				Message: Message{
					Role:    "assistant",
					Content: payload,
				},
				FinishReason: "stop",
			},
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *Handler) handleStreamResponse(w http.ResponseWriter, r *http.Request, req ChatCompletionRequest) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming not supported", http.StatusInternalServerError)
		return
	}

	responseText := "I'm ContextHelper, your AI assistant. How can I help you today?"

	words := splitIntoChunks(responseText, 3)
	for _, word := range words {
		chunk := SSEChunk{
			ID:      fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano()),
			Object:  "chat.completion.chunk",
			Created: time.Now().Unix(),
			Model:   req.Model,
			Choices: []SSEChoice{
				{
					Index: 0,
					Delta: SSEDelta{
						Content: word + " ",
					},
				},
			},
		}

		data, _ := json.Marshal(chunk)
		fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
		time.Sleep(50 * time.Millisecond)
	}

	doneChunk := SSEChunk{
		ID:      fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion.chunk",
		Created: time.Now().Unix(),
		Model:   req.Model,
		Choices: []SSEChoice{
			{
				Index:        0,
				Delta:        SSEDelta{},
				FinishReason: strPtr("stop"),
			},
		},
	}

	data, _ := json.Marshal(doneChunk)
	fmt.Fprintf(w, "data: %s\n\n", data)
	fmt.Fprintf(w, "data: [DONE]\n\n")
	flusher.Flush()
}

func (h *Handler) handleNonStreamResponse(w http.ResponseWriter, r *http.Request, req ChatCompletionRequest) {
	response := ChatCompletionResponse{
		ID:      fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion",
		Created: time.Now().Unix(),
		Model:   req.Model,
		Choices: []Choice{
			{
				Index: 0,
				Message: Message{
					Role:    "assistant",
					Content: "I'm ContextHelper, your AI assistant. How can I help you today?",
				},
				FinishReason: "stop",
			},
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *Handler) HandleListModels(w http.ResponseWriter, r *http.Request) {
	models := map[string]interface{}{
		"object": "list",
		"data": []map[string]interface{}{
			{
				"id":       "gpt-4o",
				"object":   "model",
				"created":  time.Now().Unix(),
				"owned_by": "context-helper",
			},
			{
				"id":       "gpt-4o-mini",
				"object":   "model",
				"created":  time.Now().Unix(),
				"owned_by": "context-helper",
			},
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models)
}

func (h *Handler) HandleHealth(w http.ResponseWriter, r *http.Request) {
	health := map[string]interface{}{
		"status":    "healthy",
		"timestamp": time.Now().Unix(),
		"version":   "1.0.0",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(health)
}

func splitIntoChunks(s string, chunkSize int) []string {
	words := []string{}
	current := ""

	for _, char := range s {
		current += string(char)
		if char == ' ' && len(current) >= chunkSize {
			words = append(words, current)
			current = ""
		}
	}

	if current != "" {
		words = append(words, current)
	}

	return words
}

func strPtr(s string) *string {
	return &s
}
