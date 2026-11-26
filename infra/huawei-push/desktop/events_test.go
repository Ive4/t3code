package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"testing"
	"time"
)

func TestShellAlertsOnlyForFreshTransitions(t *testing.T) {
	now := time.Date(2026, 11, 24, 9, 40, 0, 0, time.UTC)
	state := shellState{environmentID: "t3-local", startedAt: now.Add(-time.Minute)}
	var alerts []pushEvent
	add := func(raw string) {
		t.Helper()
		var item shellItem
		if err := json.Unmarshal([]byte(raw), &item); err != nil {
			t.Fatal(err)
		}
		if err := state.observe(item, now, func(event pushEvent) error {
			alerts = append(alerts, event)
			return nil
		}); err != nil {
			t.Fatal(err)
		}
	}
	update := func(seq int, location, shell string) {
		t.Helper()
		add(fmt.Sprintf(`{"kind":"thread.updated","sequence":%d,"location":%q,"thread":%s}`, seq, location, shell))
	}
	add(`{"kind":"snapshot","snapshot":{"snapshotSequence":10,"threads":[{"id":"one","status":"waiting","pendingRuntimeRequest":{"id":"already-waiting","kind":"command","createdAt":"2026-11-24T09:39:30Z"}}]}}`)
	update(11, "active", `{"id":"one","status":"waiting","pendingRuntimeRequest":{"id":"already-waiting","kind":"command","createdAt":"2026-11-24T09:39:30Z"}}`)
	update(12, "active", `{"id":"reopened","status":"completed","latestRunId":"old","latestRunCompletedAt":"2026-11-24T09:38:45Z"}`)
	update(13, "archive", `{"id":"archived","status":"failed","latestRunId":"old","latestRunCompletedAt":"2026-11-24T09:39:30Z"}`)
	update(14, "active", `{"id":"one","status":"waiting","pendingRuntimeRequest":{"id":"interactive-approval","kind":"permission","createdAt":"2026-11-24T09:39:35Z"}}`)
	add(`{"kind":"snapshot","resolvedRepositoryIdentityRoots":[],"snapshot":{"snapshotSequence":40,"threads":[]}}`)
	update(15, "active", `{"id":"one","status":"waiting","pendingRuntimeRequest":{"id":"interactive-approval","kind":"permission","createdAt":"2026-11-24T09:39:35Z"}}`)
	update(16, "active", `{"id":"one","status":"running","pendingRuntimeRequest":{"id":"user-choice","kind":"user_input","createdAt":"2026-11-24T09:39:45Z"}}`)
	update(17, "active", `{"id":"one","status":"completed","latestRunId":"run-a","latestRunCompletedAt":"2026-11-24T09:39:50Z"}`)
	update(17, "active", `{"id":"one","status":"failed","latestRunId":"should-not-replay","latestRunCompletedAt":"2026-11-24T09:39:51Z"}`)
	update(18, "active", `{"id":"one","status":"completed","latestRunId":"run-stopped","latestRunStopRequested":true,"latestRunCompletedAt":"2026-11-24T09:39:55Z"}`)
	update(19, "active", `{"id":"one","status":"failed","latestRunId":"run-b","latestRunCompletedAt":"2026-11-24T09:39:58Z"}`)
	update(20, "active", `{"id":"one","status":"waiting","pendingRuntimeRequest":{"id":"refresh","kind":"auth_refresh","createdAt":"2026-11-24T09:40:00Z"}}`)
	update(21, "active", `{"id":"one","status":"completed","latestRunId":"muted","latestRunCompletedAt":"2026-11-24T09:40:00Z","snoozedAt":"2026-11-24T09:39:00Z","snoozedUntil":"2026-11-24T10:00:00Z"}`)
	update(22, "active", `{"id":"one","status":"completed","latestRunId":"run-background","latestRunCompletedAt":"2026-11-24T09:40:00Z","pendingBackgroundTasks":[{"kind":"subagent"}]}`)
	var phases []string
	for _, alert := range alerts {
		if alert.EnvironmentID != "t3-local" || alert.ThreadID != "one" || len(alert.EventID) != 64 || alert.OccurredAt.IsZero() {
			t.Fatalf("unexpected alert %+v", alert)
		}
		phases = append(phases, alert.Phase)
	}
	want := []string{"waiting_for_approval", "waiting_for_input", "completed", "failed"}
	if !slices.Equal(phases, want) {
		t.Fatalf("phases %v, want %v", phases, want)
	}
}

func TestShellCursorKeepsEventUntilDeliverySucceeds(t *testing.T) {
	now := time.Date(2026, 11, 24, 9, 40, 0, 0, time.UTC)
	initial := int64(1)
	state := shellState{environmentID: "env", startedAt: now.Add(-time.Minute), cursor: &initial}
	var update shellItem
	if err := json.Unmarshal([]byte(`{"kind":"thread.updated","sequence":2,"location":"active","thread":{"id":"thread","status":"completed","latestRunId":"run","latestRunCompletedAt":"2026-11-24T09:40:00Z"}}`), &update); err != nil {
		t.Fatal(err)
	}
	unavailable := errors.New("temporary delivery failure")
	var first pushEvent
	if err := state.observe(update, now, func(event pushEvent) error {
		first = event
		return unavailable
	}); !errors.Is(err, unavailable) || *state.cursor != 1 {
		t.Fatalf("cursor %d, error %v after failed delivery", *state.cursor, err)
	}
	if err := state.observe(update, now, func(event pushEvent) error {
		if event != first {
			t.Fatalf("retry changed event identity, got %+v, want %+v", event, first)
		}
		return nil
	}); err != nil || *state.cursor != 2 {
		t.Fatalf("cursor %d, error %v after retry", *state.cursor, err)
	}
}
