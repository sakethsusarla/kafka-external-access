# Kafka on K8s

This repository contains scripts and configurations to set up Kafka on Kubernetes with mutual TLS authentication.

## Getting Started

### Prerequisites

- Windows (10+)
- Go installed
- Kubernetes cluster running on Minikube using Podman, Docker, or Rancher Desktop
- Java Development Kit (JDK) installed (for `keytool`)
- OpenSSL installed

### Setup

1. **Generate Certificates:**
    Run the following script to generate the necessary certificates:
    ```sh
    mkcerts.bat
    ```

2. **Install Kafka and Secrets:**
    Run the setup script to install Kafka and all required secrets:
    ```sh
    setup.bat
    ```

3. **Port Forwarding:**
    Once Kafka is up and running, you can set up port forwarding by running:
    ```sh
    fwd.bat
    ```

### Accessing Kafka UI

To access the Kafka UI, you can use the following command:
```sh
minikube service kafka-ui-service --url -n kfk-k8s
```

### Testing Connectivity

To test the connectivity (external access with mTLS), you can run the producer and consumer in the `kafka-mtls-go` directory:

- **Producer:**
  ```sh
  go run .\global.go .\producer.go
  ```

- **Consumer:**
  ```sh
  go run .\global.go .\consumer.go
  ```

### Teardown

To uninstall Kafka and delete all secrets, run the following script:
```sh
teardown.bat
```
