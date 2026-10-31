# 26번 서버: 내부 CA 기반 HTTPS 운영 가이드

기본 전송은 HTTP이며 `monitor.scheme=https`를 지정하면 별도 웹 서버 없이 직접 HTTPS를 제공합니다. 인증서는 운영자가 외부 경로로 준비합니다. 앱은 인증서 발급·CA 신뢰 설치·방화벽 변경을 자동 수행하지 않습니다. 실제 접속 주소와 운영체제 정책은 운영자가 확인합니다.

## 선택 구성: 별도 웹 서버 없이 직접 HTTPS

브라우저 → `https://<실제 접속 주소>:19443` → Java `HttpsServer` 모니터.

Nginx는 필요하지 않습니다. 기본 `monitor.scheme=http`를 유지하면 종전 HTTP 경로입니다. HTTPS는 서버 인증서 PEM과 암호화하지 않은 RSA/EC PKCS#8 PEM 개인키를 읽습니다. 선택한 HTTPS 인증서·키·체인의 누락, 만료, 형식 오류, 불일치는 시작 실패로 처리하며 HTTP로 자동 우회하지 않습니다. 암호화하지 않은 서버 PEM 키라면 비밀번호를 묻지 않습니다. 보호된 PKCS#12 저장소도 선택할 수 있으며 기본은 시작 시 가려진 비밀번호 입력입니다. 비밀번호를 모르는 기존 `.p12` 파일을 추측하거나 변환할 필요는 없으며, 이미 가진 정상 PEM 경로를 사용할 수 있습니다.

TLS 1.2 이상만 활성화합니다. TLS 1.3은 Java 런타임이 지원하는 경우 사용합니다. 클라이언트는 접속 주소와 일치하는 SAN 인증서 및 발급 CA 신뢰가 필요합니다. 포트는 1024~65535 범위에서 설정합니다. 하나의 프로세스가 선택한 HTTP 또는 HTTPS 한 종류의 포트만 제공하며 자동 리다이렉트·HSTS·실행 중 인증서 재로딩은 제공하지 않습니다.

CA는 조직의 기존 내부 PKI가 있으면 그것을 사용합니다. 없으면 아래 소규모 수동 CA 예시를 사용할 수 있습니다. **CA 개인키는 모니터 서버에 상시 두지 않고 별도 관리 장비/오프라인 저장소에서 보관합니다.** 모니터에는 서버 인증서·서버 개인키·필요한 공개 체인만 둡니다.

## 1. 접속 주소와 발급 요청 준비 (26번 서버)

운영자가 실제 브라우저 접속 IP를 확인한다. 예시는 환경 변수를 수동 지정하며 실제 IP를 추정하지 않는다.

```sh
# 반드시 실제 전체 IP로 수정. 예시 주소를 그대로 운영에 사용하지 않는다.
MONITOR_IP='192.0.2.26'
umask 077
mkdir -p "$HOME/monitor-tls-request"
cd "$HOME/monitor-tls-request"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out monitor.key
openssl req -new -sha256 -key monitor.key -out monitor.csr \
  -subj "/CN=$MONITOR_IP"
cat > monitor.ext <<EXT
[server_cert]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = IP:$MONITOR_IP
EXT
```

CN만으로는 IP 검증을 대신하지 않는다. 접속 IP는 `subjectAltName`의 **IP 형식**에 넣는다. 여러 IP로 접속해야 하면 `IP:주소1,IP:주소2`로 발급하고, IP 변경 시 재발급한다. CSR와 확장 설정만 CA 관리자에게 전달하고 `monitor.key`는 26번 서버 밖으로 보내지 않는다.

## 2. 내부 CA 생성과 서명 (별도 CA 관리 장비)

조직 CA가 이미 있다면 루트를 새로 만들지 않고 CSR를 해당 관리자에게 제출한다. 아래는 별도 CA가 없는 소규모 환경의 초기 발급 예시다. 매번 루트를 재생성하지 않는다.

