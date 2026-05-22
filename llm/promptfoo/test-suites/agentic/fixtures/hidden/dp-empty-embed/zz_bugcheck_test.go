package openai_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

func TestGenerateEmbed_SubstitutesEmptyInput(t *testing.T) {
	var seenInput any
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/embeddings", func(w http.ResponseWriter, r *http.Request) {
		var req map[string]any
		_ = json.NewDecoder(r.Body).Decode(&req)
		seenInput = req["input"]
		_ = json.NewEncoder(w).Encode(map[string]any{
			"data": []map[string]any{{"embedding": []float32{0.0}}},
		})
	})
	c := newClient(t, mux)
	if _, err := c.GenerateEmbed(context.Background(), "m", ""); err != nil {
		t.Fatal(err)
	}
	if seenInput != " " {
		t.Errorf("empty input not substituted: got %q", seenInput)
	}
}
