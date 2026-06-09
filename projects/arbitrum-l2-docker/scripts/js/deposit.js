#!/usr/bin/env node
// deposit.js — L1 → L2 ETH deposit via Inbox.depositEth(uint256 maxSubmissionCost)
//
// ABI Contract 방식 사용 (raw calldata 아님).
// L2 잔액 polling: l2BalanceBefore + depositAmount 이상이 될 때까지 대기.
//
// 환경변수 (shell script에서 주입):
//   L1_RPC, L2_RPC, INBOX_ADDRESS
//   DEPOSITOR_PRIVATE_KEY, DEPOSITOR_ADDRESS, DEPOSIT_AMOUNT_ETH
//   MAX_SUBMISSION_COST (optional, default: 143000000000000 = 0x82f79cd90000)
//   ARTIFACT_PATH
'use strict';

const { ethers } = require('ethers');
const fs = require('fs');

const INBOX_ABI = [
    'function depositEth(uint256 maxSubmissionCost) external payable returns (uint256)'
];

async function main() {
  const L1_RPC            = process.env.L1_RPC;
  const L2_RPC            = process.env.L2_RPC;
  const INBOX_ADDRESS     = process.env.INBOX_ADDRESS;
  const DEPOSITOR_PK      = process.env.DEPOSITOR_PRIVATE_KEY;
  const DEPOSITOR_ADDR    = process.env.DEPOSITOR_ADDRESS;
  const DEPOSIT_AMOUNT_ETH = process.env.DEPOSIT_AMOUNT_ETH;
  const ARTIFACT_PATH     = process.env.ARTIFACT_PATH;

  for (const [k, v] of Object.entries({ L1_RPC, L2_RPC, INBOX_ADDRESS, DEPOSITOR_PK, DEPOSITOR_ADDR, DEPOSIT_AMOUNT_ETH })) {
    if (!v) { console.error(`[ERROR] 환경변수 누락: ${k}`); process.exit(1); }
  }

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const wallet = new ethers.Wallet(DEPOSITOR_PK, l1Provider);

  // key → address 검증
  if (wallet.address.toLowerCase() !== DEPOSITOR_ADDR.toLowerCase()) {
    console.error(`[ERROR] DEPOSITOR_PRIVATE_KEY 주소 불일치`);
    console.error(`  파생된 주소: ${wallet.address.toLowerCase()}`);
    console.error(`  설정된 주소: ${DEPOSITOR_ADDR.toLowerCase()}`);
    process.exit(1);
  }

  const depositAmountWei = ethers.parseEther(DEPOSIT_AMOUNT_ETH);
  const maxSubmissionCost = BigInt(process.env.MAX_SUBMISSION_COST || '143000000000000');

  const l1Balance = await l1Provider.getBalance(wallet.address);
  console.log(`[INFO] L1 depositor : ${wallet.address}`);
  console.log(`[INFO] L1 balance   : ${ethers.formatEther(l1Balance)} ETH`);
  console.log(`[INFO] deposit      : ${DEPOSIT_AMOUNT_ETH} ETH → Inbox ${INBOX_ADDRESS}`);

  const GAS_BUFFER = ethers.parseEther('1');
  if (l1Balance < depositAmountWei + GAS_BUFFER) {
    console.error(
      `[ERROR] L1 잔액 부족: ${ethers.formatEther(l1Balance)} ETH` +
      ` (need ${DEPOSIT_AMOUNT_ETH} ETH + 1 ETH gas buffer)`
    );
    process.exit(1);
  }

  // L2 잔액 기록 (before)
  const l2Provider = new ethers.JsonRpcProvider(L2_RPC);
  let l2BalanceBefore = 0n;
  try {
    l2BalanceBefore = await l2Provider.getBalance(wallet.address);
  } catch (_) { /* L2 초기화 중 — 0으로 취급 */ }
  console.log(`[INFO] L2 balance (before): ${ethers.formatEther(l2BalanceBefore)} ETH`);

  // Inbox.depositEth(maxSubmissionCost) — ABI Contract 호출
  const inbox = new ethers.Contract(INBOX_ADDRESS, INBOX_ABI, wallet);
  console.log('[INFO] L1 트랜잭션 전송 중...');

  let tx;
  try {
    tx = await inbox.depositEth(maxSubmissionCost, { value: depositAmountWei });
  } catch (e) {
    console.error(`[ERROR] depositEth() 호출 실패: ${e.message}`);
    process.exit(1);
  }

  console.log(`[INFO] L1 tx hash   : ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`[OK]   L1 확인됨    : block ${receipt.blockNumber}, gasUsed ${receipt.gasUsed}`);

  // L2 잔액 polling: l2BalanceBefore + depositAmount 이상이 될 때까지
  const expectedL2Balance = l2BalanceBefore + depositAmountWei;
  console.log(`[INFO] L2 deposit 반영 대기 중... (목표: >= ${ethers.formatEther(expectedL2Balance)} ETH)`);

  let l2BalanceAfter = 0n;
  const maxAttempts = 120;
  for (let i = 0; i < maxAttempts; i++) {
    try {
      l2BalanceAfter = await l2Provider.getBalance(wallet.address);
      if (l2BalanceAfter >= expectedL2Balance) {
        process.stdout.write('\n');
        console.log(`[OK]   L2 잔액 확인 : ${ethers.formatEther(l2BalanceAfter)} ETH`);
        break;
      }
    } catch (_) { /* L2 RPC 일시 불안정 */ }
    process.stdout.write('.');
    await new Promise(r => setTimeout(r, 5000));
    if (i === maxAttempts - 1) {
      process.stdout.write('\n');
      console.error(
        `[ERROR] L2 deposit 타임아웃 (${maxAttempts * 5}s)\n` +
        `  현재 L2 잔액: ${ethers.formatEther(l2BalanceAfter)} ETH\n` +
        `  기대 잔액:    ${ethers.formatEther(expectedL2Balance)} ETH\n` +
        `  sequencer 로그를 확인하세요`
      );
      process.exit(1);
    }
  }

  const result = {
    from: wallet.address.toLowerCase(),
    to: wallet.address.toLowerCase(),
    inboxAddress: INBOX_ADDRESS.toLowerCase(),
    amountEth: DEPOSIT_AMOUNT_ETH,
    l1TxHash: tx.hash,
    l1BlockNumber: Number(receipt.blockNumber),
    l2BalanceBeforeEth: ethers.formatEther(l2BalanceBefore),
    l2BalanceAfterEth: ethers.formatEther(l2BalanceAfter),
    expectedL2BalanceEth: ethers.formatEther(expectedL2Balance),
    status: 'confirmed',
    timestamp: new Date().toISOString(),
  };

  if (ARTIFACT_PATH) {
    fs.writeFileSync(ARTIFACT_PATH, JSON.stringify(result, null, 4));
    console.log(`[OK]   artifact 저장: ${ARTIFACT_PATH}`);
  }
}

main().catch(e => {
  console.error('[ERROR]', e.message || String(e));
  process.exit(1);
});
