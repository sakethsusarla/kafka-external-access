package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"

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
	config.Consumer.Return.Errors = true
	config.Version = sarama.V0_10_1_0 // Match the version in your Python code

	// Create a new consumer
	log.Println("Connecting to Kafka with mTLS...")
	consumer, err := sarama.NewConsumer(AppConfig.KafkaBrokers, config)
	if err != nil {
		log.Fatalf("Failed to create consumer: %v", err)
	}

	log.Println("Successfully connected to Kafka with mTLS!")

	// Trap SIGINT to trigger a shutdown
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt)

	topic := AppConfig.KafkaTopic

	// Get the list of partitions for the topic
	partitions, err := consumer.Partitions(topic)
	if err != nil {
		log.Fatalf("Failed to get partitions: %v", err)
	}

	var wg sync.WaitGroup

	// Start a consumer for each partition
	for _, partition := range partitions {
		wg.Add(1)

		go func(partition int32) {
			defer wg.Done()

			// Start consuming from the beginning of the partition
			partitionConsumer, err := consumer.ConsumePartition(topic, partition, sarama.OffsetOldest)
			if err != nil {
				log.Printf("Failed to start partition consumer: %v", err)
				return
			}

			defer func() {
				if err := partitionConsumer.Close(); err != nil {
					log.Printf("Error closing partition consumer: %v", err)
				}
			}()

			// Consume messages until signaled to stop
			for {
				select {
				case msg := <-partitionConsumer.Messages():
					var message Message
					if err := json.Unmarshal(msg.Value, &message); err != nil {
						log.Printf("Error unmarshaling message: %v", err)
						continue
					}
					log.Printf("Received timestamp: %s, count: %d", message.Timestamp, message.Count)
				case err := <-partitionConsumer.Errors():
					log.Printf("Error: %v", err)
				case <-signals:
					return
				}
			}
		}(partition)
	}

	log.Println("Waiting for messages...")

	// Wait for an interrupt signal to exit
	<-signals
	fmt.Println("Shutting down...")

	// Wait for all partition consumers to finish
	wg.Wait()

	if err := consumer.Close(); err != nil {
		log.Printf("Error closing consumer: %v", err)
	}

	log.Println("Consumer closed")
}
