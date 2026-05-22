package rest

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/fagerbergj/document-pipeline/server/core/model"
)

func TestPatchDocument_AdditionalContextNudgesWaitingJobs(t *testing.T) {
	h, docs, jobs := newTestHandler(t)
	now := time.Now().UTC()
	doc := model.Document{ID: testDocID, ContentHash: "abc", CreatedAt: now, UpdatedAt: now}
	docs.Insert(context.Background(), doc)

	waiting := model.Job{
		ID: testJobID, DocumentID: testDocID, Stage: "clarify",
		Status: model.JobStatusWaiting, CreatedAt: now, UpdatedAt: now,
	}
	if err := jobs.Upsert(context.Background(), waiting); err != nil {
		t.Fatal(err)
	}

	rr := doRequest(t, h, http.MethodPatch, "/api/v1/documents/"+testDocID, map[string]any{
		"additional_context": "session 12 notes",
	})
	if rr.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rr.Code, rr.Body.String())
	}

	updated, err := jobs.GetByID(context.Background(), testJobID)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Status != model.JobStatusPending {
		t.Errorf("waiting job should be flipped to pending after context update, got %q", updated.Status)
	}
}

func TestPatchDocument_TitleOnlyDoesNotNudgeJobs(t *testing.T) {
	h, docs, jobs := newTestHandler(t)
	now := time.Now().UTC()
	doc := model.Document{ID: testDocID, ContentHash: "abc", CreatedAt: now, UpdatedAt: now}
	docs.Insert(context.Background(), doc)

	waiting := model.Job{
		ID: testJobID, DocumentID: testDocID, Stage: "clarify",
		Status: model.JobStatusWaiting, CreatedAt: now, UpdatedAt: now,
	}
	if err := jobs.Upsert(context.Background(), waiting); err != nil {
		t.Fatal(err)
	}

	rr := doRequest(t, h, http.MethodPatch, "/api/v1/documents/"+testDocID, map[string]any{
		"title": "Updated Title",
	})
	if rr.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rr.Code, rr.Body.String())
	}

	updated, err := jobs.GetByID(context.Background(), testJobID)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Status != model.JobStatusWaiting {
		t.Errorf("title-only patch should not affect waiting jobs, got %q", updated.Status)
	}
}
