# BCMD 6주차 — 스마트컨트랙트 보안 실습 (로컬 샌드박스)

테스트넷·MetaMask·faucet 없이 **Foundry 로컬 환경**에서 Ethernaut 취약점을
"익스플로잇 성공 테스트"로 증명한다. (Lv1 Fallback / Lv10 Re-entrancy)

## 실행법

```bash
# Foundry 설치 (한 번)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 빌드 & 테스트
forge build
forge test -vvv
```

기대 결과: **4 tests passed, 0 failed** (Fallback 1 · Reentrancy 1 · AuditMe 2).
`testDrain`은 공격자 0.1 ether로 컨트랙트 5.1 ether 전액을 탈취하는 로그를 출력한다.

## 파일 구조

```
src/
  Fallback.sol            # Lv1 재현 — receive() 옆문으로 owner 탈취 (// VULN / // FIX 표기)
  Reentrancy.sol          # Lv10 재현 — call 먼저 / 차감 나중 (// VULN / // FIX 표기)
  ReentrancyAttacker.sol  # 공격A: 0.1씩 재귀 인출 (Ethernaut 정석)
  ReentrancyAttackerMax.sol # 공격B: 1회 재진입에 최대 금액 (실전형 — 2번에 전액)
  AuditMe.sol             # LLM 분석 연습용 — 버그 3개, 주석/힌트 없음
test/
  Fallback.t.sol          # testTakeover: owner 탈취 + 잔액 인출
  Reentrancy.t.sol        # testDrain: 0.1씩 → 5.1 전액 탈취
  ReentrancyMax.t.sol     # testDrainMax: 단 2번의 withdraw로 전액(잔액 크기 무관)
  AuditMe.t.sol           # testAnyoneCanDrain(무권한) + testTxOriginPhishing(피싱)
```

## 두 취약점은 왜 뚫리는가

### 1) Fallback — 접근제어 실패 (오전 개념: 접근제어 D-3)
`receive()`가 "기여한 적 있고 1 wei라도 보내면 `owner`를 호출자로 바꾼다." 즉 소유권 변경이
**정상 업무 함수가 아니라 송금이라는 옆문**에 매달려 있다. 공격자는 (1) 1 wei contribute로
`contributions > 0`을 만들고 (2) 컨트랙트에 1 wei를 직접 보내 `receive()`를 때려 owner를 가져온 뒤
(3) `withdraw()`로 잔액을 턴다. **권한 변경 경로가 하나로 통제되지 않은 것**이 핵심 결함.

### 2) Reentrancy — 두 개의 잔액 + CALL 재진입 (오전 개념: 두 개의 잔액 D-2 + CALL 재진입 F-6)
`withdraw()`가 **외부로 ETH를 먼저 보내고(call), 장부(balances) 차감은 나중**에 한다.
공격자 컨트랙트의 `receive()`는 ETH를 받자마자 차감되기 전의 잔액을 보고 `withdraw()`를 **재귀
호출**한다. "실제 컨트랙트 잔액"과 "장부상 내 잔액"이라는 **두 개의 잔액이 어긋난 창** 동안
반복 인출이 일어나 컨트랙트가 빌 때까지 빠져나간다.

> ⚠️ **0.8.20 관련 설계 메모**: 원본 Ethernaut Lv10은 Solidity 0.6.x다. 0.8.x는 산술
> 언더플로를 자동 revert하므로, 재진입 언와인드 단계에서 `balances -= _amount`가 음수가 되어
> **공격이 revert로 막혀 PoC가 성립하지 않는다.** 그래서 `Reentrancy.withdraw()`의 차감만
> `unchecked {}`로 감싸 0.6.x의 wrap 거동을 재현했다. (취약점 본질=call 선행은 그대로.)
> → 이것이 곧 방어 포인트: **0.8.x의 기본 오버플로/언더플로 검사 자체가 1차 방어선**이 된다.

### 재진입 공격, 두 가지 방식 (찔끔 vs 최대)
같은 취약점이지만 공격자가 1회당 빼는 금액에 따라 효율이 갈린다.

| 방식 | 1회 인출 | 재귀 횟수 | 한계 |
|---|---|---|---|
| A. 찔끔 (`ReentrancyAttacker`) | 0.1 ETH 고정 | 잔액÷0.1 (5.1 ETH → 51회) | **가스(63/64 규칙)로 ~270회에서 전액 revert**, EVM 콜스택 1024 |
| B. 최대 (`ReentrancyAttackerMax`) | min(컨트랙트잔액, 내장부) | **항상 2회** | 잔액 크기와 무관. 단 시드 ≥ 피해자 잔액 필요(현실에선 flash loan) |

핵심: 깊이로 승부 보는 게 아니라 **1회 인출액을 키우는 게 실전**이다. B는 피해자 잔액이 5든 50이든
`withdraw` **딱 2번**으로 컨트랙트를 비운다(`testDrainMax`/`testDrainMaxLargePot`로 증명). 재진입 중
장부(`balanceOf`)가 차감 전이라 그대로이므로, 매 호출 "뺄 수 있는 최대"를 빼면 깊이·가스 한계에 안 걸린다.

## 방어법 요약

| 취약점 | 방어 |
|---|---|
| 접근제어 (Fallback) | 권한 변경 경로 단일화 + `onlyOwner` 모디파이어 / OpenZeppelin `Ownable`. 송금 콜백(receive)에 권한 로직 금지. |
| 재진입 (Reentrancy) | **CEI 패턴**(Checks → Effects → Interactions): 잔액 **차감을 먼저**, 외부 호출을 마지막에. 추가로 `ReentrancyGuard`(mutex `nonReentrant`). |
| 무권한 함수 (AuditMe) | 모든 상태변경/자금이동 함수에 접근제어. `public` 기본값 방치 금지. |
| `tx.origin` 인증 (AuditMe) | 인증은 항상 **`msg.sender`** 로. `tx.origin`은 중간 컨트랙트 경유 피싱에 뚫린다. |

수정 예시(개념): `withdraw`를
```solidity
balances[msg.sender] -= _amount;                     // Effects 먼저
(bool ok, ) = msg.sender.call{value: _amount}("");   // Interactions 나중
require(ok);
```
순서로 바꾸고 컨트랙트에 `ReentrancyGuard`를 상속해 `nonReentrant`를 붙인다.

## AuditMe.sol — LLM 취약점 분석 연습

`src/AuditMe.sol`은 의도적으로 버그를 심되 **VULN/FIX 힌트 주석이 없다.** 아래 프롬프트로
LLM에게 직접 찾게 한 뒤, `test/AuditMe.t.sol`의 PoC와 대조하라(정답 스포일러는 테스트 파일에).

### LLM 프롬프트 템플릿
> 다음 Solidity 컨트랙트의 취약점을 심각도(CVSS)와 함께 모두 찾고, 각 취약점의 PoC
> 시나리오와 수정안을 제시하라. 오탐(false positive)도 구분해 표기하라:
>
> ```solidity
> <AuditMe.sol 코드 붙여넣기>
> ```

## 금지/원칙
- 메인넷·실제 개인키·실제 자금 **사용 안 함**. 전부 로컬 `anvil`/`forge` cheatcode.
- 외부 의존성 최소화: `forge-std`만 사용(OpenZeppelin은 FIX 설명에만 등장, import 안 함).

## (병행) Ethernaut 실전
로컬에서 손에 익힌 패턴을 Sepolia(Chain ID 11155111)에서 그대로 적용:
**Lv1 Fallback(권한 탈취)**, **Lv10 Re-entrancy(재진입)**.
faucet ETH는 미리 받아둘 것 (Alchemy/Google faucet).
