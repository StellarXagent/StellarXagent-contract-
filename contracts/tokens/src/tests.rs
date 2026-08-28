#![cfg(test)]
extern crate std;

use crate::{MyToken, MyTokenClient};
use soroban_sdk::{
    testutils::{Address as _, MockAuth, MockAuthInvoke},
    Address, Env, IntoVal, String,
};
use stellar_tokens::fungible::Base as TokenBase;

fn setup_env() -> (Env, Address, Address) {
    let env = Env::default();
    let owner = Address::generate(&env);
    let user = Address::generate(&env);
    let contract_id = env.register(
        MyToken,
        (
            owner.clone(),
            String::from_str(&env, "MyToken"),
            String::from_str(&env, "MTK"),
            7u32,
        ),
    );
    (env, contract_id, user)
}

fn setup_env_with_owner() -> (Env, Address, Address, Address) {
    let env = Env::default();
    let owner = Address::generate(&env);
    let user = Address::generate(&env);
    let contract_id = env.register(
        MyToken,
        (
            owner.clone(),
            String::from_str(&env, "MyToken"),
            String::from_str(&env, "MTK"),
            7u32,
        ),
    );
    (env, contract_id, user, owner)
}

fn bind_marketplace(env: &Env, token_id: &Address, owner: &Address, marketplace: &Address) {
    let client = MyTokenClient::new(env, token_id);
    client
        .mock_auths(&[MockAuth {
            address: owner,
            invoke: &MockAuthInvoke {
                contract: token_id,
                fn_name: "set_marketplace",
                args: (marketplace,).into_val(env),
                sub_invokes: &[],
            },
        }])
        .set_marketplace(marketplace);
}

#[test]
fn test_token_mint_and_balance() {
    let (env, contract_id, user) = setup_env();

    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &user, 1000);
    });

    let bal: i128 = env.as_contract(&contract_id, || TokenBase::balance(&env, &user));
    assert_eq!(bal, 1000);

    let supply: i128 = env.as_contract(&contract_id, || TokenBase::total_supply(&env));
    assert_eq!(supply, 1000);
}

#[test]
fn test_token_metadata() {
    let (env, contract_id, ..) = setup_env();
    let client = MyTokenClient::new(&env, &contract_id);

    assert_eq!(client.name(), String::from_str(&env, "MyToken"));
    assert_eq!(client.symbol(), String::from_str(&env, "MTK"));
    assert_eq!(client.decimals(), 7);
}

#[test]
fn test_mint_multiple_same_user() {
    let (env, contract_id, user) = setup_env();

    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &user, 100);
        TokenBase::mint(&env, &user, 200);
        TokenBase::mint(&env, &user, 300);
    });

    let bal: i128 = env.as_contract(&contract_id, || TokenBase::balance(&env, &user));
    assert_eq!(bal, 600);

    let supply: i128 = env.as_contract(&contract_id, || TokenBase::total_supply(&env));
    assert_eq!(supply, 600);
}

#[test]
fn test_mint_to_different_users() {
    let env = Env::default();
    let owner = Address::generate(&env);
    let alice = Address::generate(&env);
    let bob = Address::generate(&env);

    let contract_id = env.register(
        MyToken,
        (
            owner.clone(),
            String::from_str(&env, "MyToken"),
            String::from_str(&env, "MTK"),
            7u32,
        ),
    );

    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &alice, 500);
        TokenBase::mint(&env, &bob, 1500);
    });

    assert_eq!(
        env.as_contract(&contract_id, || TokenBase::balance(&env, &alice)),
        500
    );
    assert_eq!(
        env.as_contract(&contract_id, || TokenBase::balance(&env, &bob)),
        1500
    );
    assert_eq!(
        env.as_contract(&contract_id, || TokenBase::total_supply(&env)),
        2000
    );
}

#[test]
#[should_panic]
fn test_mint_overflow_panics() {
    let (env, contract_id, user) = setup_env();

    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &user, i128::MAX);
    });

    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &user, 1);
    });
}

