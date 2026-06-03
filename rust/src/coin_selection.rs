//! Coin selection for transaction building (CIP-2 largest-first algorithm).
//!
//! This module implements the CIP-2 largest-first coin selection algorithm
//! as a pure, deterministic Rust function. No I/O, no randomness, no statics.
//!
//! ## Algorithm
//!
//! 1. Sort available UTXOs by ADA value descending (deterministic tiebreak
//!    on tx_hash + output_index).
//! 2. Greedily add inputs until `sum(inputs) >= sum(target_outputs) +
//!    estimated_fee + min_change_ada`.
//! 3. Estimate fee after each input added; fee grows with input count.
//! 4. For multi-asset targets, ensure selected inputs cover both ADA sum
//!    *and* each target asset quantity.
//! 5. If residual ADA < min_ada, add another input to avoid dust.
//! 6. Return error if insufficient funds or assets.
//!
//! ## Invariants (tested via property tests)
//!
//! - `sum_selected_inputs.coin == sum_target_outputs.coin + change.coin + fee`
//! - For each asset in target: `sum_selected_inputs.assets[k] >= sum_target_outputs.assets[k]`

use crate::error::CardanoError;
use crate::tx::{NativeAsset, ProtocolParams, TxInput, TxOutput, Value};
use std::collections::HashMap;

/// Result of successful coin selection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoinSelectionResult {
    /// UTXOs selected to cover outputs and fees.
    pub selected_inputs: Vec<TxInput>,
    /// Change output(s); typically one pure-ADA output plus optional multi-asset outputs.
    pub change_outputs: Vec<TxOutput>,
    /// Computed transaction fee.
    pub fee: u64,
}

