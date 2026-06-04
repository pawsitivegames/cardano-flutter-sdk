const CSL = require("@emurgo/cardano-serialization-lib-nodejs");
const MS = require("@emurgo/cardano-message-signing-nodejs");
const bip39 = require("bip39");

const MNEMONIC = "test walk nut penalty hip pave soap entry language right filter choice";
const H = (n) => (n | 0x80000000) >>> 0;
const hex = (u8) => Buffer.from(u8).toString("hex");

const entropy = bip39.mnemonicToEntropy(MNEMONIC); // hex string
const root = CSL.Bip32PrivateKey.from_bip39_entropy(Buffer.from(entropy, "hex"), Buffer.from(""));
const account = root.derive(H(1852)).derive(H(1815)).derive(H(0));
const paymentKey = account.derive(0).derive(0);          // role 0 / index 0
const stakeKey = account.derive(2).derive(0);            // role 2 / index 0
const payPub = paymentKey.to_raw_key().to_public();
const stkPub = stakeKey.to_raw_key().to_public();
const payCred = CSL.Credential.from_keyhash(payPub.hash());
const stkCred = CSL.Credential.from_keyhash(stkPub.hash());

const baseAddr = CSL.BaseAddress.new(0, payCred, stkCred).to_address();   // testnet
const rewardAddr = CSL.RewardAddress.new(0, stkCred).to_address();

function signData(addr, rawPrivKey, pubKey, message) {
  const ph = MS.HeaderMap.new();
  ph.set_algorithm_id(MS.Label.from_algorithm_id(MS.AlgorithmId.EdDSA));
  ph.set_header(MS.Label.new_text("address"), MS.CBORValue.new_bytes(addr.to_bytes()));
  const phSer = MS.ProtectedHeaderMap.new(ph);
  const headers = MS.Headers.new(phSer, MS.HeaderMap.new());
  const payload = Buffer.from(message, "utf8");
  const builder = MS.COSESign1Builder.new(headers, payload, false);
  const toSign = builder.make_data_to_sign().to_bytes();
  const sig = rawPrivKey.sign(toSign).to_bytes();
  const cose = builder.build(sig);
  const key = MS.EdDSA25519Key.new(pubKey.as_bytes());
  key.is_for_verifying();
  return {
    addressHex: hex(addr.to_bytes()),
    payloadHex: hex(payload),
    signatureHex: hex(cose.to_bytes()),
    keyHex: hex(key.build().to_bytes()),
  };
}

const out = {
  source: "@emurgo/cardano-message-signing-nodejs + @emurgo/cardano-serialization-lib-nodejs",
  mnemonic: MNEMONIC,
  baseAddressBech32: baseAddr.to_bech32(),
  rewardAddressBech32: rewardAddr.to_bech32(),
  vectors: {
    base_payment: signData(baseAddr, paymentKey.to_raw_key(), payPub, "Login to ExampleDApp at 2026-06-04"),
    reward_stake: signData(rewardAddr, stakeKey.to_raw_key(), stkPub, "Prove stake key ownership"),
  },
};
console.log(JSON.stringify(out, null, 2));
