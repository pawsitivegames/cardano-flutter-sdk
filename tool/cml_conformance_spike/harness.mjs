// CML-JS ↔ CSL golden-vector conformance spike (Node, nodejs CML build).
// Proves whether CML 6.2.0 reproduces the frozen CSL golden bytes byte-for-byte.
import { createRequire } from 'module';
import { readFileSync } from 'fs';
const require = createRequire(import.meta.url);
const CML = require('@dcspark/cardano-multiplatform-lib-nodejs');
const MS = require('@emurgo/cardano-message-signing-nodejs');
const bip39 = require('bip39');

const HARDEN = 0x80000000;

// Read the canonical golden vectors directly (single source of truth) so this
// spike can never drift from a stale copy.
// Preserve large int64 `n` values as strings so JSON.parse doesn't round them
// through float64 (the real Dart backend passes a true int64).
const goldenPath = new URL(
  '../../dart/test/conformance/golden_cbor.json', import.meta.url);
const rawGolden = readFileSync(goldenPath, 'utf8')
  .replace(/("n":\s*)(-?\d+)/g, '$1"$2"');
const golden = JSON.parse(rawGolden);

const hexToBytes = (h) => Uint8Array.from(h.match(/../g) || [], (b) => parseInt(b, 16));

// --- op implementations via CML -------------------------------------------
function computeBaseAddress({ paymentKeyHashHex, stakeKeyHashHex, networkId }) {
  const pay = CML.Credential.new_pub_key(CML.Ed25519KeyHash.from_hex(paymentKeyHashHex));
  const stk = CML.Credential.new_pub_key(CML.Ed25519KeyHash.from_hex(stakeKeyHashHex));
  return CML.BaseAddress.new(networkId, pay, stk).to_address().to_bech32();
}
function addressToHex({ addressBech32 }) {
  return CML.Address.from_bech32(addressBech32).to_hex();
}
function valueToCbor({ coin, assets }) {
  if (assets.length === 0) return CML.Value.from_coin(BigInt(coin)).to_cbor_hex();
  const ma = CML.MultiAsset.new();
  for (const a of assets) {
    const pid = CML.ScriptHash.from_hex(a.policyId);
    const an = CML.AssetName.from_hex(a.assetName);
    let inner = ma.get_assets(pid);
    if (!inner) inner = CML.MapAssetNameToCoin.new();
    inner.insert(an, BigInt(a.quantity));
    ma.insert_assets(pid, inner);
  }
  // CSL canonically sorts multi-asset map keys (length, then lexicographic);
  // CML preserves insertion order under to_cbor_hex(). Canonical matches CSL.
  const v = CML.Value.new(BigInt(coin), ma);
  return v.to_canonical_cbor_hex();
}
// Plutus: CSL emits Cardano-node CBOR (indefinite-length constr/list arrays).
// CML's default `to_cbor_hex()` uses definite-length; `to_cardano_node_format()`
// normalizes to the node encoding, matching CSL byte-for-byte.
function plutusInt({ n }) {
  return CML.PlutusData.new_integer(CML.BigInteger.from_str(String(n)))
    .to_cardano_node_format().to_cbor_hex();
}
function plutusBytes({ hexData }) {
  return CML.PlutusData.new_bytes(hexToBytes(hexData))
    .to_cardano_node_format().to_cbor_hex();
}
function plutusConstr({ constructor, fieldsCborHex }) {
  const list = CML.PlutusDataList.new();
  for (const f of fieldsCborHex) list.add(CML.PlutusData.from_cbor_hex(f));
  const c = CML.ConstrPlutusData.new(BigInt(constructor), list);
  return CML.PlutusData.new_constr_plutus_data(c)
    .to_cardano_node_format().to_cbor_hex();
}
function plutusList({ itemsCborHex }) {
  const list = CML.PlutusDataList.new();
  for (const f of itemsCborHex) list.add(CML.PlutusData.from_cbor_hex(f));
  return CML.PlutusData.new_list(list).to_cardano_node_format().to_cbor_hex();
}
function witnessSet({ witnesses }) {
  const vlist = CML.VkeywitnessList.new();
  for (const w of witnesses) {
    const vk = CML.PublicKey.from_bytes(hexToBytes(w.vkeyHex));
    const sig = CML.Ed25519Signature.from_raw_bytes(hexToBytes(w.signatureHex));
    vlist.add(CML.Vkeywitness.new(vk, sig));
  }
  const ws = CML.TransactionWitnessSet.new();
  ws.set_vkeywitnesses(vlist);
  return ws.to_cbor_hex();
}