```sh
umask 077
mkdir -p "$HOME/monitor-internal-ca"
cd "$HOME/monitor-internal-ca"
# 비밀번호는 프롬프트로 입력. 명령행/저장소에 기록하지 않는다.
openssl genpkey -algorithm RSA -aes-256-cbc \
  -pkeyopt rsa_keygen_bits:4096 -out root-ca.key
openssl req -x509 -new -sha256 -days 3650 -key root-ca.key \
  -out root-ca.crt -subj '/CN=Monitor Internal Root CA' \
  -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -addext 'subjectKeyIdentifier=hash'
# 전달받은 monitor.csr와 monitor.ext를 이 작업 디렉터리에 둔다.
openssl req -in monitor.csr -verify -noout
openssl x509 -req -sha256 -days 365 -in monitor.csr \
  -CA root-ca.crt -CAkey root-ca.key -CAcreateserial \
  -extfile monitor.ext -extensions server_cert -out monitor.crt
openssl verify -CAfile root-ca.crt -purpose sslserver monitor.crt
openssl x509 -in monitor.crt -noout -dates -serial -ext subjectAltName
openssl x509 -in root-ca.crt -noout -fingerprint -sha256
```

OpenSSL 버전에 따라 `-addext` 지원을 확인한다(현재 조사 환경 OpenSSL 3.5.7). CA 관리자는 SAN·기간·요청자를 검토하고 발급 기록(CSR, 인증서, serial, 요청자, IP, 만료일)을 보관한다. `.srl`을 포함한 상태와 암호화된 CA 키를 안전하게 백업하며 동시 서명은 직렬화한다. 이 수동 예시는 발급 DB/CRL/자동 갱신 시스템을 제공하지 않는다. 다수 서버나 폐기·자동 갱신이 필요해지면 조직 PKI로 운영한다. 유효기간 365/3650일은 제안값이지 강제 규칙이 아니다.

26번 서버에 `monitor.crt`를 돌려주고, 사용자 PC에는 공개 인증서 `root-ca.crt`와 별도 경로로 확인할 SHA-256 지문만 배포한다. CA 개인키를 배포하지 않는다.

## 3. 서버 PEM 파일과 INI 설정

인증서의 첫 항목은 서버 leaf 인증서여야 합니다. 중간 CA가 있다면 leaf 뒤에 이어 붙이거나 `chain_file`에 발급 순서대로 둡니다. 루트 CA 공개 인증서는 클라이언트 신뢰 저장소에 설치하며 서버 체인에 포함해도 됩니다. 모든 제공 인증서의 유효기간과 체인 서명을 시작 시 검사합니다.

```ini
[monitor]
scheme = https
bind = 0.0.0.0
port = 19443

[tls]
certificate_file = ~/.config/goldilocks-monitor/tls/monitor.crt
private_key_file = ~/.config/goldilocks-monitor/tls/monitor.key
# Optional issuing/intermediate CA PEM chain; leave empty when unnecessary.
chain_file =
```

경로는 절대 경로, INI 파일 디렉터리 기준 상대 경로, 현재 실행 계정의 `~/`를 지원합니다. 환경변수·`~다른사용자`를 자동 확장하지 않습니다. 인증서 파일은 최대 1MiB/16개, 개인키는 최대 256KiB로 제한합니다. 앱 계정 전용 TLS 디렉터리는 권한 700, 암호화하지 않은 PEM 개인키 파일은 소유자 전용 권한(예: 600 또는 400)이 필수입니다. 그룹/다른 사용자 권한이 있으면 시작을 거부합니다. POSIX 권한 검사가 지원되지 않는 파일시스템에서는 보호된 PKCS#12 방식을 사용합니다. 소스 저장소·배포 압축·공유 다운로드 경로에 개인키를 넣지 않습니다.

개인키는 `BEGIN PRIVATE KEY` 형식의 암호화하지 않은 PKCS#8 PEM이어야 합니다. `BEGIN RSA PRIVATE KEY`(PKCS#1), `BEGIN EC PRIVATE KEY`(SEC1), 암호화된 PEM은 그대로 읽지 않습니다. 필요한 경우 운영자가 별도 출력 파일로 변환합니다. 기존 파일을 덮어쓰지 않습니다.

```sh
umask 077
openssl pkcs8 -topk8 -nocrypt -in original-server.key -out monitor-pkcs8.key
chmod 600 monitor-pkcs8.key
sh run.sh /private/path/monitor-https.ini
```