/// Implements CIP-2 largest-first coin selection.
///
/// Selects a minimal set of inputs from `available_utxos` that cover
/// `target_outputs`, estimated fees, and minimum change ADA, prioritizing
/// larger inputs to minimize the number of UTXOs consumed.
///
/// # Arguments
///
/// * `available_utxos` - Pool of unspent outputs to select from.
/// * `target_outputs` - Desired payment outputs (not including change).
/// * `change_address` - Address to send change to.
/// * `params` - Network protocol parameters (fees, min-ada).
///
/// # Errors
///
/// - `CardanoError::InsufficientFunds` if total available < target + fee + min_change.
/// - `CardanoError::InsufficientAsset` if no UTXOs carry a required native asset.
/// - `CardanoError::DustChange` if change would be below min-ada and no more inputs available.
///
/// # Example
///
/// ```ignore
/// let utxos = vec![
///     TxInput { tx_hash: "aaa...".to_string(), output_index: 0, address: "addr...".to_string(), value: Value { coin: 2_000_000, assets: vec![] } },
///     TxInput { tx_hash: "bbb...".to_string(), output_index: 0, address: "addr...".to_string(), value: Value { coin: 1_000_000, assets: vec![] } },
/// ];
/// let targets = vec![
///     TxOutput { address: "addr_recv...".to_string(), value: Value { coin: 1_500_000, assets: vec![] } },
/// ];
/// let result = largest_first(utxos, targets, "addr_change...".to_string(), params)?;
/// assert_eq!(result.selected_inputs.len(), 1);
/// ```
pub fn largest_first(
    available_utxos: Vec<TxInput>,
    target_outputs: Vec<TxOutput>,
    change_address: String,
    params: ProtocolParams,
) -> Result<CoinSelectionResult, CardanoError> {
    // Validate inputs
    if target_outputs.is_empty() {
        return Err(CardanoError::CoinSelectionError(
            "Target outputs cannot be empty".to_string(),
        ));
    }

    if available_utxos.is_empty() {
        return Err(CardanoError::InsufficientFunds {
            needed_lovelace: target_outputs.iter().map(|o| o.value.coin).sum(),
            available_lovelace: 0,
        });
    }

    // Calculate total target coin and asset requirements
    let target_coin: u64 = target_outputs.iter().map(|o| o.value.coin).sum();
    let target_assets = aggregate_assets(&target_outputs);

    // Min ADA for a pure-ADA change output (~0.97 ADA on mainnet/preview)
    let min_ada_for_change = estimate_min_ada(&params);

    // Estimate total output count: target outputs + up to 2 change outputs (ADA + multi-asset)
    let est_num_outputs = target_outputs.len() + 2;

    // Sort UTXOs: descending by coin, with deterministic tiebreak on (tx_hash, output_index).
    let mut sorted_utxos = available_utxos;
    sorted_utxos.sort_by(|a, b| {
        // Primary: coin descending
        match b.value.coin.cmp(&a.value.coin) {
            std::cmp::Ordering::Equal => {
                // Tiebreak: tx_hash ascending, then output_index ascending
                match a.tx_hash.cmp(&b.tx_hash) {
                    std::cmp::Ordering::Equal => a.output_index.cmp(&b.output_index),
                    other => other,
                }
            }
            other => other,
        }
    });

    // Greedily select inputs
    let mut selected = Vec::new();
    let mut accumulated_coin: u64 = 0;
    let mut accumulated_assets: HashMap<(String, String), u64> = HashMap::new();

    for utxo in &sorted_utxos {
        // Add this UTXO to consideration
        accumulated_coin += utxo.value.coin;
        for asset in &utxo.value.assets {
            let key = (asset.policy_id.clone(), asset.asset_name.clone());
            *accumulated_assets.entry(key).or_insert(0) += asset.quantity;
        }

        // Estimate fee for current selection
        let tentative_fee = estimate_fee_for_inputs(selected.len() + 1, est_num_outputs, &params);
        let needed_coin = target_coin + tentative_fee + min_ada_for_change;

        // Check if we have enough coin and all required assets
        let have_all_assets = target_assets.iter().all(|(key, needed_qty)| {
            accumulated_assets.get(key).copied().unwrap_or(0) >= *needed_qty
        });

        selected.push(utxo.clone());

        if accumulated_coin >= needed_coin && have_all_assets {
            break;
        }

        // Avoid infinite loop: cap at reasonable number (e.g., 80 inputs)
        if selected.len() >= 80 {
            return Err(CardanoError::CoinSelectionError(
                "Exceeded maximum inputs (80)".to_string(),
            ));
        }
    }

    // Final validation: do we have enough?
    let final_fee = estimate_fee_for_inputs(selected.len(), est_num_outputs, &params);
    if accumulated_coin < target_coin + final_fee + min_ada_for_change {
        // Check if it's an asset shortage or coin shortage
        for (key, needed_qty) in &target_assets {
            let have = accumulated_assets.get(key).copied().unwrap_or(0);
            if have < *needed_qty {
                return Err(CardanoError::InsufficientAsset {
                    policy_id: key.0.clone(),
                    asset_name: key.1.clone(),
                    needed: *needed_qty,
                    available: have,
                });
            }
        }
        return Err(CardanoError::InsufficientFunds {
            needed_lovelace: target_coin + final_fee + min_ada_for_change,
            available_lovelace: accumulated_coin,
        });
    }

    // Compute change
    let change_coin = accumulated_coin - target_coin - final_fee;
    if change_coin > 0 && change_coin < min_ada_for_change {
        // Dust change: try to add another input
        let already_selected_set: std::collections::HashSet<_> = selected
            .iter()
            .map(|u| (u.tx_hash.clone(), u.output_index))
            .collect();
        let mut added = false;

        for utxo in &sorted_utxos {
            if already_selected_set.contains(&(utxo.tx_hash.clone(), utxo.output_index)) {
                continue;
            }
            selected.push(utxo.clone());
            accumulated_coin += utxo.value.coin;
            let new_fee = estimate_fee_for_inputs(selected.len(), est_num_outputs, &params);
            let new_change = accumulated_coin - target_coin - new_fee;
            if new_change >= min_ada_for_change {
                added = true;
                break;
            }
        }

        if !added {
            return Err(CardanoError::DustChange {
                residual_lovelace: change_coin,
                min_required: min_ada_for_change,
            });
        }
    }

    // Recompute final fee and change with final input count
    let final_fee = estimate_fee_for_inputs(selected.len(), est_num_outputs, &params);
    let change_coin = accumulated_coin - target_coin - final_fee;

    // Multi-asset change (excess assets that weren't sent to recipients)
    let change_assets: Vec<NativeAsset> = accumulated_assets
        .into_iter()
        .map(|((policy_id, asset_name), qty)| {
            let target_qty = target_assets
                .get(&(policy_id.clone(), asset_name.clone()))
                .copied()
                .unwrap_or(0);
            NativeAsset {
                policy_id,
                asset_name,
                quantity: qty - target_qty,
            }
        })
        .filter(|a| a.quantity > 0)
        .collect();

    // Build change outputs
    let mut change_outputs = Vec::new();

    if change_assets.is_empty() {
        // Pure ADA change only
        if change_coin > 0 {
            change_outputs.push(TxOutput {
                address: change_address.clone(),
                value: Value {
                    coin: change_coin,
                    assets: vec![],
                },
            });
        }
    } else {
        // Multi-asset change: the output MUST carry min-ADA per protocol rules.
        // We deduct it from the pure-ADA change. If pure-ADA change is below
        // min_ada_pure after deduction, absorb it into the multi-asset output instead
        // of creating a dust pure-ADA output.
        //
        // Limitation: if change_coin < min_ada_multi, the TX will be rejected by the
        // ledger. Users must consolidate UTXOs to resolve this.
        let min_ada_multi = estimate_min_ada_for_multi_asset_output(change_assets.len(), &params);

        if change_coin < min_ada_multi {
            return Err(CardanoError::DustChange {
                residual_lovelace: change_coin,
                min_required: min_ada_multi,
            });
        }

        let pure_ada_remainder = change_coin - min_ada_multi;
        if pure_ada_remainder >= min_ada_for_change {
            // Enough for two separate change outputs
            change_outputs.push(TxOutput {
                address: change_address.clone(),
                value: Value {
                    coin: pure_ada_remainder,
                    assets: vec![],
                },
            });
            change_outputs.push(TxOutput {
                address: change_address.clone(),
                value: Value {
                    coin: min_ada_multi,
                    assets: change_assets,
                },
            });
        } else {
            // Pure-ADA remainder is dust; absorb all change_coin into the multi-asset output
            change_outputs.push(TxOutput {
                address: change_address.clone(),
                value: Value {
                    coin: change_coin,
                    assets: change_assets,
                },
            });
        }
    }

    Ok(CoinSelectionResult {
        selected_inputs: selected,
        change_outputs,
        fee: final_fee,
    })
}

