use soroban_sdk::{Address, Env, Executable, MuxedAddress, String};
use stellar_access::ownable;
use stellar_tokens::fungible::Base;

use crate::events::{BurnEvent, MintEvent, SellEvent, TransferEvent};
use crate::storage::types::DataKey;

pub struct TokenManager;

impl TokenManager {
    pub fn initialize(e: &Env, owner: Address, name: String, symbol: String, decimals: u32) {
        Base::set_metadata(e, decimals, name, symbol);
        ownable::set_owner(e, &owner);
    }

    pub fn mint(e: &Env, to: &Address, amount: i128) {
        assert!(amount > 0, "amount must be positive");
        Base::mint(e, to, amount);
        MintEvent {
            admin: ownable::get_owner(e).unwrap(),
            to: to.clone(),
            amount,
        }
        .publish(e);
    }

    pub fn set_marketplace(e: &Env, marketplace: &Address) {
        if e.storage().instance().has(&DataKey::Marketplace) {
            panic!("marketplace already set");
        }
        if marketplace == &e.current_contract_address() {
            panic!("marketplace cannot be this token");
        }
        // G-addresses can satisfy require_auth() by signing, so binding an
        // account would grant unlimited forwarded mint/burn to that key.
        if !matches!(marketplace.executable(), Some(Executable::Wasm(_))) {
            panic!("marketplace must be a deployed contract");
        }

        e.storage()
            .instance()
            .set(&DataKey::Marketplace, marketplace);
    }

    pub fn get_marketplace(e: &Env) -> Address {
        e.storage()
            .instance()
            .get(&DataKey::Marketplace)
            .expect("marketplace not set")
    }

    pub fn transfer(e: &Env, from: &Address, to: &MuxedAddress, amount: i128) {
        Base::transfer(e, from, to, amount);
        TransferEvent {
            from: from.clone(),
            to: to.clone(),
            amount,
        }
        .publish(e);
    }

    pub fn transfer_from(e: &Env, spender: &Address, from: &Address, to: &Address, amount: i128) {
        Base::transfer_from(e, spender, from, to, amount);
    }

    pub fn burn(e: &Env, from: &Address, amount: i128) {
        Base::burn(e, from, amount);
        BurnEvent {
            from: from.clone(),
            amount,
        }
        .publish(e);
    }

    /// Burn tokens from seller's balance. Auth is checked via `seller.require_auth()`.
    /// Use this for direct calls where `sell` is the root invocation.
    ///
    /// Uses `Base::update` directly instead of `Base::burn` to avoid a double
    /// `require_auth` (Base::burn also calls `from.require_auth()`).
    pub fn sell(e: &Env, seller: &Address, amount: i128) {
        assert!(amount > 0, "amount must be positive");
        seller.require_auth();
        Base::update(e, Some(seller), None, amount);
        SellEvent {
            seller: seller.clone(),
            amount,
        }
        .publish(e);
    }

    pub fn sell_forwarded(e: &Env, seller: &Address, amount: i128) {
        Self::require_marketplace(e);
        assert!(amount > 0, "amount must be positive");
        Base::update(e, Some(seller), None, amount);
        SellEvent {
            seller: seller.clone(),
            amount,
        }
        .publish(e);
    }

    pub fn mint_forwarded(e: &Env, to: &Address, amount: i128) {
        Self::require_marketplace(e);
        Self::mint(e, to, amount);
    }

    pub fn require_marketplace(e: &Env) {
        let marketplace = Self::get_marketplace(e);
        // A G-address could satisfy this by signing. set_marketplace therefore
        // rejects non-contracts so only the bound Wasm contract can authorize
        // forwarded mint/burn, typically via authorize_as_current_contract.
        marketplace.require_auth();
    }
}
