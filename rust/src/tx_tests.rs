#[cfg(test)]
mod tests {
    use crate::tx::*;

    fn test_protocol_params() -> ProtocolParams {
        ProtocolParams {
            min_fee_a: 44,
            min_fee_b: 155381,
            coins_per_utxo_byte: 4310,
            max_tx_size: 16384,
            pool_deposit: 500000000,
            key_deposit: 2000000,
            max_val_size: 5000,
        }
    }

    #[test]
    fn test_protocol_params_are_valid() {
        let params = test_protocol_params();
        assert!(params.min_fee_a > 0);
        assert!(params.coins_per_utxo_byte > 0);
    }

    #[test]
    fn test_min_ada_computation_succeeds() {
        let output = TxOutput {
            address: "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld".to_string(),
            value: Value {
                coin: 1000000,
                assets: vec![],
            },
        };
        
        let result = min_ada_for_output(output, 4310);
        assert!(result.is_ok(), "min_ada_for_output failed: {:?}", result);
        let min_ada = result.unwrap();
        assert!(min_ada > 0, "min_ada should be positive");
    }

    #[test]
    fn test_estimate_fee_calculation() {
        let params = test_protocol_params();
        let tx_body_hex = "00".to_string();  // Minimal valid CBOR
        
        let result = estimate_fee(tx_body_hex, 1, params);
        assert!(result.is_ok(), "estimate_fee failed: {:?}", result);
        let fee = result.unwrap();
        assert!(fee > 0, "fee should be positive");
    }
}
