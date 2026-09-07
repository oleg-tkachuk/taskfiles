// Command taskfiles-demo is a minimal HTTP service that exists to be built,
// tested, scanned, signed and deployed by the taskfiles library — the
// service itself is a prop, not the point.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
)

// Quote is one line from the /quote endpoint.
type Quote struct {
	Text   string `json:"text"`
	Author string `json:"author"`
}

var quotes = []Quote{
	{"Make it work, make it right, make it fast.", "Kent Beck"},
	{"Simplicity is prerequisite for reliability.", "Edsger Dijkstra"},
	{"The best code is no code at all.", "Jeff Atwood"},
	{"Programs must be written for people to read.", "Harold Abelson"},
	{"Any fool can write code that a computer can understand.", "Martin Fowler"},
}

func healthzHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func quoteHandler(w http.ResponseWriter, _ *http.Request) {
	q := quotes[rand.IntN(len(quotes))]
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(q)
}

func versionHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"version":  envOr("APP_VERSION", "dev"),
		"commit":   envOr("GIT_COMMIT_HASH", "unknown"),
		"built_at": envOr("BUILD_TIME", "unknown"),
	})
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	port := envOr("PORT", "8080")

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthzHandler)
	mux.HandleFunc("/quote", quoteHandler)
	mux.HandleFunc("/version", versionHandler)

	addr := fmt.Sprintf(":%s", port)
	log.Printf("taskfiles-demo %s listening on %s", envOr("APP_VERSION", "dev"), addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