/// Aggregate assets from a slice of outputs into a map: (policy_id, asset_name) -> total_quantity.
fn aggregate_assets(outputs: &[TxOutput]) -> HashMap<(String, String), u64> {
    let mut map = HashMap::new();
    for output in outputs {
        for asset in &output.value.assets {
            let key = (asset.policy_id.clone(), asset.asset_name.clone());
            *map.entry(key).or_insert(0) += asset.quantity;
        }
    }
    map
}

/// Estimate the minimum ADA needed for a pure-ADA change output.
/// Uses Babbage formula: coins_per_utxo_byte * (output_cbor_size + 160)
/// For a pure-ADA output, this is roughly 0.97-1.0 ADA.
fn estimate_min_ada(params: &ProtocolParams) -> u64 {
    // Pure ADA output serialization is ~57 bytes; 160 is Babbage overhead
    let output_size = 57u64;
    let base_overhead = 160u64;
    params.coins_per_utxo_byte.saturating_mul(output_size + base_overhead)
}

/// Estimate the minimum ADA needed for a multi-asset output.
/// Conservative estimate based on number of distinct assets.
/// Formula: coins_per_utxo_byte * (output_size + 160)
/// where output_size includes policy map overhead and per-asset CBOR.
fn estimate_min_ada_for_multi_asset_output(num_assets: usize, params: &ProtocolParams) -> u64 {
    // 57B base + 50B policy map overhead + 28B policy id + 10B per (name, qty) pair
    let output_size = 57u64 + 50 + 28 + (num_assets as u64).saturating_mul(10);
    params.coins_per_utxo_byte.saturating_mul(output_size + 160)
}

