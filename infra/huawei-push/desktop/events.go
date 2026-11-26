package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

const pushEventMaxAge = 2 * time.Minute

type pushEvent struct {
	EventID       string    `json:"eventId"`
	EnvironmentID string    `json:"environmentId"`
	ThreadID      string    `json:"threadId"`
	Phase         string    `json:"phase"`
	OccurredAt    time.Time `json:"occurredAt"`
}

type shellThread struct {
	ID                       string    `json:"id"`
	Status                   string    `json:"status"`
	ActivityRunStatus        string    `json:"activityRunStatus"`
	LatestRunID              string    `json:"latestRunId"`
	LatestRunCompletedAt     time.Time `json:"latestRunCompletedAt"`
	LatestRunStopRequested   bool      `json:"latestRunStopRequested"`
	LatestRunBackgroundWake  bool      `json:"latestRunBackgroundWake"`
	SettledOverride          string    `json:"settledOverride"`
	SnoozedAt                time.Time `json:"snoozedAt"`
	SnoozedUntil             time.Time `json:"snoozedUntil"`
	PendingGuestMessageCount int       `json:"pendingGuestMessageCount"`
	Lineage                  struct {
		RelationshipToParent string `json:"relationshipToParent"`
		SideChat             bool   `json:"sideChat"`
		WorkflowStep         bool   `json:"workflowStep"`
	} `json:"lineage"`
	PendingRuntimeRequest *struct {
		ID        string    `json:"id"`
		Kind      string    `json:"kind"`
		CreatedAt time.Time `json:"createdAt"`
	} `json:"pendingRuntimeRequest"`
	PendingBackgroundTasks []struct {
		Kind    string `json:"kind"`
		TaskID  string `json:"taskId"`
		Awaited bool   `json:"awaited"`
	} `json:"pendingBackgroundTasks"`
}

type shellItem struct {
	Kind                            string          `json:"kind"`
	Sequence                        *int64          `json:"sequence"`
	Location                        string          `json:"location"`
	Thread                          *shellThread    `json:"thread"`
	ResolvedRepositoryIdentityRoots json.RawMessage `json:"resolvedRepositoryIdentityRoots"`
	Snapshot                        *struct {
		Sequence *int64        `json:"snapshotSequence"`
		Threads  []shellThread `json:"threads"`
	} `json:"snapshot"`
}

type shellState struct {
	environmentID string
	startedAt     time.Time
	cursor        *int64
	seen          map[string]time.Time
	pruneAt       time.Time
}

func (state *shellState) observe(item shellItem, now time.Time, deliver func(pushEvent) error) error {
	if state.seen == nil {
		state.seen = make(map[string]time.Time)
	}
	if !now.Before(state.pruneAt) {
		for id, expiry := range state.seen {
			if !expiry.After(now) {
				delete(state.seen, id)
			}
		}
		state.pruneAt = now.Add(pushEventMaxAge)
	}

	switch item.Kind {
	case "snapshot":
		// Enrichment snapshots contain projects only and can run ahead of the thread replay cursor.
		if item.ResolvedRepositoryIdentityRoots != nil {
			return nil
		}
		if item.Snapshot == nil || item.Snapshot.Sequence == nil || *item.Snapshot.Sequence < 0 {
			return errors.New("invalid T3 shell snapshot")
		}
		for _, thread := range item.Snapshot.Threads {
			if event, ok := state.recentEvent(thread, now); ok {
				state.seen[event.EventID] = event.OccurredAt.Add(pushEventMaxAge)
			}
		}
		state.cursor = item.Snapshot.Sequence
		return nil
	case "thread.updated", "thread.removed", "project.updated", "project.removed":
		if state.cursor == nil || item.Sequence == nil || *item.Sequence < 0 {
			return errors.New("T3 shell update without a baseline or sequence")
		}
		if *item.Sequence <= *state.cursor {
			return nil
		}
	default:
		return nil
	}

	if item.Kind == "thread.updated" && item.Location == "active" {
		if item.Thread == nil {
			return errors.New("missing T3 thread update")
		}
		if event, ok := state.recentEvent(*item.Thread, now); ok {
			if _, seen := state.seen[event.EventID]; !seen {
				if err := deliver(event); err != nil {
					return err
				}
				state.seen[event.EventID] = event.OccurredAt.Add(pushEventMaxAge)
			}
		}
	}
	state.cursor = item.Sequence
	return nil
}

func (state *shellState) recentEvent(thread shellThread, now time.Time) (pushEvent, bool) {
	if thread.ID == "" || thread.Lineage.RelationshipToParent == "subagent" || thread.Lineage.SideChat || thread.Lineage.WorkflowStep {
		return pushEvent{}, false
	}
	phase, sourceID, occurredAt := thread.pushPhase()
	if phase == "" || sourceID == "" || occurredAt.IsZero() || occurredAt.Before(state.startedAt) ||
		!now.Before(occurredAt.Add(pushEventMaxAge)) || occurredAt.After(now.Add(15*time.Second)) {
		return pushEvent{}, false
	}
	parts, _ := json.Marshal([]string{state.environmentID, thread.ID, phase, sourceID})
	hash := sha256.Sum256(parts)
	return pushEvent{EventID: hex.EncodeToString(hash[:]), EnvironmentID: state.environmentID,
		ThreadID: thread.ID, Phase: phase, OccurredAt: occurredAt}, true
}

func (thread shellThread) pushPhase() (phase string, id string, occurredAt time.Time) {
	if pending := thread.PendingRuntimeRequest; pending != nil {
		switch pending.Kind {
		case "user_input":
			return "waiting_for_input", pending.ID, pending.CreatedAt
		case "command", "file-read", "file-change", "mcp-elicitation", "permission", "dynamic_tool_call":
			return "waiting_for_approval", pending.ID, pending.CreatedAt
		}
	}
	if thread.ActivityRunStatus != "" || thread.SettledOverride == "settled" {
		return "", "", time.Time{}
	}
	switch thread.Status {
	case "completed":
		snoozed := thread.PendingGuestMessageCount == 0 &&
			!thread.LatestRunCompletedAt.Before(thread.SnoozedAt) &&
			thread.LatestRunCompletedAt.Before(thread.SnoozedUntil)
		if thread.LatestRunStopRequested || snoozed || thread.completionHeldByBackgroundTask() {
			return "", "", time.Time{}
		}
	case "failed":
	default:
		return "", "", time.Time{}
	}
	return thread.Status, thread.LatestRunID, thread.LatestRunCompletedAt
}

func (thread shellThread) completionHeldByBackgroundTask() bool {
	for _, task := range thread.PendingBackgroundTasks {
		if task.Awaited || task.Kind == "subagent" || task.Kind == "background_task" ||
			(thread.LatestRunBackgroundWake && task.Kind == "monitor" && !strings.HasPrefix(task.TaskID, "pull-request-watch:")) {
			return true
		}
	}
	return false
}
