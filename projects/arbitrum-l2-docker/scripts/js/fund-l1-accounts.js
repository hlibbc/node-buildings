#!/usr/bin/env node
// fund-l1-accounts.js — L1 ETH 선분배 (depositor → deployer / batchPoster / validator)
//
// batch-poster와 validator는 L1 트랜잭션을 발생시키므로 rollup 배포 전 L1 ETH 필요.
//
// 환경변수 (shell script에서 주입):
//   L1_RPC                   — L1 HTTP RPC endpoint
//   L2_DEPOSITOR_PRIVATE_KEY — signer (L1 depositor)
//   L2_DEPOSITOR_ADDRESS     — signer address 검증용
//   TARGETS_JSON             — JSON array: [{role, address, amountEth, optional}, ...]
//   ARTIFACT_PATH            — 결과 저장 경로
//   FORCE                    — "1" = 잔액 무관 강제 전송
'use strict';

const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
  const L1_RPC         = process.env.L1_RPC;
  const DEPOSITOR_PK   = process.env.L2_DEPOSITOR_PRIVATE_KEY;
  const DEPOSITOR_ADDR = process.env.L2_DEPOSITOR_ADDRESS;
  const TARGETS_JSON   = process.env.TARGETS_JSON;
  const ARTIFACT_PATH  = process.env.ARTIFACT_PATH;
  const FORCE          = process.env.FORCE === '1';

  for (const [k, v] of Object.entries({ L1_RPC, DEPOSITOR_PK, DEPOSITOR_ADDR, TARGETS_JSON })) {
    if (!v) { console.error(`[ERROR] 환경변수 누락: ${k}`); process.exit(1); }
  }

  const l1Provider = new ethers.JsonRpcProvider(L1_RPC);
  const wallet = new ethers.Wallet(DEPOSITOR_PK, l1Provider);

  // key → address 검증
  if (wallet.address.toLowerCase() !== DEPOSITOR_ADDR.toLowerCase()) {
    console.error(`[ERROR] L2_DEPOSITOR_PRIVATE_KEY 주소 불일치`);
    console.error(`  파생된 주소: ${wallet.address.toLowerCase()}`);
    console.error(`  설정된 주소: ${DEPOSITOR_ADDR.toLowerCase()}`);
    process.exit(1);
  }

  const depositorBalance = await l1Provider.getBalance(wallet.address);
  console.log(`[INFO] L1 depositor : ${wallet.address}`);
  console.log(`[INFO] L1 balance   : ${ethers.formatEther(depositorBalance)} ETH`);

  const targets = JSON.parse(TARGETS_JSON);
  const results = [];

  // address 유효성 사전 검사 (required 항목)
  for (const { role, address, optional } of targets) {
    if (!address || address === '') {
      if (!optional) {
        console.error(`[ERROR] ${role}: address 미설정 (필수 항목)`);
        process.exit(1);
      }
      continue;
    }
    if (!/^0x[0-9a-fA-F]{40}$/.test(address)) {
      console.error(`[ERROR] ${role}: 잘못된 주소 형식: ${address}`);
      process.exit(1);
    }
  }

  // 실제로 필요한 금액 사전 계산 (이미 funded 계정 제외)
  let totalActuallyNeeded = 0n;
  const needsFunding = new Map();

  for (const { role, address, amountEth, optional } of targets) {
    if (!address || address === '') continue;
    if (address.toLowerCase() === wallet.address.toLowerCase()) continue; // self

    const amountWei = ethers.parseEther(amountEth);
    const currentBalance = await l1Provider.getBalance(address);

    if (!FORCE && currentBalance >= amountWei) {
      needsFunding.set(role, false);
    } else {
      needsFunding.set(role, true);
      totalActuallyNeeded += amountWei;
    }
  }

  if (depositorBalance < totalActuallyNeeded) {
    console.error(
      `[ERROR] L1 depositor 잔액 부족: ` +
      `${ethers.formatEther(depositorBalance)} ETH < ` +
      `${ethers.formatEther(totalActuallyNeeded)} ETH 필요`
    );
    process.exit(1);
  }

  // 송금 실행
  for (const { role, address, amountEth, optional } of targets) {
    if (!address || address === '') {
      console.log(`[SKIP] ${role}: address 미설정${optional ? ' (optional)' : ''}`);
      results.push({ role, address: '', amountEth, txHash: null, status: 'skipped', reason: 'no_address' });
      continue;
    }

    if (address.toLowerCase() === wallet.address.toLowerCase()) {
      console.log(`[SKIP] ${role}: depositor와 동일한 주소 (self-transfer 생략)`);
      const bal = await l1Provider.getBalance(address);
      results.push({ role, address: address.toLowerCase(), amountEth, txHash: null,
        balanceAfterEth: ethers.formatEther(bal), status: 'skipped', reason: 'self_transfer' });
      continue;
    }

    const amountWei = ethers.parseEther(amountEth);
    const balanceBefore = await l1Provider.getBalance(address);

    if (!FORCE && !needsFunding.get(role)) {
      console.log(
        `[SKIP] ${role} (${address}): ` +
        `이미 충분한 잔액 (${ethers.formatEther(balanceBefore)} ETH >= ${amountEth} ETH)`
      );
      results.push({
        role, address: address.toLowerCase(), amountEth, txHash: null,
        balanceBeforeEth: ethers.formatEther(balanceBefore),
        balanceAfterEth: ethers.formatEther(balanceBefore),
        status: 'skipped', reason: 'already_funded',
      });
      continue;
    }

    try {
      console.log(`[INFO] ${role} (${address}): ${amountEth} ETH 전송 중...`);
      const tx = await wallet.sendTransaction({ to: address, value: amountWei });
      const receipt = await tx.wait();
      const balanceAfter = await l1Provider.getBalance(address);
      console.log(`[OK]   ${role}: ${ethers.formatEther(balanceAfter)} ETH  (tx: ${tx.hash})`);
      results.push({
        role, address: address.toLowerCase(), amountEth,
        txHash: tx.hash, l1BlockNumber: Number(receipt.blockNumber),
        balanceBeforeEth: ethers.formatEther(balanceBefore),
        balanceAfterEth: ethers.formatEther(balanceAfter),
        status: 'sent',
      });
    } catch (e) {
      console.error(`[ERROR] ${role} 전송 실패: ${e.message}`);
      results.push({
        role, address: address.toLowerCase(), amountEth,
        txHash: null, status: 'failed', reason: e.message,
      });
    }
  }

  const artifact = {
    timestamp: new Date().toISOString(),
    depositor: wallet.address.toLowerCase(),
    distributions: results,
  };

  if (ARTIFACT_PATH) {
    fs.writeFileSync(ARTIFACT_PATH, JSON.stringify(artifact, null, 4));
    console.log(`[OK]   artifact 저장: ${ARTIFACT_PATH}`);
  }

  const sent    = results.filter(r => r.status === 'sent').length;
  const skipped = results.filter(r => r.status === 'skipped').length;
  const failed  = results.filter(r => r.status === 'failed');
  console.log(`\nL1 funding 결과: ${sent}개 전송 완료, ${skipped}개 스킵`);

  if (failed.length > 0) {
    console.error(`[ERROR] ${failed.length}개 전송 실패`);
    process.exit(1);
  }
}

main().catch(e => {
  console.error('[ERROR]', e.message || String(e));
  process.exit(1);
});
