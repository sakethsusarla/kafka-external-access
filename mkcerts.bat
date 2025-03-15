@echo off

REM Check if OpenSSL is installed
openssl version >nul 2>&1
if errorlevel 1 (
    echo Error: OpenSSL is not installed or not in PATH.
    pause
    exit /b 1
)

REM Check if keytool is installed
keytool -help >nul 2>&1
if errorlevel 1 (
    echo Error: keytool is not installed or not in PATH.
    pause
    exit /b 1
)

REM Define the Kafka certificate details and filenames
set CA_SUBJECT="/C=IN/O=ASTERIX/CN=kafka-ca"
set CONTROLLER_SUBJECT="/C=IN/O=ASTERIX/CN=kafka"
set CLIENT_SUBJECT="/C=IN/O=ASTERIX/CN=kafka-client"
set OPENSSL_CONF_KAFKA=kafka-san.cnf

REM Check if Kafka OpenSSL configuration file exists
if not exist "%OPENSSL_CONF_KAFKA%" (
    echo Error: Configuration file %OPENSSL_CONF_KAFKA% not found.
    pause
    exit /b 1
)

REM Define directories for Kafka keys and certificates
set KAFKA_DIR=kafka-mtls
set CLIENT_DIR=kafka-client

REM Define filenames for Kafka keys and certificates
set CA_KEY_FILE=%KAFKA_DIR%\ca-key.pem
set CA_CERT_FILE=%KAFKA_DIR%\ca-cert.pem
set CLIENT_KEY_FILE=%CLIENT_DIR%\client-key.pem
set CLIENT_CSR_FILE=%CLIENT_DIR%\client.csr
set CLIENT_CERT_FILE=%CLIENT_DIR%\client-cert.pem
set CA_SERIAL_FILE=%KAFKA_DIR%\ca-cert.srl
set CLIENT_P12=%CLIENT_DIR%\client.p12
set TRUSTSTORE_P12=%KAFKA_DIR%\truststore.p12

REM Kafka controllers
set KAFKA_CONTROLLERS=kafka-controller-0 kafka-controller-1 kafka-controller-2

REM Define passwords for keystore and truststore
set KEYSTORE_PASS=secret
set TRUSTSTORE_PASS=secret

REM Create directories if they do not exist
if not exist "%KAFKA_DIR%" mkdir "%KAFKA_DIR%"
if not exist "%CLIENT_DIR%" mkdir "%CLIENT_DIR%"

REM Remove existing Kafka files if they exist
if exist "%CA_KEY_FILE%" del "%CA_KEY_FILE%"
if exist "%CA_CERT_FILE%" del "%CA_CERT_FILE%"
if exist "%CLIENT_KEY_FILE%" del "%CLIENT_KEY_FILE%"
if exist "%CLIENT_CSR_FILE%" del "%CLIENT_CSR_FILE%"
if exist "%CLIENT_CERT_FILE%" del "%CLIENT_CERT_FILE%"
if exist "%CA_SERIAL_FILE%" del "%CA_SERIAL_FILE%"
if exist "%CLIENT_P12%" del "%CLIENT_P12%"
if exist "%TRUSTSTORE_P12%" del "%TRUSTSTORE_P12%"
if exist "%KAFKA_DIR%\kafka.truststore.jks" del "%KAFKA_DIR%\kafka.truststore.jks"
if exist "%KAFKA_DIR%\client.keystore.jks" del "%KAFKA_DIR%\client.keystore.jks"

for %%b in (%KAFKA_CONTROLLERS%) do (
    if exist "%KAFKA_DIR%\%%b-key.pem" del "%KAFKA_DIR%\%%b-key.pem"
    if exist "%KAFKA_DIR%\%%b.csr" del "%KAFKA_DIR%\%%b.csr"
    if exist "%KAFKA_DIR%\%%b-cert.pem" del "%KAFKA_DIR%\%%b-cert.pem"
    if exist "%KAFKA_DIR%\%%b.p12" del "%KAFKA_DIR%\%%b.p12"
    if exist "%KAFKA_DIR%\%%b.keystore.jks" del "%KAFKA_DIR%\%%b.keystore.jks"
)

REM Generate Kafka CA private key and certificate with CA:TRUE
openssl ecparam -genkey -name secp384r1 -out "%CA_KEY_FILE%"
if not exist "%CA_KEY_FILE%" (
    echo Error: Failed to generate CA key file %CA_KEY_FILE%
    pause
    exit /b 1
)

openssl req -x509 -new -nodes -key "%CA_KEY_FILE%" -sha512 -days 1825 -out "%CA_CERT_FILE%" -subj "%CA_SUBJECT%" -config "%OPENSSL_CONF_KAFKA%" -extensions v3_ca
if not exist "%CA_CERT_FILE%" (
    echo Error: Failed to generate CA certificate %CA_CERT_FILE%
    pause
    exit /b 1
)

