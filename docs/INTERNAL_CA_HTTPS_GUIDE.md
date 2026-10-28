# 26번 서버: 내부 CA 기반 HTTPS 운영 가이드

현재 상태: HTTP `19090` 포트로 운영한다. 아래는 **향후 전환 절차**이며 이번 작업에서 인증서 발급, 방화벽·서비스·실행 설정 변경을 수행하지 않았다. 현재 조사 환경은 CentOS Linux 8이다. 26번 서버의 실제 접속 IP, root 권한, 방화벽/SELinux 정책과 패키지 저장소는 전환 전에 확인한다. `26`만으로 인증서 IP를 정하지 않는다.

## 권장 구성: 별도 웹 서버 없이 직접 HTTPS

브라우저 → `https://<26번 서버 접속 IP>:19443` → 모니터 Java 프로세스.

Nginx는 필요하지 않다. 기존 Java `HttpServer`를 HTTPS 모드에서 `HttpsServer`와 `SSLContext`로 구성하고 PKCS#12 키 저장소를 읽도록 **다음 작업에서 앱을 수정해야 한다**. 현재 Main.java는 HttpServer만 생성하므로 인증서 파일만 두어도 HTTPS가 켜지는 것은 아니다. HTTP 운영은 기존 경로를 유지한다. HTTPS 모드를 선택하면 인증서 오류 시 시작 실패를 표시하고 HTTP로 자동 우회하지 않는 것이 권장 정책이다.

현재 앱 포트 범위는 1024~65535이므로 관리자 권한이 필요 없는 19443을 제안한다. 정확한 HTTPS 설정 키/비밀번호 전달 방법은 다음 구현에서 확정한다. 이 문서에 아직 없는 INI 옵션을 설정해도 동작하지 않는다. 전환 시 외부 HTTP 19090은 닫고 HTTPS 포트만 허용하는 편이 좋다. HTTP/HTTPS 동시 제공이 필요하면 별도 요구사항으로 정한다.

CA는 조직의 기존 내부 PKI가 있으면 그것을 사용한다. 없으면 아래 소규모 수동 CA로 시작할 수 있다. CA는 상시 서버 프로세스가 필요하지 않다. **CA 개인키는 웹 서버에 상시 두지 않고 별도 관리 장비/오프라인 저장소에서 보관한다.** 26번 서버에는 서버 키 저장소만 설치한다.

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

## 3. 26번 서버의 Java용 키 저장소 준비

서버 개인키와 CA가 발급한 인증서를 PKCS#12로 묶는다. 비밀번호는 프롬프트로 입력한다. 중간 CA가 있다면 `-certfile`에는 체인을 담은 파일을 사용한다.

```sh
umask 077
openssl pkcs12 -export -name monitor \
  -inkey monitor.key -in monitor.crt -certfile root-ca.crt \
  -out monitor.p12
# 실제 모니터에 사용하는 JRE8의 keytool로 읽을 수 있는지 확인한다.
/usr/lib/jvm/jre-1.8.0-openjdk/bin/keytool -list -v \
  -storetype PKCS12 -keystore monitor.p12
```

`PrivateKeyEntry`, SAN IP, 만료일, 인증서 체인을 확인한다. OpenSSL3 기본 PKCS#12 알고리즘과 오래된 JRE8의 호환성은 실제 설치 버전으로 확인한다. 실패하면 지원되는 JRE8 업데이트/호환 생성 옵션을 검토하고 검증된 조합을 사용한다.

앱 실행 계정 전용 경로(예: `$HOME/.config/goldilocks-monitor/tls/`)를 권한 700으로 만들고 키 저장소를 600으로 설치한다. 소스 저장소, `dist`, 공유 다운로드 디렉터리에는 넣지 않는다. CA 개인키는 이 서버로 복사하지 않는다. PKCS#12 비밀번호는 다음 HTTPS 구현에서 비공개 파일/환경 전달 등 운영 방식을 확정하며 URL, 명령행 인자, 로그, 공개 INI에 평문으로 넣지 않는다.

HTTPS 기능 구현 후 수행할 절차:

1. HTTP 실행 설정을 백업한다.
2. 앱에 HTTPS 모드, 접속 포트 19443, PKCS#12 경로와 비밀번호 공급 경로를 설정한다(정확한 키는 구현 시 문서화).
3. 프로세스를 재시작하고 인증서 로딩 실패/만료/키 불일치가 명확히 보고되는지 확인한다.
4. 승인한 내부 사용자/VPN 망에서만 TCP19443을 허용한다. 검증 완료 후 기존 원격 HTTP19090을 닫는다.
5. HTTPS 인증서 교체 시 앱 재시작이 필요하다고 가정한다. 무중단 인증서 재로딩은 현재 구현되지 않았다.

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
- 새 키/CSR를 생성하고 같은 CA로 재발급한다. 새 SAN·만료일·키 일치·체인과 JRE8 키 저장소 로딩을 검증한 뒤 PKCS#12를 교체하고 모니터를 재시작한다. 진행 중 감시 작업은 재시작 중단으로 표시되므로 갱신 시점을 조정한다.
- 기존 CA로 갱신하면 PC의 루트 재설치는 보통 필요 없다. 루트 교체 시 새 루트를 PC에 먼저 배포하고 유예 기간을 둔다.
- 서버 키 유출 시 키/인증서 재발급 및 기존 인증서 폐기 정책을 적용한다. 루트 키 유출 시 해당 루트 신뢰 제거·새 루트 배포와 전체 재발급이 필요하다. 수동 CA의 CRL/OCSP 자동 배포는 위 예시에 포함되지 않는다.
- HTTPS는 전송 암호화와 서버 식별 기능이다. 모니터의 접근 통제·DB 권한·관리 포트 제한은 별도로 유지한다.

## 근거

- [Java8 HttpsServer](https://docs.oracle.com/javase/8/docs/jre/api/net/httpserver/spec/com/sun/net/httpserver/HttpsServer.html)
- [OpenSSL SAN의 IP 형식](https://docs.openssl.org/1.1.1/man5/x509v3_config/)
- [OpenSSL IP 검증 옵션](https://github.com/openssl/openssl/blob/master/doc/man1/openssl-verification-options.pod)
- [Red Hat 시스템 CA 신뢰 저장소](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/sec-shared-system-certificates)
