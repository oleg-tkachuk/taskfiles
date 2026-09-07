package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthzHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	healthzHandler(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	if w.Body.String() != "ok" {
		t.Fatalf("body = %q, want %q", w.Body.String(), "ok")
	}
}

func TestQuoteHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/quote", nil)
	w := httptest.NewRecorder()

	quoteHandler(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	var got Quote
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if got.Text == "" || got.Author == "" {
		t.Fatalf("got empty quote: %+v", got)
	}
}

func TestVersionHandlerDefaults(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	w := httptest.NewRecorder()

	versionHandler(w, req)

	var got map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if got["version"] != "dev" {
		t.Fatalf("version = %q, want %q (no APP_VERSION set)", got["version"], "dev")
	}
}
