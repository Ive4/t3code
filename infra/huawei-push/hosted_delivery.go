package main

import (
	"context"
	"log"
	"net/http"
	"slices"
	"time"
)

const (
	hostedDeliveryTTL = 10 * time.Minute
	hostedEventTTL    = 24 * time.Hour
	hostedMaxEvents   = 8192
)

var hostedPhaseBodies = map[string]string{
	"completed":            "Agent finished",
	"failed":               "Agent turn failed",
	"waiting_for_approval": "Agent needs approval",
	"waiting_for_input":    "Agent needs input",
}

type hostedDelivery struct {
	SessionID      string    `json:"sessionId"`
	RegistrationID string    `json:"registrationId"`
	Attempts       int       `json:"attempts,omitempty"`
	RetryAt        time.Time `json:"retryAt,omitzero"`
}

type hostedEvent struct {
	EnvironmentID   string           `json:"environmentId,omitempty"`
	ThreadID        string           `json:"threadId,omitempty"`
	Phase           string           `json:"phase,omitempty"`
	SenderSessionID string           `json:"senderSessionId,omitempty"`
	Deadline        time.Time        `json:"deadline,omitzero"`
	ExpiresAt       time.Time        `json:"expiresAt"`
	Deliveries      []hostedDelivery `json:"deliveries,omitempty"`
}

func (server *hostedPushServer) postEvent(w http.ResponseWriter, r *http.Request) {
	var input struct {
		EventID       string `json:"eventId"`
		EnvironmentID string `json:"environmentId"`
		ThreadID      string `json:"threadId"`
		Phase         string `json:"phase"`
		OccurredAt    string `json:"occurredAt"`
	}
	if !server.readSessionJSON(w, r, "desktop", &input) {
		return
	}
	server.mu.Lock()
	defer server.mu.Unlock()
	now := server.now().UTC()
	sessionID, session, ok := server.sessionLocked(w, r, "desktop", now)
	if !ok {
		return
	}
	_, phaseOK := hostedPhaseBodies[input.Phase]
	occurredAt, err := time.Parse(time.RFC3339Nano, input.OccurredAt)
	if err != nil || !phaseOK ||
		!validPushIdentifier(input.EventID, 255) || !validPushIdentifier(input.EnvironmentID, 255) ||
		!validPushIdentifier(input.ThreadID, 512) {
		http.Error(w, "Invalid notification event", http.StatusBadRequest)
		return
	}
	eventID := hostedHash(session.Account + "\n" + input.EnvironmentID + "\n" + input.EventID)
	if existing, found := server.state.Events[eventID]; found && existing.ExpiresAt.After(now) {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if occurredAt.Before(now.Add(-2*time.Minute)) || occurredAt.After(now.Add(30*time.Second)) {
		http.Error(w, "Event timestamp is outside the delivery window", http.StatusBadRequest)
		return
	}
	if !server.allowLocked("event", session.Account, 60, 240, now) {
		respondHostedRateLimit(w)
		return
	}

	next := server.state.snapshot(now)
	if len(next.Events) >= hostedMaxEvents {
		respondHostedRateLimit(w)
		return
	}
	event := hostedEvent{ExpiresAt: now.Add(hostedEventTTL)}
	for id, mobile := range next.Sessions {
		if mobile.matches(session.Account, input.EnvironmentID, input.Phase, now) {
			event.Deliveries = append(event.Deliveries, hostedDelivery{SessionID: id, RegistrationID: mobile.RegistrationID})
		}
	}
	if len(event.Deliveries) > 0 {
		event.EnvironmentID = input.EnvironmentID
		event.ThreadID = input.ThreadID
		event.Phase = input.Phase
		event.SenderSessionID = sessionID
		event.Deadline = now.Add(hostedDeliveryTTL)
	}
	next.Events[eventID] = event
	if server.commitRequestLocked(w, next) {
		select {
		case server.wake <- struct{}{}:
		default:
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func (server *hostedPushServer) runDelivery(ctx context.Context) {
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
	for ctx.Err() == nil {
		if server.deliverOne(ctx) {
			continue
		}
		select {
		case <-ctx.Done():
		case <-server.wake:
		case <-tick.C:
		}
	}
}

func (server *hostedPushServer) deliverOne(ctx context.Context) bool {
	if ctx.Err() != nil {
		return false
	}
	now := server.now().UTC()
	server.mu.Lock()
	if server.dirty {
		if err := server.commitLocked(server.state.snapshot(now)); err != nil {
			server.mu.Unlock()
			return false
		}
	}
	key, event, delivery, token := server.nextDeliveryLocked(now)
	server.mu.Unlock()
	if key == "" {
		return false
	}

	var result string
	var err error
	if token != "" {
		result, err = server.send(ctx, notification{
			ID: key, Token: token, Title: "T3 Code", Body: hostedPhaseBodies[event.Phase],
			EnvironmentID: event.EnvironmentID, ThreadID: event.ThreadID, ExpiresAt: event.Deadline.UnixMilli(),
		}, now)
	}

	now = server.now().UTC()
	server.mu.Lock()
	defer server.mu.Unlock()
	next := server.state.snapshot(now)
	event, exists := next.Events[key]
	if !exists || len(event.Deliveries) == 0 {
		return true
	}
	index := slices.IndexFunc(event.Deliveries, func(item hostedDelivery) bool {
		return item.SessionID == delivery.SessionID
	})
	if index < 0 {
		return true
	}
	event.Deliveries = slices.Clone(event.Deliveries)
	if err != nil {
		delivery.RetryAt = now.Add(min(5*time.Second<<min(delivery.Attempts, 4), time.Minute))
		delivery.Attempts++
		event.Deliveries[index] = delivery
	} else {
		event.Deliveries = slices.Delete(event.Deliveries, index, index+1)
		if result == "invalid_token" {
			session, found := next.Sessions[delivery.SessionID]
			if found && session.RegistrationID == delivery.RegistrationID {
				session.RegistrationID = ""
				session.EnvironmentIDs = nil
				session.Phases = nil
				next.Sessions[delivery.SessionID] = session
			}
		}
	}
	if len(event.Deliveries) == 0 {
		event = hostedEvent{ExpiresAt: event.ExpiresAt}
	}
	next.Events[key] = event
	if err := server.commitLocked(next); err != nil {
		log.Printf("Huawei push delivery state write failed: %v", err)
		// Avoid sending again while the delivery outcome is still pending on disk.
		server.state = next
		server.dirty = true
	}
	return true
}

func (server *hostedPushServer) nextDeliveryLocked(now time.Time) (string, hostedEvent, hostedDelivery, string) {
	for key, event := range server.state.Events {
		if !event.Deadline.After(now.Add(time.Second)) {
			continue
		}
		sender, senderFound := server.state.Sessions[event.SenderSessionID]
		for _, delivery := range event.Deliveries {
			if delivery.RetryAt.After(now) {
				continue
			}
			mobile, mobileFound := server.state.Sessions[delivery.SessionID]
			var token string
			if senderFound && sender.Role == "desktop" && sender.ExpiresAt.After(now) &&
				mobileFound && mobile.RegistrationID == delivery.RegistrationID &&
				mobile.matches(sender.Account, event.EnvironmentID, event.Phase, now) {
				token = mobile.PushToken
			}
			return key, event, delivery, token
		}
	}
	return "", hostedEvent{}, hostedDelivery{}, ""
}
