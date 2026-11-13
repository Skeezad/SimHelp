package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestCallStatusPreservesCanonicalAndroidIdentity(t *testing.T) {
	payload, err := json.Marshal(callRecord{ID: "agent-local-A", AndroidID: "telecom-A", State: "incoming"})
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["id"] != "agent-local-A" || decoded["android_id"] != "telecom-A" {
		t.Fatalf("call status lost explicit backend/canonical identity mapping: %s", payload)
	}
}

func TestOwnedDialProducerJSONReachesAndroidTelecom(t *testing.T) {
	a := testAndroidAgent("secret-value")
	response := httptest.NewRecorder()
	done := make(chan struct{})
	go func() {
		a.dial(response, httptest.NewRequest(http.MethodPost, "/api/calls/dial",
			strings.NewReader(`{"number":"123","operation_id":"fixture-operation"}`)))
		close(done)
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	if command, ok := a.android.next(ctx, 200*time.Millisecond); ok {
		if command.Action != "dial" || command.Number != "123" {
			t.Fatalf("wrong command: %#v", command)
		}
		_ = a.android.complete(androidCommandResult{ID: command.ID, Success: true})
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("dial did not complete")
	}
	if response.Code != http.StatusOK {
		t.Fatalf("owned dial rejected: %d %s", response.Code, response.Body.String())
	}
}

func TestLocalDTMFDoesNotTargetReplacementCall(t *testing.T) {
	a := testAndroidAgent("secret-value")
	a.calls.Active = &callRecord{ID: "current", AndroidID: "telecom-current", State: "active"}
	response := httptest.NewRecorder()
	done := make(chan struct{})
	go func() {
		a.dtmf(response, httptest.NewRequest(http.MethodPost, "/api/calls/dtmf",
			strings.NewReader(`{"digit":"5","call_id":"previous"}`)))
		close(done)
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	if command, ok := a.android.next(ctx, 100*time.Millisecond); ok {
		_ = a.android.complete(androidCommandResult{ID: command.ID, Success: true})
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("stale DTMF did not return")
	}
	if response.Code != http.StatusBadGateway {
		t.Fatalf("stale owned DTMF status=%d, require explicit identity rejection", response.Code)
	}
}

func TestLocalDTMFWithCurrentIdentityReachesOnlyThatTelecomCall(t *testing.T) {
	a := testAndroidAgent("secret-value")
	a.calls.Active = &callRecord{ID: "current", AndroidID: "telecom-current", State: "active"}
	response := httptest.NewRecorder()
	done := make(chan struct{})
	go func() {
		a.dtmf(response, httptest.NewRequest(http.MethodPost, "/api/calls/dtmf",
			strings.NewReader(`{"digit":"5","call_id":"current"}`)))
		close(done)
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	if command, ok := a.android.next(ctx, 100*time.Millisecond); ok {
		if command.CallID != "telecom-current" || command.Action != "dtmf" {
			t.Fatalf("wrong target: %#v", command)
		}
		_ = a.android.complete(androidCommandResult{ID: command.ID, Success: true})
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("owned DTMF did not return")
	}
	if response.Code != http.StatusOK {
		t.Fatalf("valid owned DTMF status=%d", response.Code)
	}
}

func TestCanonicalCallIDCapabilityRequiresAndroidTelecom(t *testing.T) {
	for _, enabled := range []bool{true, false} {
		service := &agent{at: newATPort("unused"), started: time.Now(),
			profile:      runtimeProfile{AndroidTelecom: enabled},
			voiceBackend: voiceBackendConfig{kind: voiceBackendSamsungAndroid, endpoint: "192.168.240.1:7580"}}
		recorder := httptest.NewRecorder()
		service.health(recorder, httptest.NewRequest("GET", "/api/health", nil))
		var payload map[string]any
		if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		if payload["canonical_call_ids"] != enabled {
			t.Fatalf("Android Telecom=%v, capability=%v", enabled, payload["canonical_call_ids"])
		}
	}
}
