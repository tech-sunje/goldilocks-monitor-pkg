# 에이전트 매뉴얼 안내 토픽

`agent-manual.js`는 공식 GOLDILOCKS 26c.1 매뉴얼에서 확인한 제한된 토픽을 검색하는 순수 모듈이다. 외부 AI·형태소 분석기·DB 연결·SQL 실행 의존성이 없다. 초기 버전은 삭제·초기화·종료 문법을 제공하지 않는다.

근거 버전은 `sunjesoft/goldilocks-manuals`의 `f5976dfdb7296116f2aa988746c3e375993b4825`다. 각 토픽 `sources`에 파일과 행 범위를 고정한 링크가 있다. 현재 DB 상태와 권한을 실제 확인했다는 뜻은 아니며 SQL 콘솔의 사용자가 별도로 인증하고 검토·실행해야 한다.

| ID | 안내 범위 | 중요한 구분 |
|---|---|---|
| `member-add` | 기존 그룹에 멤버 추가 | `ALTER CLUSTER GROUP ... ADD CLUSTER MEMBER`; HOST/PORT는 DB 생성 당시 클러스터 통신 주소다. SQL 리스너 포트로 추정하지 않는다. |
| `group-create` | 새 클러스터 그룹 생성 | `CREATE CLUSTER GROUP`; 최초 그룹의 자기 자신 한 개 조건과 기존 그룹 멤버 추가를 구분한다. |
| `member-startup` | LOCAL OPEN까지 구동 | 현 단계를 먼저 확인한다. `executeSql`은 단계 조회 SELECT만 제공하며 MOUNT/OPEN을 무조건 실행하지 않는다. |
| `member-join` | 기존 비활성 멤버 재참여 | 이미 LOCAL OPEN인 기존 멤버에 대한 JOIN이며 신규 등록이나 OS 프로세스 기동과 다르다. |
| `table-create` | 테이블 정의 | CLONED AT CLUSTER WIDE는 클러스터 배치 예시다. 모든 환경에 적합한 배치로 단정하지 않는다. |
| `index-create` | 일반 인덱스 생성 | 열·유일성·순서·저장소를 부하와 데이터 규칙에 맞게 정해야 한다. |
| `sequence-create` | 시퀀스 생성 | 시퀀스 생성과 테이블 열의 기본값 연결은 별개다. |
| `privilege-grant` | 테이블 SELECT 권한 부여 | 사용자 생성·로그인 권한·WITH GRANT OPTION은 포함하지 않는다. |

구동·JOIN의 SQL 매뉴얼은 `ADMINISTRATION ON DATABASE` 권한을 요구한다. 기존 모니터의 관리 작업 경로는 추가로 SYSDBA 연결을 검사한다. 두 기준을 같은 것으로 설명하지 않는다.

## API

```javascript
AgentManual.search(text)
// { answer: topic | null,
//   candidates: [{id, title, titleKo, score}],
//   ambiguous: boolean }

AgentManual.get(id)
// topic | null; 내부 카탈로그를 변경하지 않는 복사본
```

토픽은 `id`, `title/titleKo`, `summary/summaryKo`, `steps/stepsKo`, `syntax`, `example`, `executeSql`, `notes/notesKo`, `sources`를 제공한다. `syntax`와 `executeSql`에는 `<GROUP_NAME>`, `<NEW_MEMBER>`, `<HOST>`, `<PORT>` 등 사용자가 바꿔야 하는 자리표시자를 유지한다. 예시 주소 `192.0.2.x`와 `example_*` 이름은 설명용이며 실제 수집 설정에서 유추한 값이 아니다.

`executeSql`은 호환을 위한 데이터 필드 이름이다. 이 모듈은 해당 SQL을 보내거나 실행하지 않는다. 통합 UI는 문장을 SQL 콘솔 **편집기에만** 복사하고, 연결과 실행은 사용자의 별도 동작으로 유지해야 한다.

검색은 질문 길이를 500자로 제한하고 영·한 별칭 정규화, 명시적 대상/동작 특징, 문자 bigram 유사도를 결합한다. 점수는 검색 정렬값이며 통계적으로 검증된 정확도 확률이 아니다. 근접 후보가 있거나 신뢰가 부족하면 최대 세 후보를 반환하고 자동 답변을 선택하지 않는다.

- `cluster member추가`, `cluster멤버 추가`, `클러스터 member 추가`, `멤버 추가`를 같은 토픽으로 처리한다.
- `새그룹만들려면`은 새 그룹 생성과 연결한다.
- 대상이 없는 `추가방법`은 멤버 추가와 그룹 생성 후보를 제시한다.
- 현재 상태·느린 SQL·실행계획 요청은 매뉴얼 답변으로 보내지 않는다.

한글 표시 문구와 입력 별칭은 제품 소스 언어 정책에 맞춰 영문/한글 쌍 및 Unicode escape로 저장한다. 동적인 관측 데이터나 SQL 원문을 번역 대상으로 재작성하지 않는다.

검증:

```sh
node test/agent-manual-test.js
node test/ui-language-test.js
```
