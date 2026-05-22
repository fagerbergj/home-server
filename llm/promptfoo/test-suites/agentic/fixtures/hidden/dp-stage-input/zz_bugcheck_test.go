package core

import "testing"

func TestFindInput_PrefersNonEmpty(t *testing.T) {
	stageData := map[string]map[string]any{
		"_ingest":    {"raw_text": ""},
		"transcribe": {"raw_text": "hello world"},
	}
	for i := 0; i < 100; i++ {
		got, field := findInput(stageData, "raw_text")
		if got != "hello world" || field != "raw_text" {
			t.Fatalf("iter %d: got (%q, %q), want (\"hello world\", \"raw_text\")", i, got, field)
		}
	}
}
