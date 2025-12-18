// CVN-1: View Function Tests
// Test module for vault view functions.
#[test_only]
module cvn1_vault::vault_views_tests {
    use std::vector;
    use cvn1_vault::vault_views;
    use cvn1_vault::vault_core;

    // ============================================
    // vault_exists tests
    // ============================================

    #[test]
    fun test_vault_exists_false_for_nonexistent() {
        assert!(!vault_views::vault_exists(@0x999), 0);
    }

    // ============================================
    // get_vault_config tests
    // ============================================

    #[test]
    #[expected_failure(abort_code = 10, location = cvn1_vault::vault_views)]
    fun test_get_vault_config_not_found() {
        let (_, _, _, _) = vault_views::get_vault_config(@0x999);
    }

    // ============================================
    // get_vault_balances tests
    // ============================================

    #[test]
    fun test_get_vault_balances_nonexistent() {
        let balances = vault_core::get_vault_balances(@0x999);
        assert!(vector::is_empty(&balances), 0);
    }

    // ============================================
    // get_vault_info tests
    // ============================================

    #[test]
    #[expected_failure(abort_code = 8, location = cvn1_vault::vault_views)]
    fun test_get_vault_info_not_found() {
        let (_, _) = vault_views::get_vault_info(@0x999);
    }
}
