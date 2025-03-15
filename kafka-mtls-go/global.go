package main

import (
	"crypto"
	"crypto/tls"
	"crypto/x509"
	"log"
	"os"

	pkcs12 "software.sslmate.com/src/go-pkcs12"
)

// Config holds the configuration values for the application
type Config struct {
	// Kafka configuration
	KafkaBrokers []string
	KafkaTopic   string

	// TLS configuration
	KafkaTlsDirectory          string
	KafkaTlsKeystoreFilename   string
	KafkaTlsKeystorePassword   string
	KafkaTlsTruststoreFilename string
	KafkaTlsTruststorePassword string
}

// Default configuration values
var AppConfig = Config{
	KafkaBrokers:               []string{"localhost:9094"},
	KafkaTopic:                 "timestamps_topic",
	KafkaTlsDirectory:          "../kafka-client",
	KafkaTlsKeystoreFilename:   "client.p12",
	KafkaTlsKeystorePassword:   "secret",
	KafkaTlsTruststoreFilename: "truststore.p12",
	KafkaTlsTruststorePassword: "secret",
}

// CreateTLSConfig creates a TLS configuration using the provided PKCS12 files
func CreateTLSConfig() *tls.Config {
	// Load keystore
	keystoreLocation := AppConfig.KafkaTlsDirectory + "/" + AppConfig.KafkaTlsKeystoreFilename
	keystoreData, err := os.ReadFile(keystoreLocation)
	if err != nil {
		log.Fatalf("Could not read keystore file: %s", err)
		os.Exit(1)
	}

	// Decode keystore
	privateKey, cert, err := pkcs12.Decode(keystoreData, AppConfig.KafkaTlsKeystorePassword)
	if err != nil {
		log.Fatalf("Could not decode keystore: %s", err)
		os.Exit(1)
	}

	// Load truststore
	truststoreLocation := AppConfig.KafkaTlsDirectory + "/" + AppConfig.KafkaTlsTruststoreFilename
	truststoreData, err := os.ReadFile(truststoreLocation)
	if err != nil {
		log.Fatalf("Could not read truststore file: %s", err)
		os.Exit(1)
	}

	// Decode truststore
	trustCerts, err := pkcs12.DecodeTrustStore(truststoreData, AppConfig.KafkaTlsTruststorePassword)
	if err != nil {
		log.Fatalf("Could not decode truststore: %s", err)
		os.Exit(1)
	}

	// Create CertPool and append the CA certificates
	caCertPool := x509.NewCertPool()
	for _, cert := range trustCerts {
		caCertPool.AddCert(cert)
	}

	// Create TLS cert
	tlsCert := tls.Certificate{
		Certificate: [][]byte{cert.Raw},
		PrivateKey:  privateKey.(crypto.PrivateKey),
		Leaf:        cert,
	}

	return &tls.Config{
		Certificates:       []tls.Certificate{tlsCert},
		RootCAs:            caCertPool,
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: false,
	}
}

type Message struct {
	Timestamp string `json:"timestamp"`
	Count     int    `json:"count"`
}