/// Estimate the transaction fee based on the number of inputs and outputs.
///
/// Accounts for:
/// - Base transaction body (~250B)
/// - Per-input CBOR (~43B) + vkey witness (~100B)
/// - Per-output CBOR (~65B conservative)
fn estimate_fee_for_inputs(num_inputs: usize, num_outputs: usize, params: &ProtocolParams) -> u64 {
    let base_size = 250u64;
    let per_input_size = 43u64;
    let per_witness_size = 100u64; // vkey witness: 32B pk + 64B sig + overhead
    let per_output_size = 65u64;
    let total_size = base_size
        + (num_inputs as u64).saturating_mul(per_input_size + per_witness_size)
        + (num_outputs as u64).saturating_mul(per_output_size);
    params.min_fee_b.saturating_add(params.min_fee_a.saturating_mul(total_size))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_params() -> ProtocolParams {
        ProtocolParams {
            min_fee_a: 44,
            min_fee_b: 155381,
            max_tx_size: 16384,
            coins_per_utxo_byte: 4310,
            pool_deposit: 500000000,
            key_deposit: 2000000,
            max_val_size: 5000,
        }
    }

    /// Helper: create a simple UTXO with just coin.
    fn utxo(tx_hash: &str, output_index: u32, coin: u64) -> TxInput {
        TxInput {
            tx_hash: tx_hash.to_string(),
            output_index,
            address: "addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqq4mj7m3hn8wxssdcn0y3fy".to_string(),
            value: Value {
                coin,
                assets: vec![],
            },
        }
    }

    /// Helper: create an output with just coin.
    fn output(address: &str, coin: u64) -> TxOutput {
        TxOutput {
            address: address.to_string(),
            value: Value {
                coin,
                assets: vec![],
            },
        }
    }

    // Test 1: Single input covers everything
    #[test]
    fn largest_first_single_input_covers() {
        let utxos = vec![utxo("aaa", 0, 5_000_000)];
        let targets = vec![output("addr_recv", 1_000_000)];
        let change_addr = "addr_change".to_string();
        let params = make_params();

        let result = largest_first(utxos, targets, change_addr, params).unwrap();
        assert_eq!(result.selected_inputs.len(), 1);
        assert_eq!(result.selected_inputs[0].tx_hash, "aaa");
        assert!(result.fee > 0);
        // Change should be ~3.8M (5M - 1M - fee)
        assert!(!result.change_outputs.is_empty());
    }

    // Test 2: Multiple inputs needed
    #[test]
    fn largest_first_picks_multiple_inputs() {
        let utxos = vec![
            utxo("ccc", 0, 1_000_000),
            utxo("bbb", 0, 2_000_000),
            utxo("aaa", 0, 3_000_000),
        ];
        let targets = vec![output("addr_recv", 3_500_000)];
        let change_addr = "addr_change".to_string();
        let params = make_params();

        let result = largest_first(utxos, targets, change_addr, params).unwrap();
        // Should pick aaa (3M) + bbb (2M) = 5M, covering 3.5M target + fee + min_change
        assert!(result.selected_inputs.len() >= 2);
        let selected_hashes: Vec<_> = result
            .selected_inputs
            .iter()
            .map(|u| u.tx_hash.as_str())
            .collect();
        assert!(selected_hashes.contains(&"aaa"));
        assert!(selected_hashes.contains(&"bbb"));
    }

    // Test 3: Insufficient funds
    #[test]
    fn largest_first_insufficient_funds() {
        let utxos = vec![utxo("aaa", 0, 1_000_000)];
        let targets = vec![output("addr_recv", 2_000_000)];
        let change_addr = "addr_change".to_string();
        let params = make_params();

        let result = largest_first(utxos, targets, change_addr, params);
        match result {
            Err(CardanoError::InsufficientFunds {
                needed_lovelace,
                available_lovelace,
            }) => {
                assert!(needed_lovelace > available_lovelace);
                assert_eq!(available_lovelace, 1_000_000);
            }
            _ => panic!("Expected InsufficientFunds error"),
        }
    }

    // Test 4: Multi-asset requires asset carrier
    #[test]
    fn largest_first_multi_asset_needs_asset_carrier() {
        let utxo_with_asset = TxInput {
            tx_hash: "bbb".to_string(),
            output_index: 0,
            address: "addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqq4mj7m3hn8wxssdcn0y3fy".to_string(),
            value: Value {
                coin: 3_000_000,
                assets: vec![NativeAsset {
                    policy_id: "29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418"
                        .to_string(),
                    asset_name: "MYTKN".to_string(),
                    quantity: 100,
                }],
            },
        };

        let target_with_asset = TxOutput {
            address: "addr_recv".to_string(),
            value: Value {
                coin: 1_000_000,
                assets: vec![NativeAsset {
                    policy_id: "29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418"
                        .to_string(),
                    asset_name: "MYTKN".to_string(),
                    quantity: 100,
                }],
            },
        };

        let change_addr = "addr_change".to_string();
        let params = make_params();

        let result = largest_first(
            vec![utxo_with_asset],
            vec![target_with_asset],
            change_addr,
            params,
        )
        .unwrap();
        // Must select the asset carrier
        assert_eq!(result.selected_inputs.len(), 1);
        assert_eq!(result.selected_inputs[0].tx_hash, "bbb");
    }

    // Test 5: Change below min-ada pulls more input
    #[test]
    fn largest_first_change_below_min_ada_pulls_more() {
        // We need to construct a scenario where initial selection leaves dust.
        // min_ada_for_output ≈ 988_000 for the params we use.
        let utxos = vec![
            utxo("aaa", 0, 1_000_000), // Too small to be change
            utxo("bbb", 0, 1_000_000), // Another small one
        ];
        let targets = vec![output("addr_recv", 500_000)];
        let change_addr = "addr_change".to_string();
        let params = make_params();

        let result = largest_first(utxos, targets, change_addr, params).unwrap();
        // Should pick both inputs to ensure change > min_ada
        assert_eq!(result.selected_inputs.len(), 2);
        // Verify change >= min_ada
        let total_change_coin: u64 = result.change_outputs.iter().map(|o| o.value.coin).sum();
        let min_ada = estimate_min_ada(&params);
        assert!(total_change_coin >= min_ada);
    }

    // Test 6: Deterministic ordering
    #[test]
    fn largest_first_deterministic_ordering() {
        let params = make_params();
        let change_addr = "addr_change".to_string();

        let utxos1 = vec![
            utxo("aaa", 0, 1_500_000),
            utxo("bbb", 0, 1_000_000),
            utxo("ccc", 0, 2_000_000),
        ];
        let utxos2 = vec![
            utxo("ccc", 0, 2_000_000),
            utxo("aaa", 0, 1_500_000),
            utxo("bbb", 0, 1_000_000),
        ];
        let targets = vec![output("addr_recv", 2_500_000)];

        let result1 =
            largest_first(utxos1, targets.clone(), change_addr.clone(), params).unwrap();
        let result2 = largest_first(utxos2, targets, change_addr, params).unwrap();

        // Should select the same inputs regardless of input order
        assert_eq!(result1.selected_inputs.len(), result2.selected_inputs.len());
        assert_eq!(result1.fee, result2.fee);

        let hashes1: Vec<_> = result1
            .selected_inputs
            .iter()
            .map(|u| u.tx_hash.as_str())
            .collect();
        let hashes2: Vec<_> = result2
            .selected_inputs
            .iter()
            .map(|u| u.tx_hash.as_str())
            .collect();
        // Both should select ccc (2M) + aaa (1.5M) by algorithm
        assert_eq!(hashes1, hashes2);
    }

    // Property test 1: Inputs cover outputs + fee + change
    #[test]
    fn invariant_inputs_cover_outputs_plus_fee() {
        // Seeded deterministic property test
        let params = make_params();
        let change_addr = "addr_change".to_string();

        for seed in 0..10 {
            let utxos = vec![
                utxo(
                    &format!("utxo{}", seed * 3),
                    0,
                    500_000 + seed as u64 * 100_000,
                ),
                utxo(
                    &format!("utxo{}", seed * 3 + 1),
                    0,
                    1_000_000 + seed as u64 * 200_000,
                ),
                utxo(
                    &format!("utxo{}", seed * 3 + 2),
                    0,
                    2_000_000 + seed as u64 * 300_000,
                ),
            ];
            let targets = vec![output("addr_recv", 1_500_000)];

            if let Ok(result) = largest_first(utxos, targets, change_addr.clone(), params) {
                let inputs_sum: u64 = result.selected_inputs.iter().map(|u| u.value.coin).sum();
                let outputs_sum: u64 = result.change_outputs.iter().map(|o| o.value.coin).sum();
                // outputs_sum is change, fee is separate
                // Invariant: inputs_sum == outputs_sum + fee + (sent to recipients)
                // Since our targets only have coin, check: inputs_sum >= outputs_sum + fee + target_sent
                let target_sent = 1_500_000u64;
                let balance_check = outputs_sum + result.fee + target_sent;
                assert_eq!(
                    inputs_sum, balance_check,
                    "seed {}: inputs {} != change {} + fee {} + target {}",
                    seed, inputs_sum, outputs_sum, result.fee, target_sent
                );
            }
        }
    }

    // Test 7: Multi-asset change output carries min-ADA (not coin=0)
    #[test]
    fn multi_asset_change_output_has_min_ada() {
        let params = make_params();
        let policy = "29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418".to_string();
        let asset_name = "MYTKN".to_string();

        // UTXO with 5 ADA and 200 tokens — send 100 tokens, keep 100 as change
        let utxo_with_asset = TxInput {
            tx_hash: "aaa".to_string(),
            output_index: 0,
            address: "addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqq4mj7m3hn8wxssdcn0y3fy".to_string(),
            value: Value {
                coin: 5_000_000,
                assets: vec![NativeAsset {
                    policy_id: policy.clone(),
                    asset_name: asset_name.clone(),
                    quantity: 200,
                }],
            },
        };

        let target = TxOutput {
            address: "addr_recv".to_string(),
            value: Value {
                coin: 1_500_000,
                assets: vec![NativeAsset {
                    policy_id: policy.clone(),
                    asset_name: asset_name.clone(),
                    quantity: 100,
                }],
            },
        };

        let result =
            largest_first(vec![utxo_with_asset], vec![target], "addr_change".to_string(), params)
                .unwrap();

        // Find the multi-asset change output
        let multi_output = result
            .change_outputs
            .iter()
            .find(|o| !o.value.assets.is_empty())
            .expect("should have a multi-asset change output");

        // Must carry non-zero ADA (min-ADA per protocol)
        assert!(
            multi_output.value.coin > 0,
            "multi-asset change output must have non-zero coin, got {}",
            multi_output.value.coin
        );
        assert!(
            multi_output.value.coin >= estimate_min_ada_for_multi_asset_output(1, &make_params()),
            "multi-asset change coin {} below min-ADA {}",
            multi_output.value.coin,
            estimate_min_ada_for_multi_asset_output(1, &make_params())
        );

        // Asset conservation: 200 total − 100 sent = 100 in change
        let change_asset_qty: u64 = result
            .change_outputs
            .iter()
            .flat_map(|o| &o.value.assets)
            .filter(|a| a.policy_id == policy && a.asset_name == asset_name)
            .map(|a| a.quantity)
            .sum();
        assert_eq!(change_asset_qty, 100);

        // Coin conservation: inputs == change + fee + target
        let inputs_sum: u64 = result.selected_inputs.iter().map(|u| u.value.coin).sum();
        let change_sum: u64 = result.change_outputs.iter().map(|o| o.value.coin).sum();
        assert_eq!(inputs_sum, change_sum + result.fee + 1_500_000);
    }

    // Property test 2: No asset lost
    #[test]
    fn invariant_no_asset_lost() {
        let params = make_params();
        let change_addr = "addr_change".to_string();

        for seed in 0..5 {
            let policy = "29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418".to_string();
            let asset_name = format!("TKN{}", seed);

            let utxos = vec![
                TxInput {
                    tx_hash: "aaa".to_string(),
                    output_index: 0,
                    address: "addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqq4mj7m3hn8wxssdcn0y3fy"
                        .to_string(),
                    value: Value {
                        coin: 2_000_000,
                        assets: vec![NativeAsset {
                            policy_id: policy.clone(),
                            asset_name: asset_name.clone(),
                            quantity: 200 + seed as u64 * 10,
                        }],
                    },
                },
                utxo("bbb", 0, 3_000_000),
            ];

            let targets = vec![TxOutput {
                address: "addr_recv".to_string(),
                value: Value {
                    coin: 1_000_000,
                    assets: vec![NativeAsset {
                        policy_id: policy.clone(),
                        asset_name: asset_name.clone(),
                        quantity: 100,
                    }],
                },
            }];

            if let Ok(result) = largest_first(utxos, targets, change_addr.clone(), params) {
                let input_asset_qty: u64 = result
                    .selected_inputs
                    .iter()
                    .flat_map(|u| &u.value.assets)
                    .filter(|a| a.policy_id == policy && a.asset_name == asset_name)
                    .map(|a| a.quantity)
                    .sum();

                let output_asset_qty: u64 = result
                    .change_outputs
                    .iter()
                    .flat_map(|o| &o.value.assets)
                    .filter(|a| a.policy_id == policy && a.asset_name == asset_name)
                    .map(|a| a.quantity)
                    .sum();

                let target_asset_qty = 100u64;
                // Invariant: input_qty == change_qty + target_qty
                assert_eq!(
                    input_asset_qty,
                    output_asset_qty + target_asset_qty,
                    "seed {}: asset not conserved",
                    seed
                );
            }
        }
    }
}
