@echo off
REM Script to automate Kafka secrets creation, deployment, and basic operations

set "NAMESPACE=kfk-k8s"

REM Create Secrets for Kafka Broker
echo Creating secret for Kafka Broker...
kubectl create secret generic kafka-mtls --from-file=kafka-mtls -n "%NAMESPACE%"

REM Create Secrets for Kafka Client
REM Read the keystore and truststore passwords from the file
set /p keystorePassword=<kafka-client/creds
set /p truststorePassword=<kafka-client/creds
echo Creating secret for Kafka Client...
kubectl create secret generic kafka-client --from-file=kafka-client --from-literal=keystorePassword=%keystorePassword% --from-literal=truststorePassword=%truststorePassword% -n "%NAMESPACE%"

REM Create Secrets for Nginx Server
echo Creating secret for Nginx Server...
kubectl create secret generic nginx-mtls --from-file=nginx-mtls -n "%NAMESPACE%"

REM Add Bitnami repository to Helm
helm repo add bitnami https://charts.bitnami.com/bitnami

if %ERRORLEVEL% neq 0 (
    echo Failed to add Bitnami Helm repository!
    exit /b 1
) else (
    echo Successfully added Bitnami Helm repository!
)

REM Install or upgrade kafka via Helm
helm upgrade --install kafka -f values.yaml -n "%NAMESPACE%" bitnami/kafka

if %ERRORLEVEL% neq 0 (
    echo Failed to install or upgrade kafka via Helm!
    exit /b 1
) else (
    echo Successfully installed or upgraded kafka via Helm!
)

echo Waiting for Kafka to be in Running state...
timeout /t 60

REM Deploy Kafka UI
kubectl apply -f kafka-ui.yaml -n "%NAMESPACE%"

echo Setup completed successfully.
