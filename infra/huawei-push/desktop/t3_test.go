package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/net/websocket"
)

func TestPairT3ExchangesOnlyTheReadScope(t *testing.T) {
	for _, scope := range []string{"orchestration:read", "orchestration:read settings:write"} {
		t.Run(scope, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				switch req.URL.Path {
				case "/.well-known/t3/environment":
					io.WriteString(w, `{"environmentId":"env-id","orchestrationProtocolVersion":2}`)
				case "/oauth/token":
					if req.Method != http.MethodPost || req.FormValue("subject_token") != "pair+secret" || req.FormValue("scope") != "orchestration:read" {
						t.Error("pairing request did not request the read-only grant")
					}
					if req.FormValue("grant_type") != "urn:ietf:params:oauth:grant-type:token-exchange" || req.FormValue("subject_token_type") != "urn:t3:params:oauth:token-type:environment-bootstrap" {
						t.Error("pairing request did not use the official token-exchange grant")
					}
					fmt.Fprintf(w, `{"token_type":"Bearer","access_token":"desktop-session","scope":%q}`, scope)
				default:
					http.NotFound(w, req)
				}
			}))
			defer server.Close()
			connection, err := pairT3(context.Background(), server.URL+"/pair#token=pair%2Bsecret")
			if scope != "orchestration:read" {
				if err == nil || connection.AccessToken != "" {
					t.Fatalf("overprivileged response accepted")
				}
				return
			}
			want := t3Connection{BaseURL: server.URL, EnvironmentID: "env-id", AccessToken: "desktop-session"}
			if err != nil || connection != want {
				t.Fatalf("connection differs from read-only pairing result, error %v", err)
			}
		})
	}
}

func TestPairT3KeepsPairingCredentialsOnLoopback(t *testing.T) {
	redirected := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		t.Error("pairing request was redirected")
	}))
	defer redirected.Close()
	original := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/.well-known/t3/environment" {
			io.WriteString(w, `{"environmentId":"env-id","orchestrationProtocolVersion":2}`)
			return
		}
		http.Redirect(w, req, redirected.URL, http.StatusTemporaryRedirect)
	}))
	defer original.Close()
	for _, link := range []string{
		"https://example.test/pair#token=pair-secret",
		"http://127.0.0.1.example.test/pair#token=pair-secret",
		"http://pair-secret@127.0.0.1/pair#token=pair-secret",
		original.URL + "/pair?token=pair-secret",
		original.URL + "/pair#token=pair-secret&token=other",
		original.URL + "/pair#token=pair-secret",
	} {
		_, err := pairT3(context.Background(), link)
		if err == nil || strings.Contains(err.Error(), "pair-secret") {
			t.Fatalf("pairing link was accepted or leaked in its error")
		}
	}
}

func TestWatchT3ResumesAfterTheLastConsumedShellUpdate(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	var streams atomic.Int32
	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/t3/environment", func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, `{"environmentId":"env","orchestrationProtocolVersion":2}`)
	})
	mux.HandleFunc("GET /api/auth/session", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer scoped-session" {
			t.Error("T3 session check did not use its paired bearer")
		}
		io.WriteString(w, `{"authenticated":true,"scopes":["orchestration:read"]}`)
	})
	mux.HandleFunc("POST /api/auth/websocket-ticket/rpc", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer scoped-session" {
			t.Error("T3 ticket request did not use its paired bearer")
		}
		io.WriteString(w, `{"ticket":"local-ticket"}`)
	})
	mux.Handle("GET /ws", websocket.Handler(func(ws *websocket.Conn) {
		_ = ws.SetDeadline(time.Now().Add(3 * time.Second))
		query := ws.Request().URL.Query()
		if query.Get("orchestrationProtocol") != "2" || query.Get("wsTicket") != "local-ticket" {
			t.Error("T3 WebSocket did not use protocol 2 with a ticket")
		}
		var subscribe struct {
			ID      string `json:"id"`
			Tag     string `json:"tag"`
			Payload struct {
				AfterSequence *int64 `json:"afterSequence"`
			} `json:"payload"`
		}
		if err := websocket.JSON.Receive(ws, &subscribe); err != nil || subscribe.Tag != "orchestration.subscribeShell" {
			t.Errorf("expected the read-only shell subscription, got %q, %v", subscribe.Tag, err)
			return
		}
		now := time.Now().UTC().Format(time.RFC3339Nano)
		approval := `{"id":"thread","status":"waiting","pendingRuntimeRequest":{"id":"approval","kind":"command","createdAt":"` + now + `"}}`
		var items string
		switch tries := streams.Add(1); tries {
		case 1:
			if subscribe.Payload.AfterSequence != nil {
				t.Error("first connection tried to replay history")
			}
			items = `{"kind":"snapshot","snapshot":{"snapshotSequence":10,"threads":[]}},` +
				`{"kind":"thread.updated","sequence":11,"location":"active","thread":` + approval + `}`
		case 2:
			if after := subscribe.Payload.AfterSequence; after == nil || *after != 11 {
				t.Error("reconnect did not resume from the last consumed sequence 11")
			}
			items = `{"kind":"snapshot","resolvedRepositoryIdentityRoots":[],"snapshot":{"snapshotSequence":20,"threads":[]}},` +
				`{"kind":"thread.updated","sequence":12,"location":"active","thread":` + approval + `},` +
				`{"kind":"thread.updated","sequence":13,"location":"active","thread":{"id":"thread","status":"completed","latestRunId":"run","latestRunCompletedAt":"` + now + `"}}`
		default:
			t.Error("unexpected further reconnect")
			return
		}
		if err := websocket.Message.Send(ws, `{"_tag":"Chunk","requestId":`+fmt.Sprintf("%q", subscribe.ID)+`,"values":[`+items+`]}`); err != nil {
			t.Errorf("writing test T3 frames: %v", err)
			return
		}
		var ack struct {
			Tag       string `json:"_tag"`
			RequestID string `json:"requestId"`
		}
		if err := websocket.JSON.Receive(ws, &ack); err != nil || ack.Tag != "Ack" || ack.RequestID != subscribe.ID {
			t.Errorf("expected T3 stream acknowledgement, got %+v, %v", ack, err)
			return
		}
		if streams.Load() == 2 {
			cancel()
		}
	}))
	server := httptest.NewServer(mux)
	defer server.Close()
	var phases []string
	err := watchT3(ctx, t3Connection{BaseURL: server.URL, EnvironmentID: "env", AccessToken: "scoped-session"},
		func(_ context.Context, event pushEvent) error {
			phases = append(phases, event.Phase)
			return nil
		})
	if !errors.Is(err, context.Canceled) || !slices.Equal(phases, []string{"waiting_for_approval", "completed"}) {
		t.Fatalf("watcher returned %v and delivered %v", err, phases)
	}
}
