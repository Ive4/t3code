package main

import (
	"context"
	"crypto/tls"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func readHostedAccountClient(role string) (*huaweiAccountClient, error) {
	prefix := "HUAWEI_PUSH_" + role + "_CLIENT_"
	id := os.Getenv(prefix + "ID")
	secret := os.Getenv(prefix + "SECRET")
	if !validHuaweiCredential(id, 64) || !validHuaweiCredential(secret, huaweiAccountMaxCredential) {
		return nil, errors.New(prefix + "ID and " + prefix + "SECRET are required")
	}
	return newHuaweiAccountClient(id, secret), nil
}

func runHostedPush() error {
	desktop, err := readHostedAccountClient("DESKTOP")
	if err != nil {
		return err
	}
	mobile, err := readHostedAccountClient("MOBILE")
	if err != nil {
		return err
	}
	push, err := loadHuaweiClient(os.Getenv("HUAWEI_PUSH_SERVICE_ACCOUNT_FILE"), os.Getenv("HUAWEI_PUSH_PROJECT_ID"))
	if err != nil {
		return err
	}
	handler, err := newHostedPushServer(os.Getenv("HUAWEI_PUSH_STATE_FILE"), desktop, mobile, push.send, time.Now)
	if err != nil {
		return err
	}
	address := os.Getenv("HUAWEI_PUSH_LISTEN_ADDR")
	if address == "" {
		address = "127.0.0.1:8080"
	}
	cert := os.Getenv("HUAWEI_PUSH_TLS_CERT_FILE")
	key := os.Getenv("HUAWEI_PUSH_TLS_KEY_FILE")
	if (cert == "") != (key == "") {
		return errors.New("HUAWEI_PUSH_TLS_CERT_FILE and HUAWEI_PUSH_TLS_KEY_FILE must be set together")
	}
	tlsConfig := &tls.Config{MinVersion: tls.VersionTLS12}
	if cert != "" {
		pair, err := tls.LoadX509KeyPair(cert, key)
		if err != nil {
			return err
		}
		tlsConfig.Certificates = []tls.Certificate{pair}
	}
	host, _, err := net.SplitHostPort(address)
	if err != nil || (cert == "" && !net.ParseIP(host).IsLoopback()) {
		return errors.New("HUAWEI_PUSH_LISTEN_ADDR must include a port and needs TLS for non-loopback addresses")
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return err
	}
	defer listener.Close()

	server := &http.Server{
		Handler:           handler,
		TLSConfig:         tlsConfig,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      20 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	deliveryDone := make(chan struct{})
	go func() {
		defer close(deliveryDone)
		handler.runDelivery(ctx)
	}()
	shutdownDone := make(chan struct{})
	go func() {
		defer close(shutdownDone)
		<-ctx.Done()
		timeout, stop := context.WithTimeout(context.Background(), 20*time.Second)
		defer stop()
		_ = server.Shutdown(timeout)
	}()

	log.Printf("Huawei push API listening on %s", listener.Addr())
	if cert == "" {
		err = server.Serve(listener)
	} else {
		err = server.ServeTLS(listener, "", "")
	}
	cancel()
	<-deliveryDone
	<-shutdownDone
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
