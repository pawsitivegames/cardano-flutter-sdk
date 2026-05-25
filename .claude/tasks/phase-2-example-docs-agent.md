# Task: Phase 2 Example & Docs Agent

**Assigned to:** Example & Docs Agent
**Deliverable:** Example app "Send" screen + README + dartdoc
**Blocked by:** Test & Verification Agent (proof the pipeline works)
**Unblocks:** Phase 2 ship

## Objective

Translate the working Phase 2 pipeline into something a new user can
run, read, and copy from in five minutes.

## Scope

1. **Example app — Send screen**
   - New route: "Send testnet ADA"
   - Inputs: recipient address, amount (in ADA), optional native asset
     (policy_id, asset_name, quantity)
   - On submit: fetch UTXOs → build → preview fee → user confirms →
     sign → submit → show tx hash + link to testnet block explorer
   - Empty/error states are visible in the UI, not just console
   - Reads `BLOCKFROST_PROJECT_ID` from `--dart-define` and surfaces a
     friendly message if missing
   - **Do not** prefill a real mnemonic. Use the fixture testnet
     mnemonic from Phase 1 tests, and label the screen clearly as
     "testnet only — do not use with real funds"

2. **README**
   - "Send a transaction" section with a runnable snippet (10–20
     lines, compilable as-is)
   - Update the feature matrix to mark transaction building / signing /
     submission as v0.2.0
   - Setup row for `BLOCKFROST_PROJECT_ID` env var
   - Link to the testnet block explorer

3. **Dartdoc**
   - Every new public API in `dart/lib/src/` (TX builder wrappers,
     coin selection wrappers, signing wrappers, BlockfrostProvider)
     has a docstring with at least one short example
   - Run `dart doc` locally to confirm no warnings on new code

## Acceptance

- [ ] Example app builds and runs on iOS (simulator or device)
- [ ] One real testnet send succeeds from the example app, hash
      recorded in `docs/PHASE_2_VERIFICATION.md`
- [ ] README "Send a transaction" snippet compiles when copy-pasted
- [ ] `flutter analyze` clean
- [ ] No real-money warnings missing on the Send screen