REM Generate Kafka client private key
openssl ecparam -genkey -name secp384r1 -out "%CLIENT_KEY_FILE%"
if not exist "%CLIENT_KEY_FILE%" (
    echo Error: Failed to generate client key file %CLIENT_KEY_FILE%
    pause
    exit /b 1
)

REM Generate Kafka client certificate signing request (CSR) with SANs
openssl req -new -key "%CLIENT_KEY_FILE%" -out "%CLIENT_CSR_FILE%" -subj "%CLIENT_SUBJECT%" -config "%OPENSSL_CONF_KAFKA%" -extensions req_ext
if not exist "%CLIENT_CSR_FILE%" (
    echo Error: Failed to generate client CSR %CLIENT_CSR_FILE%
    pause
    exit /b 1
)

REM Generate Kafka client certificate signed by the Kafka CA including SANs (no CA:TRUE)
openssl x509 -req -in "%CLIENT_CSR_FILE%" -CA "%CA_CERT_FILE%" -CAkey "%CA_KEY_FILE%" -CAcreateserial -out "%CLIENT_CERT_FILE%" -days 365 -sha512 -extfile "%OPENSSL_CONF_KAFKA%" -extensions req_ext
if not exist "%CLIENT_CERT_FILE%" (
    echo Error: Failed to generate client certificate %CLIENT_CERT_FILE%
    pause
    exit /b 1
)

REM Convert Kafka client private key and certificate to PKCS12 format
openssl pkcs12 -export -in "%CLIENT_CERT_FILE%" -inkey "%CLIENT_KEY_FILE%" -out "%CLIENT_P12%" -name client-cert -CAfile "%CA_CERT_FILE%" -caname root -password pass:%KEYSTORE_PASS%
if not exist "%CLIENT_P12%" (
    echo Error: Failed to generate client PKCS12 file %CLIENT_P12%
    pause
    exit /b 1
)

REM Convert client PKCS12 keystore to JKS format
keytool -importkeystore -deststorepass %KEYSTORE_PASS% -destkeypass %KEYSTORE_PASS% -destkeystore "%CLIENT_DIR%\client.keystore.jks" -srckeystore "%CLIENT_P12%" -srcstoretype PKCS12 -srcstorepass %KEYSTORE_PASS% -alias client-cert -noprompt
if not exist "%CLIENT_DIR%\client.keystore.jks" (
    echo Error: Failed to generate client JKS keystore %CLIENT_DIR%\client.keystore.jks
    pause
    exit /b 1
)

REM Generate and sign certificates for Kafka controllers
for %%b in (%KAFKA_CONTROLLERS%) do (
    REM Generate controller private key
    openssl ecparam -genkey -name secp384r1 -out "%KAFKA_DIR%\%%b-key.pem"
    if not exist "%KAFKA_DIR%\%%b-key.pem" (
        echo Error: Failed to generate controller key file %KAFKA_DIR%\%%b-key.pem
        pause
        exit /b 1
    )

    REM Generate controller certificate signing request (CSR) with SANs
    openssl req -new -key "%KAFKA_DIR%\%%b-key.pem" -out "%KAFKA_DIR%\%%b.csr" -subj "%CONTROLLER_SUBJECT%/CN=%%b" -config "%OPENSSL_CONF_KAFKA%" -extensions req_ext
    if not exist "%KAFKA_DIR%\%%b.csr" (
        echo Error: Failed to generate controller CSR %KAFKA_DIR%\%%b.csr
        pause
        exit /b 1
    )

    REM Generate controller certificate signed by the Kafka CA including SANs (no CA:TRUE)
    openssl x509 -req -in "%KAFKA_DIR%\%%b.csr" -CA "%CA_CERT_FILE%" -CAkey "%CA_KEY_FILE%" -CAcreateserial -out "%KAFKA_DIR%\%%b-cert.pem" -days 365 -sha512 -extfile "%OPENSSL_CONF_KAFKA%" -extensions req_ext
    if not exist "%KAFKA_DIR%\%%b-cert.pem" (
        echo Error: Failed to generate controller certificate %KAFKA_DIR%\%%b-cert.pem
        pause
        exit /b 1
    )

    REM Convert controller private key and certificate to PKCS12 format
    openssl pkcs12 -export -in "%KAFKA_DIR%\%%b-cert.pem" -inkey "%KAFKA_DIR%\%%b-key.pem" -out "%KAFKA_DIR%\%%b.p12" -name %%b-cert -CAfile "%CA_CERT_FILE%" -caname root -password pass:%KEYSTORE_PASS%
    if not exist "%KAFKA_DIR%\%%b.p12" (
        echo Error: Failed to generate controller PKCS12 file %KAFKA_DIR%\%%b.p12
        pause
        exit /b 1
    )

    REM Convert controller PKCS12 keystore to JKS format
    keytool -importkeystore -deststorepass %KEYSTORE_PASS% -destkeypass %KEYSTORE_PASS% -destkeystore "%KAFKA_DIR%\%%b.keystore.jks" -srckeystore "%KAFKA_DIR%\%%b.p12" -srcstoretype PKCS12 -srcstorepass %KEYSTORE_PASS% -alias %%b-cert -noprompt
    if not exist "%KAFKA_DIR%\%%b.keystore.jks" (
        echo Error: Failed to generate controller JKS keystore %KAFKA_DIR%\%%b.keystore.jks
        pause
        exit /b 1
    )
)

