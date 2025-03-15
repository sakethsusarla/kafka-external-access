@echo off
echo Starting Kafka port-forwarding...

REM Set your namespace - change as needed
set NAMESPACE=kfk-k8s

REM Bootstrap connection
start "Kafka Bootstrap Port" cmd /k "kubectl port-forward service/kafka-controller-0-external -n %NAMESPACE% 9094:9094 && pause"

REM Allow a moment for the first command to establish
timeout /t 2 /nobreak > nul

REM NodePort forwarding
start "Kafka NodePort 30000" cmd /k "kubectl port-forward service/kafka-controller-0-external -n %NAMESPACE% 30000:9094 && pause"

REM Allow a moment between commands to avoid overwhelming kubectl
timeout /t 1 /nobreak > nul

start "Kafka NodePort 30001" cmd /k "kubectl port-forward service/kafka-controller-1-external -n %NAMESPACE% 30001:9094 && pause"

timeout /t 1 /nobreak > nul

start "Kafka NodePort 30002" cmd /k "kubectl port-forward service/kafka-controller-2-external -n %NAMESPACE% 30002:9094 && pause"

echo All port-forwarding tasks started in separate windows!
echo To stop, close all command windows or press Ctrl+C in each window.