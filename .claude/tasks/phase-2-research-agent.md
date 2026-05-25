# Task: Phase 2 Research Agent — CSL TX Builder & Blockfrost

**Assigned to:** Research Agent
**Deliverable:** `docs/research/phase-2-csl-tx-builder.md`
**Blocked by:** none
**Unblocks:** Rust TX Builder, Coin Selection, Signing, Blockfrost Provider agents

## Objective

Produce a focused research note that maps out exactly the CSL v15 API
surface, Blockfrost endpoints, and protocol-level rules the Phase 2
implementation agents need. No code; a tight reference doc.

## Required Output Sections

1. **CSL `TransactionBuilder` v15 walkthrough**
   - Constructor + required `TransactionBuilderConfig` fields
   - How to add inputs, outputs, change, metadata, TTL, validity range
   - Fee estimation flow (`min_fee` vs `add_change_if_needed`)
   - Witness set construction (vkey witnesses only for Phase 2)
   - Known gotchas (witness set ordering, deterministic CBOR, etc.)
   - Reference snippets — minimal compilable Rust, not pseudocode

2. **Min-ada calculation for multi-asset outputs**
   - The CSL helper signature
   - Current protocol coefficient on testnet preview
   - Worked example with an output carrying one ADA + one native token

3. **CIP-2 largest-first coin selection**
   - Algorithm spec, link to CIP
   - Edge cases: insufficient funds, dust, multi-asset balancing
   - Pseudocode at the level we'll implement in Rust

4. **Blockfrost endpoints needed for Phase 2**
   - `/addresses/{address}/utxos` — pagination, response shape
   - `/epochs/latest/parameters` — fields we map into `TransactionBuilderConfig`
   - `/tx/submit` — content-type, body (CBOR bytes), error codes we care about
   - Auth: `project_id` header, where to source the key from
   - Rate limits to be aware of

5. **Recommendations**
   - Should the TX builder add a fee buffer? If so, how much?
   - Should we cache protocol parameters per session or per build? For how long?
   - Any CSL API instability or deprecations to plan around in v15

## Style

- Concise; sections > prose
- Cite CSL source files or doc URLs for every claim
- Flag anything you couldn't verify rather than guessing
- Keep total length under ~400 lines

## Acceptance

- [ ] Doc exists at `docs/research/phase-2-csl-tx-builder.md`
- [ ] All five sections covered
- [ ] Compilable Rust snippets for the TX builder happy path
- [ ] Open questions explicitly flagged at the end