이 명령은 **서버 개인키**를 변환하는 예시이며 CA 개인키를 읽거나 복사할 필요가 없습니다. 암호 입력이 필요한 기존 키는 OpenSSL 프롬프트로 입력합니다. 비밀번호를 URL·명령행 인자·공개 INI에 넣지 않습니다.

1. 기존 INI를 백업하고 외부 PEM 경로·접속 포트·bind를 지정합니다.
2. 모니터 프로세스를 재시작합니다. PEM이 바뀌어도 재시작 전까지 기존 메모리의 인증서를 사용합니다.
3. 승인한 내부 사용자/VPN 망에서 필요한 HTTPS 포트만 허용할지는 운영 정책에 따라 정합니다. 앱은 방화벽을 바꾸지 않습니다.
4. HTTP로 복구하려면 운영자가 `monitor.scheme=http`를 명시하고 재시작합니다. HTTPS 오류 때문에 앱이 자동으로 HTTP를 열지는 않습니다.

### 보호된 PKCS#12와 시작 시 비밀번호

PEM 경로 대신 아래처럼 구성합니다. PEM 인증서·개인키·체인 필드는 비워야 합니다.

```ini
[monitor]
scheme = https
port = 19443

[tls]
keystore_file = ~/.config/goldilocks-monitor/tls/monitor.p12
password_source = prompt
# Optional when exactly one private-key entry exists.
key_alias =
```

`prompt`는 `Console.readPassword`를 사용하므로 입력한 비밀번호가 터미널에 표시되지 않습니다. 기본 입력을 표준입력의 평문 에코 방식으로 우회하지 않습니다. 콘솔이 없는 서비스/백그라운드에서는 아래 둘 중 하나를 명시합니다.

- `password_source=file`: `password_file`에 별도 파일을 지정합니다. POSIX 소유자 전용 권한(예: 600), 일반 파일, 최대 1024바이트를 확인합니다. 마지막 한 줄바꿈(CRLF 가능)만 제거하며 앞뒤 공백은 비밀번호의 일부입니다. 권한 검사를 지원하지 않는 파일시스템에서는 prompt/env 방식을 사용합니다.
- `password_source=env`: `password_env`에는 값이 아닌 환경변수 이름을 지정합니다. 비워 두면 `MONITOR_TLS_PASSWORD`를 사용합니다. 환경은 프로세스 계정/운영 관리자에게 노출될 수 있으므로 보호 정책에 맞게 전달합니다.

비밀번호는 1~1024자이며 중간 줄바꿈·NUL은 거부합니다. file/env/prompt 설정이 서로 충돌하면 시작을 거부합니다. 비밀번호 값을 공개 INI, 명령행 인자, 로그에 넣지 않습니다. 비밀번호 배열은 로딩 후 지웁니다. 저장소는 최대 4MiB, 선택한 인증서 체인은 최대 16개입니다. 개인키 항목이 여러 개면 `key_alias`가 필요합니다. 인증서 기간·체인·키 일치 검사는 PEM과 동일하게 적용합니다.

새 저장소를 운영자가 만들 때는 OpenSSL 비밀번호 프롬프트를 사용합니다. 이미 존재하는 서버 키나 저장소를 덮어쓰지 않습니다.

```sh
umask 077
openssl pkcs12 -export -name monitor -inkey monitor.key \
  -in monitor.crt -certfile root-ca.crt -out new-monitor.p12
chmod 600 new-monitor.p12
```

OpenSSL과 구형 Java8의 PKCS#12 암호화/MAC 호환성은 실제 실행할 Java 버전에서 검증합니다. 호환되지 않으면 업데이트된 Java8을 사용하거나 검증한 저장소 생성 설정을 선택합니다. 암호화된 PKCS#8 PEM 자체의 비밀번호 입력은 지원하지 않으며 보호된 PKCS#12를 사용합니다. HTTP 모드에서는 위 TLS 경로·비밀번호 옵션을 읽거나 입력받지 않습니다.

## 4. 사용자 PC의 신뢰 설정

인증서를 신뢰해야 하는 쪽은 **접속하는 PC/브라우저**다. 서버에만 루트를 설치해도 사용자 PC 경고는 없어지지 않는다. 공개 루트의 SHA-256 지문을 별도 경로로 검증한 뒤 등록한다.