#[test]
fn test_zero_balance_default() {
    let (env, contract_id, ..) = setup_env();
    let nobody = Address::generate(&env);

    let bal: i128 = env.as_contract(&contract_id, || TokenBase::balance(&env, &nobody));
    assert_eq!(bal, 0);
}

#[test]
fn test_set_marketplace_stores_address() {
    let (env, contract_id, _, owner) = setup_env_with_owner();
    let client = MyTokenClient::new(&env, &contract_id);
    let marketplace = Address::generate(&env);

    bind_marketplace(&env, &contract_id, &owner, &marketplace);

    assert_eq!(client.get_marketplace(), marketplace);
}

#[test]
fn test_set_marketplace_requires_owner() {
    let (env, contract_id, user) = setup_env();
    let client = MyTokenClient::new(&env, &contract_id);
    let marketplace = Address::generate(&env);

    let result = client
        .mock_auths(&[MockAuth {
            address: &user,
            invoke: &MockAuthInvoke {
                contract: &contract_id,
                fn_name: "set_marketplace",
                args: (&marketplace,).into_val(&env),
                sub_invokes: &[],
            },
        }])
        .try_set_marketplace(&marketplace);

    assert!(result.is_err());
}

#[test]
fn test_set_marketplace_cannot_retarget() {
    let (env, contract_id, _, owner) = setup_env_with_owner();
    let client = MyTokenClient::new(&env, &contract_id);
    let first_marketplace = Address::generate(&env);
    let second_marketplace = Address::generate(&env);

    bind_marketplace(&env, &contract_id, &owner, &first_marketplace);

    let result = client
        .mock_auths(&[MockAuth {
            address: &owner,
            invoke: &MockAuthInvoke {
                contract: &contract_id,
                fn_name: "set_marketplace",
                args: (&second_marketplace,).into_val(&env),
                sub_invokes: &[],
            },
        }])
        .try_set_marketplace(&second_marketplace);

    assert!(result.is_err());
    assert_eq!(client.get_marketplace(), first_marketplace);
}

#[test]
fn test_sell_forwarded_fails_without_marketplace_binding() {
    let (env, contract_id, user) = setup_env();
    let client = MyTokenClient::new(&env, &contract_id);

    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &user, 1000);
    });

    let result = client.try_sell_forwarded(&user, &400);

    assert!(result.is_err());
    assert_eq!(client.balance(&user), 1000);
    assert_eq!(client.total_supply(), 1000);
}

#[test]
fn test_sell_forwarded_fails_from_direct_external_call() {
    let (env, contract_id, user, owner) = setup_env_with_owner();
    let client = MyTokenClient::new(&env, &contract_id);
    let marketplace = Address::generate(&env);

    bind_marketplace(&env, &contract_id, &owner, &marketplace);
    env.as_contract(&contract_id, || {
        TokenBase::mint(&env, &user, 1000);
    });

    let result = client.try_sell_forwarded(&user, &400);

    assert!(result.is_err());
    assert_eq!(client.balance(&user), 1000);
    assert_eq!(client.total_supply(), 1000);
}

#[test]
fn test_mint_forwarded_fails_without_marketplace_binding() {
    let (env, contract_id, user) = setup_env();
    let client = MyTokenClient::new(&env, &contract_id);

    let result = client.try_mint_forwarded(&user, &750);

    assert!(result.is_err());
    assert_eq!(client.balance(&user), 0);
    assert_eq!(client.total_supply(), 0);
}

#[test]
fn test_mint_forwarded_fails_from_direct_external_call() {
    let (env, contract_id, user, owner) = setup_env_with_owner();
    let client = MyTokenClient::new(&env, &contract_id);
    let marketplace = Address::generate(&env);

    bind_marketplace(&env, &contract_id, &owner, &marketplace);

    let result = client.try_mint_forwarded(&user, &750);

    assert!(result.is_err());
    assert_eq!(client.balance(&user), 0);
    assert_eq!(client.total_supply(), 0);
}
