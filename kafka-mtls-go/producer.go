package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"github.com/IBM/sarama"
)

func main() {
	// Set up logging
	log.SetOutput(os.Stdout)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)

	// Create TLS config
	tlsConfig := CreateTLSConfig()

	// Kafka configuration
	config := sarama.NewConfig()
	config.Net.TLS.Enable = true
	config.Net.TLS.Config = tlsConfig
	config.Producer.Return.Successes = true
	config.Version = sarama.V0_10_1_0 // Match the version in your Python code

	// Create a new producer
	log.Println("Connecting to Kafka with mTLS...")
	producer, err := sarama.NewSyncProducer(AppConfig.KafkaBrokers, config)
	if err != nil {
		log.Fatalf("Failed to create producer: %v", err)
	}
	defer func() {
		if err := producer.Close(); err != nil {
			log.Printf("Error closing producer: %v", err)
		}
	}()

	log.Println("Successfully connected to Kafka with mTLS!")

	// Trap SIGINT to trigger a shutdown
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt)

	topic := AppConfig.KafkaTopic
	messageCount := 0

	// Start producing messages
	log.Printf("Starting to send messages to topic: %s\n", topic)
producerLoop:
	for {
		select {
		case <-signals:
			fmt.Println("Received interrupt signal, shutting down...")
			break producerLoop
		default:
			timestamp := time.Now().Format(time.RFC3339)
			message := Message{
				Timestamp: timestamp,
				Count:     messageCount,
			}

			// Convert the message to JSON
			jsonMessage, err := json.Marshal(message)
			if err != nil {
				log.Printf("Error marshaling message: %v", err)
				continue
			}

			// Create a Kafka message
			msg := &sarama.ProducerMessage{
				Topic: topic,
				Value: sarama.StringEncoder(jsonMessage),
			}

			// Send the message
			partition, offset, err := producer.SendMessage(msg)
			if err != nil {
				log.Printf("Failed to deliver message %d: %v", messageCount, err)
			} else {
				log.Printf("Message %d delivered to partition %d at offset %d: %s",
					messageCount, partition, offset, timestamp)
			}

			messageCount++
			time.Sleep(1 * time.Second)
		}
	}

	log.Println("Producer closed")
}
