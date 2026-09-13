#!/usr/bin/env node
/* solidity_evm.cjs — run a generated contract on a real EVM, for
   tools/solidity_test.pl.

   The generator (src/syntax/lps_solidity.pl) claims that the contract does what
   the LPS program does. This checks it the only way that means anything: the
   program's own scenario is replayed as calls on an in-process EVM
   (@ethereumjs/vm), and the state the contract ends in is read back through its
   public getters, for the test to compare with the state LPS2's run ends in.

     node tools/solidity_evm.cjs plan.json      prints result JSON on stdout

   plan.json:
     { "source": "...", "contract": "Erc20",
       "ctor":  ["alice", ...],                   named accounts, constructor order
       "calls": [{"from": "alice", "fn": "transfer",
                  "args": [{"t": "uint256", "v": "300"}, {"t": "address", "v": "bob"}]}],
       "reads": [{"fn": "balance", "args": [...], "out": "uint256"}] }

   A name used as an address is a deterministic address (its keccak's last 20
   bytes); "address(0)" is the zero address.

   Two dependencies, neither part of LPS2, so the caller says where they are:
     LPS_SOLC_MODULES  a node_modules with `solc` (InsurLE2/migration/solidity has one)
     LPS_EVM_MODULES   a node_modules with @ethereumjs/vm, /common, /util
                       (default: build/evm/node_modules)
   Exit 3 without solc, so the test can skip rather than fail; without an EVM
   the contract is only compiled. */
'use strict';
const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

function from(dirEnv, fallback, name) {
  const dirs = [process.env[dirEnv], fallback].filter(Boolean);
  for (const d of dirs) {
    try { return createRequire(path.join(d, 'x.js'))(name); } catch { /* next */ }
  }
  return null;
}

const solc = from('LPS_SOLC_MODULES', '/InsurLE2/migration/solidity/node_modules', 'solc');
//  build/ is LPS2's gitignored scratch: `npm i --prefix build/evm @ethereumjs/vm@10
//  @ethereumjs/common@10 @ethereumjs/util@10` puts an EVM where this looks by default.
const EVM_DEFAULT = path.join(__dirname, '..', 'build', 'evm', 'node_modules');
const vmMod = from('LPS_EVM_MODULES', EVM_DEFAULT, '@ethereumjs/vm');
const util = from('LPS_EVM_MODULES', EVM_DEFAULT, '@ethereumjs/util');
const common = from('LPS_EVM_MODULES', EVM_DEFAULT, '@ethereumjs/common');
if (!solc) {
  console.error('solidity_evm: solc not found (set LPS_SOLC_MODULES)');
  process.exit(3);
}
//  Without an EVM the contract is still compiled: `deployed` is then null.
const haveEvm = !!(vmMod && util && common);
const sha3 = haveEvm && (from('LPS_EVM_MODULES', EVM_DEFAULT, '@noble/hashes/sha3.js') || from('LPS_EVM_MODULES', EVM_DEFAULT, '@noble/hashes/sha3'));
const keccak256 = (b) => sha3.keccak_256(Uint8Array.from(b));

const plan = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

function hex(b) { return Buffer.from(b).toString('hex'); }
function word(bigint) { return bigint.toString(16).padStart(64, '0'); }
function nameAddress(n) {
  if (n === 'address(0)') return '0'.repeat(40);
  return hex(keccak256(Buffer.from('lps:' + n))).slice(24);
}
function selector(sig) { return hex(keccak256(Buffer.from(sig))).slice(0, 8); }

