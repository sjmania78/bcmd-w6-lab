#!/usr/bin/env bash
# BCMD 6주차 라이브 시연 — 강사 앞에서: ./demo.sh
# 1) 전체 익스플로잇 테스트 green  2) 재진입 재귀 호출 트레이스
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")" || exit 1

echo "════════════════════════════════════════════════"
echo " 1) 전체 익스플로잇 테스트 (Fallback·Reentrancy·AuditMe)"
echo "════════════════════════════════════════════════"
forge test -vvv

echo
echo "════════════════════════════════════════════════"
echo " 2) 재진입이 '실제로' 재귀 호출되는 트레이스"
echo "    (withdraw → receive → withdraw … 51회)"
echo "════════════════════════════════════════════════"
forge test --match-test testDrain -vvvv 2>/dev/null \
  | grep -E 'withdraw|receive|donate|drained|\[PASS\]' | head -28
