# Local monitor accounts

The web login uses local monitor accounts and continues working when the database is down. SQL console and administration still require their separate database authentication. HTTP is the default transport; configure HTTPS before sending passwords across an untrusted network.

Configuration keys (paths are relative to the selected INI file):

```ini
[web_auth]
enabled=true
users_file=runtime/security/web-users.properties
initial_password_file=runtime/security/initial-password.txt
initial_user=admin
session_minutes=60
body_timeout_seconds=5
allowed_hosts=localhost,127.0.0.1,::1
```

Set `allowed_hosts` to the actual DNS names and IP addresses used to reach this installation. Comma separated entries accept host names, IP literals and optional ports; host matching ignores the port. The default additionally includes a specific configured bind address, but never wildcard binds. An unknown Host header is rejected to prevent DNS rebinding. Forwarding headers do not establish trust. Authentication can be disabled only with a loopback bind; public binds reject that configuration at startup.

On first startup, the monitor generates the initial administrator password. You can instead precreate `initial_password_file`: it must be a regular nonsymlink file with owner-only permissions (0600 or 0400 on POSIX, owner-only ACL on Windows), containing one valid UTF-8 password line of 1–256 characters, without NUL. This temporary bootstrap password may be shorter than the permanent password minimum; it must be replaced with a password of at least 12 characters before monitoring APIs become accessible. A final LF or CRLF is allowed. The monitor uses this password without overwriting the file, rejects insecure or invalid files, and still requires a password change at first login. It writes that password only to `initial_password_file`, with owner-only permissions. The account store contains a salted PBKDF2-HMAC-SHA256 hash (600,000 iterations). The security directory is private, enforced with POSIX permissions or an owner-only Windows ACL. Filesystems without either capability fail closed. Read the temporary password locally and sign in at `/login.html`; the first session must change it before monitoring data becomes accessible. Successful administrator password rotation removes the temporary password file. No account or initial password belongs in a source repository or public distribution.

Create or reset a local account from an interactive terminal:

```sh
./web-access-setup.sh /path/to/monitor.ini admin admin
./web-access-setup.sh /path/to/monitor.ini reader viewer
```

Build the application first. The command prompts twice using the terminal password reader; passwords are never command arguments. Restart the monitor after offline changes. Keep at least one administrator. The tool operates on the selected INI and supports the same configurable store paths.

Administrators can use the monitor's existing functions. Viewers can read monitoring/history through GET requests; every mutation and every console/profile POST is denied. This is a coarse read-only role, not per-object authorization. The administrator role does not bypass database authentication.

Sessions expire after the configured absolute lifetime and are kept only in memory (maximum 64). Restarting ends all sessions. Password changes revoke that user's sessions. Sign out revokes all of that user's sessions. Cookies use HttpOnly and SameSite=Strict, plus Secure on actual HTTPS connections. Web session expiry redirects to login; an expired database-console session remains a separate error and does not redirect the whole monitor. The account link opens password change and the Sign out button closes sessions.

Login and password operations accept at most 4096 bytes, at most two simultaneous requests, and a configurable 1–30 second body deadline (default 5 seconds) and are throttled before password hashing (5 attempts per source address and 20 globally per minute). Reverse proxies share an address for this purpose. Strong passwords should contain 12–256 characters. No public sign-up, password email, SSO, or database-dependent login is provided. Local filesystem access to the account store grants control over local monitor identity, so protect it alongside other runtime configuration.

The launcher configures the JDK HTTP server to skip draining rejected request bodies (`sun.net.httpserver.drainAmount=0`) before server initialization. This prevents incomplete rejected uploads from occupying request workers; completely consumed normal requests retain normal connection reuse. Embedded integrations must call `WebAccess.prepareServer()` before creating an HTTP server.

초기 암호 변경 화면의 **다음에 하기**를 선택하면 현재 로그인 세션에서 변경을 미루고 모니터로 이동할 수 있습니다. 초기 암호 변경 여부는 저장된 계정에 그대로 남으므로 다음 로그인 시 다시 안내합니다. 기존 로그인·만료·admin/viewer 권한 검사는 유지합니다.

로그인 페이지를 새로고침(F5)하면 세션 상태에 관계없이 로그인 입력 화면부터 표시합니다. 기존 세션을 자동 로그아웃시키지는 않으며, 암호 변경 화면은 로그인 제출 결과에 따라 열립니다.
