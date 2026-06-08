#!/usr/bin/env node
// apply-prefund.mjs — prefund.json 계정을 genesis.json alloc에 추가
// Usage: node apply-prefund.mjs <genesis.json> <prefund.json> <depositContractAddr>

import { readFileSync, writeFileSync } from 'fs';

const [,, genesisPath, prefundPath, depositAddr] = process.argv;

if (!genesisPath || !prefundPath || !depositAddr) {
    console.error('Usage: node apply-prefund.mjs <genesis.json> <prefund.json> <depositContractAddr>');
    process.exit(1);
}

const genesis = JSON.parse(readFileSync(genesisPath, 'utf8'));
const prefund = JSON.parse(readFileSync(prefundPath, 'utf8'));
const accounts = prefund.accounts;

if (!Array.isArray(accounts) || accounts.length === 0) {
    console.log('  INFO: prefund.json에 계정이 없습니다 — 건너뜀');
    process.exit(0);
}

const depositBare = depositAddr.replace(/^0x/i, '').toLowerCase();
if (!genesis.alloc) genesis.alloc = {};

const seen = new Set();

for (const account of accounts) {
    const { address, balanceEth } = account;
    const name = account.name || address;

    // address 형식 검사
    if (!address || !/^0x[0-9a-fA-F]{40}$/.test(address)) {
        console.error(`ERROR: 잘못된 address 형식: "${address}" (name: ${name})`);
        console.error('       address는 "0x" + 40자리 hex 형식이어야 합니다');
        process.exit(1);
    }

    const addrBare = address.slice(2).toLowerCase();

    // deposit contract 충돌 검사
    if (addrBare === depositBare) {
        console.error(`ERROR: prefund address가 deposit contract address와 같습니다: ${address}`);
        process.exit(1);
    }

    // prefund.json 내 중복 검사
    if (seen.has(addrBare)) {
        console.error(`ERROR: 중복된 address: ${address} (name: ${name})`);
        process.exit(1);
    }
    seen.add(addrBare);

    // balanceEth 검사 — 양수 정수 문자열
    const balStr = String(balanceEth).trim();
    if (!/^\d+$/.test(balStr) || BigInt(balStr) === 0n) {
        console.error(`ERROR: 잘못된 balanceEth: "${balanceEth}" (name: ${name})`);
        console.error('       balanceEth는 양수 정수 문자열이어야 합니다 (예: "10000")');
        process.exit(1);
    }

    // 기존 alloc에 code가 있는 경우 덮어쓰기 금지
    if (genesis.alloc[addrBare] && genesis.alloc[addrBare].code) {
        console.error(`ERROR: 이미 contract code가 있는 주소에 prefund할 수 없습니다: ${address}`);
        process.exit(1);
    }

    // ETH → wei 변환 (BigInt)
    const weiHex = '0x' + (BigInt(balStr) * (10n ** 18n)).toString(16);

    genesis.alloc[addrBare] = { balance: weiHex };
    console.log(`  prefund: ${name}`);
    console.log(`           ${address} = ${balStr} ETH (${weiHex})`);
}

writeFileSync(genesisPath, JSON.stringify(genesis, null, 4));
console.log(`  genesis.json 업데이트 완료 (prefund ${accounts.length}개)`);
