#!/usr/bin/env node
// verify-keys.js — .env의 private key → address 파생 일치 검증
// 00-check-requirements.sh에서 호출됩니다.
// 불일치 시 exit code 1.
"use strict";

const path = require("path");
const fs = require("fs");

const PROJECT_ROOT = process.env.PROJECT_ROOT || path.resolve(__dirname, "../..");
const { Wallet } = require(path.join(PROJECT_ROOT, "node_modules", "ethers"));

const ENV_PATH = path.join(PROJECT_ROOT, ".env");
if (!fs.existsSync(ENV_PATH)) {
    process.stderr.write("[ERROR] .env not found: " + ENV_PATH + "\n");
    process.exit(1);
}

const env = Object.fromEntries(
    fs.readFileSync(ENV_PATH, "utf8")
        .split(/\r?\n/)
        .filter((l) => l && !l.startsWith("#") && l.includes("="))
        .map((l) => {
            const idx = l.indexOf("=");
            return [l.slice(0, idx).trim(), l.slice(idx + 1).trim()];
        })
);

const ROLES = [
    "L2_DEPOSITOR",
    "L2_DEPLOYER",
    "L2_ROLLUP_OWNER",
    "L2_SEQUENCER",
    "L2_BATCH_POSTER",
    "L2_VALIDATOR",
];

let errors = 0;
for (const role of ROLES) {
    const address = env[`${role}_ADDRESS`];
    const pk = env[`${role}_PRIVATE_KEY`];

    if (!address && !pk) {
        process.stdout.write(`  [SKIP]  ${role}: 미설정\n`);
        continue;
    }
    if (!pk) {
        process.stdout.write(`  [SKIP]  ${role}: PRIVATE_KEY 없음 (address only)\n`);
        continue;
    }
    if (!address) {
        process.stderr.write(`  [FAIL]  ${role}: ADDRESS 미설정\n`);
        errors++;
        continue;
    }

    let derived;
    try {
        derived = new Wallet(pk).address.toLowerCase();
    } catch (e) {
        process.stderr.write(`  [FAIL]  ${role}: 유효하지 않은 private key — ${e.message}\n`);
        errors++;
        continue;
    }

    if (derived === address.toLowerCase()) {
        process.stdout.write(`  [OK]    ${role}: ${derived}\n`);
    } else {
        process.stderr.write(`  [FAIL]  ${role}: key/address 불일치\n`);
        process.stderr.write(`            파생 주소: ${derived}\n`);
        process.stderr.write(`            설정 주소: ${address.toLowerCase()}\n`);
        errors++;
    }
}

process.exit(errors > 0 ? 1 : 0);