REM Create a Kafka truststore by including the Kafka CA certificate in PKCS12 format
openssl pkcs12 -export -nokeys -jdktrust anyExtendedKeyUsage -out "%TRUSTSTORE_P12%" -in "%CA_CERT_FILE%" -name root-ca -password pass:%TRUSTSTORE_PASS%

if not exist "%TRUSTSTORE_P12%" (
    echo Error: Failed to generate truststore PKCS12 file %TRUSTSTORE_P12%
    pause
    exit /b 1
)

REM Create a Kafka truststore by importing the CA certificate into a JKS truststore
keytool -importcert -alias CARoot -file "%CA_CERT_FILE%" -keystore "%KAFKA_DIR%\kafka.truststore.jks" -storepass %TRUSTSTORE_PASS% -noprompt
if not exist "%KAFKA_DIR%\kafka.truststore.jks" (
    echo Error: Failed to generate Kafka truststore %KAFKA_DIR%\kafka.truststore.jks
    pause
    exit /b 1
)

REM Copy Kafka truststore to the client directory as well
copy "%TRUSTSTORE_P12%" "%CLIENT_DIR%\truststore.p12"
if errorlevel 1 (
    echo Error: Failed to copy truststore to %CLIENT_DIR%
    pause
    exit /b 1
)


REM Cleanup Kafka temporary files
del "%CLIENT_CSR_FILE%"
del "%CA_SERIAL_FILE%"
del %KAFKA_DIR%\*.pem
del %CLIENT_DIR%\*.pem

for %%b in (%KAFKA_CONTROLLERS%) do (
    del "%KAFKA_DIR%\%%b.csr"
)

REM Define the Nginx certificate details and filenames
set NGINX_CA_SUBJECT="/C=IN/O=ASTERIX/CN=nginx-ca"
set NGINX_SERVER_SUBJECT="/C=IN/O=ASTERIX/CN=nginx-server"
set NGINX_CLIENT_SUBJECT="/C=IN/O=ASTERIX/CN=nginx-client"
set NGINX_DIR=nginx-mtls
set OPENSSL_CONF_NGINX=nginx-san.cnf

REM Check if Nginx OpenSSL configuration file exists
if not exist "%OPENSSL_CONF_NGINX%" (
    echo Error: Configuration file %OPENSSL_CONF_NGINX% not found.
    pause
    exit /b 1
)

REM Define filenames for Nginx keys and certificates
set NGINX_CA_KEY_FILE=%NGINX_DIR%\nginx-ca-key.pem
set NGINX_CA_CERT_FILE=%NGINX_DIR%\nginx-ca-cert.pem
set NGINX_SERVER_KEY_FILE=%NGINX_DIR%\nginx-server-key.pem
set NGINX_SERVER_CSR_FILE=%NGINX_DIR%\nginx-server.csr
set NGINX_SERVER_CERT_FILE=%NGINX_DIR%\nginx-server-cert.pem
set NGINX_CA_SERIAL_FILE=%NGINX_DIR%\nginx-ca-cert.srl

REM Define filenames for Nginx client keys and certificates
set NGINX_CLIENT_KEY_FILE=%NGINX_DIR%\nginx-client-key.pem
set NGINX_CLIENT_CSR_FILE=%NGINX_DIR%\nginx-client.csr
set NGINX_CLIENT_CERT_FILE=%NGINX_DIR%\nginx-client-cert.pem

REM Create Nginx directories if they do not exist
if not exist "%NGINX_DIR%" mkdir "%NGINX_DIR%"

REM Remove existing Nginx files if they exist
if exist "%NGINX_CA_KEY_FILE%" del "%NGINX_CA_KEY_FILE%"
if exist "%NGINX_CA_CERT_FILE%" del "%NGINX_CA_CERT_FILE%"
if exist "%NGINX_SERVER_KEY_FILE%" del "%NGINX_SERVER_KEY_FILE%"
if exist "%NGINX_SERVER_CSR_FILE%" del "%NGINX_SERVER_CSR_FILE%"
if exist "%NGINX_SERVER_CERT_FILE%" del "%NGINX_SERVER_CERT_FILE%"
if exist "%NGINX_CA_SERIAL_FILE%" del "%NGINX_CA_SERIAL_FILE%"