function keyDerivation({ mnemonic, passphrase, accountIndex }) {
  const entropy = hexToBytes(bip39.mnemonicToEntropy(mnemonic));
  const root = CML.Bip32PrivateKey.from_bip39_entropy(entropy, new Uint8Array());
  const acct = root.derive(HARDEN + 1852).derive(HARDEN + 1815).derive(HARDEN + accountIndex);
  const pay = acct.derive(0).derive(0).to_raw_key().to_public().hash().to_hex();
  const stk = acct.derive(2).derive(0).to_raw_key().to_public().hash().to_hex();
  return `${pay}|${stk}`;
}
function deriveAddress({ accountKey, role, index, networkId }) {
  const acct = CML.Bip32PrivateKey.from_bech32(accountKey);
  const payHash = acct.derive(role).derive(index).to_raw_key().to_public().hash();
  const stkHash = acct.derive(2).derive(0).to_raw_key().to_public().hash();
  const addr = CML.BaseAddress.new(
    networkId,
    CML.Credential.new_pub_key(payHash),
    CML.Credential.new_pub_key(stkHash),
  ).to_address().to_bech32();
  return `${addr}|${payHash.to_hex()}`;
}
function signData({ addressHex, payloadHex, signingKeyBech32 }) {
  const bip32 = CML.Bip32PrivateKey.from_bech32(signingKeyBech32);
  const priv = bip32.to_raw_key();
  const pub = priv.to_public();

  const protectedHm = MS.HeaderMap.new();
  protectedHm.set_algorithm_id(MS.Label.from_algorithm_id(MS.AlgorithmId.EdDSA));
  protectedHm.set_header(
    MS.Label.new_text('address'),
    MS.CBORValue.new_bytes(hexToBytes(addressHex)),
  );
  const protectedSer = MS.ProtectedHeaderMap.new(protectedHm);
  const headers = MS.Headers.new(protectedSer, MS.HeaderMap.new());

  const builder = MS.COSESign1Builder.new(headers, hexToBytes(payloadHex), false);
  const toSign = builder.make_data_to_sign().to_bytes();
  const sig = priv.sign(toSign).to_raw_bytes();
  const coseSign1 = builder.build(sig);

  const key = MS.EdDSA25519Key.new(pub.to_raw_bytes());
  key.is_for_verifying();
  const coseKey = key.build();

  const toHex = (u8) => Array.from(u8, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${toHex(coseSign1.to_bytes())}|${toHex(coseKey.to_bytes())}`;
}

const OPS = {
  computeBaseAddress, addressToHex, valueToCbor,
  plutusInt, plutusBytes, plutusConstr, plutusList, witnessSet,
  keyDerivation, deriveAddress, signData,
};

// --- run ------------------------------------------------------------------
let pass = 0, fail = 0, skip = 0;
const fails = [];
for (const c of golden) {
  const fn = OPS[c.op];
  if (!fn) { skip++; continue; }
  let got;
  try { got = fn(c.input); } catch (e) { got = 'ERROR: ' + e.message; }
  if (got === c.expected) { pass++; }
  else { fail++; fails.push({ id: c.id, op: c.op, exp: c.expected, got }); }
}
console.log(`PASS ${pass}  FAIL ${fail}  SKIP(unimpl ops) ${skip}  / ${golden.length}`);
for (const f of fails) {
  console.log(`\n✗ ${f.id} (${f.op})`);
  console.log(`  exp: ${f.exp}`);
  console.log(`  got: ${f.got}`);
}