/* The ABI for the types the generator uses: static words, and strings. */
function encode(args) {
  const heads = [], tails = [];
  let dynOffset = 32 * args.length;
  for (const a of args) {
    if (a.t === 'string') {
      const bytes = Buffer.from(String(a.v), 'utf8');
      heads.push(word(BigInt(dynOffset)));
      const body = word(BigInt(bytes.length)) + hex(bytes).padEnd(Math.ceil(bytes.length / 32) * 64, '0');
      tails.push(body);
      dynOffset += body.length / 2;
    } else heads.push(encodeWord(a));
  }
  return heads.join('') + tails.join('');
}
function encodeWord(a) {
  switch (a.t) {
    case 'address': return nameAddress(a.v).padStart(64, '0');
    case 'bool': return word(a.v === true || a.v === 'true' ? 1n : 0n);
    case 'bytes32': return hex(Buffer.from(String(a.v), 'utf8')).padEnd(64, '0').slice(0, 64);
    case 'int256': { let v = BigInt(a.v); if (v < 0n) v = (1n << 256n) + v; return word(v); }
    default: return word(BigInt(a.v));
  }
}
function decode(out, t, names) {
  const h = hex(out);
  switch (t) {
    case 'bool': return BigInt('0x' + h.slice(0, 64)) !== 0n;
    case 'address': {
      const a = h.slice(24, 64);
      if (/^0+$/.test(a)) return 'address(0)';
      return names[a] ?? ('0x' + a);
    }
    case 'string': {
      const off = Number(BigInt('0x' + h.slice(0, 64))) * 2;
      const len = Number(BigInt('0x' + h.slice(off, off + 64)));
      return Buffer.from(h.slice(off + 64, off + 64 + len * 2), 'hex').toString('utf8');
    }
    case 'bytes32': return Buffer.from(h.slice(0, 64), 'hex').toString('utf8').replace(/\0+$/, '');
    case 'int256': { let v = BigInt('0x' + h.slice(0, 64)); if (v >> 255n) v -= 1n << 256n; return v.toString(); }
    default: return BigInt('0x' + h.slice(0, 64)).toString();
  }
}

(async () => {
  const input = { language: 'Solidity', sources: { 'c.sol': { content: plan.source } },
    settings: { outputSelection: { '*': { '*': ['evm.bytecode.object'] } } } };
  const out = JSON.parse(solc.compile(JSON.stringify(input)));
  const errs = (out.errors || []).filter((e) => e.severity === 'error');
  if (errs.length) { console.log(JSON.stringify({ compiled: false, errors: errs.map((e) => e.formattedMessage) })); return; }
  const warnings = (out.errors || []).filter((e) => e.severity !== 'error').map((e) => e.formattedMessage);
  const bytecode = out.contracts['c.sol'][plan.contract].evm.bytecode.object;
  if (!haveEvm) { console.log(JSON.stringify({ compiled: true, deployed: null, warnings })); return; }

  const vm = await vmMod.createVM({ common: new common.Common({ chain: common.Mainnet, hardfork: common.Hardfork.Cancun }) });
  const names = {};
  const addr = (n) => { const a = nameAddress(n); names[a] = n; return util.createAddressFromString('0x' + a); };
  const deployer = addr('the deployer');
  const ctorArgs = (plan.ctor || []).map((n) => ({ t: 'address', v: n }));
  for (const n of plan.ctor || []) addr(n);
  const created = await vm.evm.runCall({
    caller: deployer, data: Buffer.from(bytecode + encode(ctorArgs), 'hex'), gasLimit: 30000000n,
  });
  if (created.execResult.exceptionError) {
    console.log(JSON.stringify({ compiled: true, deployed: false, error: String(created.execResult.exceptionError.error) }));
    return;
  }
  const to = created.createdAddress;
  const call = async (caller, fn, args) => {
    const sig = `${fn}(${args.map((a) => a.t).join(',')})`;
    return vm.evm.runCall({ caller, to, gasLimit: 30000000n,
      data: Buffer.from(selector(sig) + encode(args), 'hex') });
  };
  for (const a of plan.calls) for (const x of a.args) if (x.t === 'address') addr(x.v);
  for (const r of plan.reads) for (const x of r.args) if (x.t === 'address') addr(x.v);
  const calls = [];
  for (const c of plan.calls) {
    const r = await call(c.from ? addr(c.from) : deployer, c.fn, c.args);
    calls.push(r.execResult.exceptionError ? { ok: false } : { ok: true });
  }
  const reads = [];
  for (const r of plan.reads) {
    const res = await call(deployer, r.fn, r.args);
    reads.push(res.execResult.exceptionError ? null : decode(res.execResult.returnValue, r.out, names));
  }
  console.log(JSON.stringify({ compiled: true, deployed: true, warnings, calls, reads }));
})().catch((e) => { console.log(JSON.stringify({ error: String(e && e.stack || e) })); });