REM Remove existing Nginx client files if they exist
if exist "%NGINX_CLIENT_KEY_FILE%" del "%NGINX_CLIENT_KEY_FILE%"
if exist "%NGINX_CLIENT_CSR_FILE%" del "%NGINX_CLIENT_CSR_FILE%"
if exist "%NGINX_CLIENT_CERT_FILE%" del "%NGINX_CLIENT_CERT_FILE%"

REM Generate Nginx CA private key and certificate with CA:TRUE
openssl ecparam -genkey -name secp384r1 -out "%NGINX_CA_KEY_FILE%"
if not exist "%NGINX_CA_KEY_FILE%" (
    echo Error: Failed to generate Nginx CA key file %NGINX_CA_KEY_FILE%
    pause
    exit /b 1
)

openssl req -x509 -new -nodes -key "%NGINX_CA_KEY_FILE%" -sha512 -days 1825 -out "%NGINX_CA_CERT_FILE%" -subj "%NGINX_CA_SUBJECT%" -config "%OPENSSL_CONF_NGINX%" -extensions v3_ca
if not exist "%NGINX_CA_CERT_FILE%" (
    echo Error: Failed to generate Nginx CA certificate %NGINX_CA_CERT_FILE%
    pause
    exit /b 1
)

REM Generate Nginx server private key
openssl ecparam -genkey -name secp384r1 -out "%NGINX_SERVER_KEY_FILE%"
if not exist "%NGINX_SERVER_KEY_FILE%" (
    echo Error: Failed to generate Nginx server key file %NGINX_SERVER_KEY_FILE%
    pause
    exit /b 1
)

REM Generate Nginx server certificate signing request (CSR) with SANs
openssl req -new -key "%NGINX_SERVER_KEY_FILE%" -out "%NGINX_SERVER_CSR_FILE%" -subj "%NGINX_SERVER_SUBJECT%" -config "%OPENSSL_CONF_NGINX%"
if not exist "%NGINX_SERVER_CSR_FILE%" (
    echo Error: Failed to generate Nginx server CSR %NGINX_SERVER_CSR_FILE%
    pause
    exit /b 1
)

REM Generate Nginx server certificate signed by the Nginx CA including SANs (no CA:TRUE)
openssl x509 -req -in "%NGINX_SERVER_CSR_FILE%" -CA "%NGINX_CA_CERT_FILE%" -CAkey "%NGINX_CA_KEY_FILE%" -CAcreateserial -out "%NGINX_SERVER_CERT_FILE%" -days 365 -sha512 -extfile "%OPENSSL_CONF_NGINX%" -extensions req_ext
if not exist "%NGINX_SERVER_CERT_FILE%" (
    echo Error: Failed to generate Nginx server certificate %NGINX_SERVER_CERT_FILE%
    pause
    exit /b 1
)

REM Generate Nginx client private key
openssl ecparam -genkey -name secp384r1 -out "%NGINX_CLIENT_KEY_FILE%"
if not exist "%NGINX_CLIENT_KEY_FILE%" (
    echo Error: Failed to generate Nginx client key file %NGINX_CLIENT_KEY_FILE%
    pause
    exit /b 1
)

REM Generate Nginx client certificate signing request (CSR) with SANs
openssl req -new -key "%NGINX_CLIENT_KEY_FILE%" -out "%NGINX_CLIENT_CSR_FILE%" -subj "%NGINX_CLIENT_SUBJECT%" -config "%OPENSSL_CONF_NGINX%"
if not exist "%NGINX_CLIENT_CSR_FILE%" (
    echo Error: Failed to generate Nginx client CSR %NGINX_CLIENT_CSR_FILE%
    pause
    exit /b 1
)

REM Generate Nginx client certificate signed by the Nginx CA including SANs (no CA:TRUE)
openssl x509 -req -in "%NGINX_CLIENT_CSR_FILE%" -CA "%NGINX_CA_CERT_FILE%" -CAkey "%NGINX_CA_KEY_FILE%" -CAcreateserial -out "%NGINX_CLIENT_CERT_FILE%" -days 365 -sha512 -extfile "%OPENSSL_CONF_NGINX%" -extensions req_ext
if not exist "%NGINX_CLIENT_CERT_FILE%" (
    echo Error: Failed to generate Nginx client certificate %NGINX_CLIENT_CERT_FILE%
    pause
    exit /b 1
)

REM Cleanup Nginx temporary files
del "%NGINX_SERVER_CSR_FILE%"
del "%NGINX_CA_SERIAL_FILE%"
del "%NGINX_CLIENT_CSR_FILE%"

echo Kafka and Nginx PEM files and truststores have been generated successfully.
pause