- Windows: 해당 사용자 또는 조직 정책으로 `신뢰할 수 있는 루트 인증 기관`에 `root-ca.crt` 등록. 전사 배포는 관리자 그룹 정책 등 기존 관리 체계를 사용한다.
- RHEL/CentOS 클라이언트: 관리자가 `/etc/pki/ca-trust/source/anchors/`에 루트를 두고 `update-ca-trust extract` 실행.
- Firefox 등 별도 인증서 저장소를 사용하는 브라우저는 조직 정책/인증기관 가져오기 설정도 확인한다.

루트 인증서를 설치하면 그 CA가 서명한 서버를 신뢰한다. 승인한 관리 PC에만 배포한다. 브라우저의 경고 무시를 정상 운영 절차로 삼지 않는다.

## 5. 전환 검증 및 복구

전환 전 기존 INI를 백업한다. 직접 HTTPS는 실제 접속할 인터페이스에 bind한다. HTTPS와 HTTP는 서로 다른 브라우저 origin이므로 저장된 레이아웃·언어 등이 자동 승계된다고 가정하지 말고 확인한다. 에이전트와 콘솔은 HTTPS 메인에서 새로 연다.

```sh
MONITOR_IP='192.0.2.26' # 실제 접속 IP로 변경
openssl verify -CAfile root-ca.crt -verify_ip "$MONITOR_IP" monitor.crt
curl --cacert root-ca.crt "https://$MONITOR_IP:19443/api/state"
openssl s_client -connect "$MONITOR_IP:19443" -verify_ip "$MONITOR_IP" \
  -verify_return_error -CAfile root-ca.crt </dev/null
```

`curl -k`로 성공했다고 신뢰 검증 완료로 보지 않는다. 최초 화면, 자동 갱신, 과거 이력, 에이전트/상세 팝업, SQL 콘솔 인증, PLAN ONLY, 작업 등록/취소, 가져오기/내보내기를 각각 테스트한다. 원치 않는 원격 HTTP 19090 접속은 차단되는지 확인한다. 실패하면 검증한 백업 구성으로 복구하되 HTTPS 오류를 HTTP로 자동 우회시키지는 않는다. 실제 26번 서버의 TLS 접속 검증은 아직 수행하지 않았다.

## 6. 갱신·운영

- 서버 인증서 만료 30일 전부터 정기 확인: `openssl x509 -in monitor.crt -checkend 2592000 -noout`의 실패를 알림으로 처리한다. CA 만료도 별도로 관리한다.
- 새 키/CSR를 생성하고 같은 CA로 재발급한다. 새 SAN·만료일·키 일치·체인과 실제 Java 런타임의 PEM 로딩을 검증한 뒤 서버 PEM 파일을 교체하고 모니터를 재시작한다. 진행 중 감시 작업은 재시작 중단으로 표시되므로 갱신 시점을 조정한다.
- 기존 CA로 갱신하면 PC의 루트 재설치는 보통 필요 없다. 루트 교체 시 새 루트를 PC에 먼저 배포하고 유예 기간을 둔다.
- 서버 키 유출 시 키/인증서 재발급 및 기존 인증서 폐기 정책을 적용한다. 루트 키 유출 시 해당 루트 신뢰 제거·새 루트 배포와 전체 재발급이 필요하다. 수동 CA의 CRL/OCSP 자동 배포는 위 예시에 포함되지 않는다.
- HTTPS는 전송 암호화와 서버 식별 기능이다. 모니터의 접근 통제·DB 권한·관리 포트 제한은 별도로 유지한다.

## 근거

- [Java8 HttpsServer](https://docs.oracle.com/javase/8/docs/jre/api/net/httpserver/spec/com/sun/net/httpserver/HttpsServer.html)
- [OpenSSL SAN의 IP 형식](https://docs.openssl.org/1.1.1/man5/x509v3_config/)
- [OpenSSL IP 검증 옵션](https://github.com/openssl/openssl/blob/master/doc/man1/openssl-verification-options.pod)
- [Red Hat 시스템 CA 신뢰 저장소](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/sec-shared-system-certificates)
