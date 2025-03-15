@echo off
REM Script to uninstall Kafka secrets, Kafka Client, Kafka Cluster, Kafka UI, and PVCs

set "NAMESPACE=kfk-k8s"

REM Delete Kafka UI
echo Deleting Kafka UI...
kubectl delete -f kafka-ui.yaml -n "%NAMESPACE%"

REM Uninstall kafka via Helm
helm uninstall kafka -n "%NAMESPACE%"

if %ERRORLEVEL% neq 0 (
    echo Failed to uninstall kafka via Helm!
    @REM exit /b 1
) else (
    echo Successfully uninstalled kafka via Helm!
)

REM Delete PVCs for Kafka
for /L %%i in (0,1,2) do (
    kubectl delete pvc data-kafka-controller-%%i -n "%NAMESPACE%"
)

REM Confirm deletion of the Secrets 
echo Verifying secret deletion (This may show errors if the namespace is already deleted)...
kubectl delete secret kafka-mtls -n "%NAMESPACE%"
kubectl delete secret kafka-client -n "%NAMESPACE%"
kubectl delete secret nginx-mtls -n "%NAMESPACE%"

echo Kafka uninstallation completed.
