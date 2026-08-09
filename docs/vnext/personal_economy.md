# vNext personal economy

## Scope

This task establishes the first vNext personal-money authority without connecting it to the formal product or to the legacy Alpha economy stack.

- Fixed base: `b2584cdf6cfc5579f20a792826f6acb284164dfb`.
- Runtime type: `VNextPersonalWallet`.
- Snapshot schema: `vnext_personal_wallet_v1`.
- Owned mutable state: `owner_person_id` and `balance_minor` only.
- Money is represented only in integer minor units inside the wallet.

The first version intentionally excludes loans, interest, tax, wages, careers, enterprises, world markets, banks and currency exchange.

## Ownership and validity boundary

`VNextPersonalWallet.create(owner_person_id)` is the formal creation entry point for a usable wallet. It accepts only a valid vNext stable ID whose kind is `person`; `place:*`, `organization:*`, malformed IDs and other stable-ID kinds are rejected.

Direct `VNextPersonalWallet.new()` is intentionally allowed only as an uninitialized shell. A shell starts with an empty owner ID and zero balance and is not a valid wallet until a valid snapshot is restored into it. No business invariant depends on `assert()`, so release/non-debug builds preserve the same validity behavior as debug builds.

`is_valid()` is the explicit runtime validity check. It returns true only when the owned ID is a valid `person` stable ID. `can_debit()`, `credit()` and `debit()` fail closed when `is_valid()` is false, and an invalid shell cannot mutate its balance through those commands.

The wallet is the sole owner of its personal balance. This change does not add a wallet registry, `EconomyManager`, `LedgerManager`, context/service-locator object, or a second money owner.

`FormalWorldEconomyService` remains a world-economy authority and is not used as a player-wallet owner. `AlphaLedgerService` remains quarantined legacy code. The reuse inventory classifies both as `REUSE_WITH_ADAPTER`; this task only carries forward already-verified behavioral constraints such as non-negative cash, rejection before mutation and transactional restore. No adapter is connected because doing so in this phase would introduce a second wallet/account authority.

## API

`VNextPersonalWallet` provides:

- `create(owner_person_id: String) -> VNextPersonalWallet`
- `is_valid() -> bool`
- `owner_id() -> String`
- `balance_minor() -> int`
- `can_debit(amount_minor: int) -> bool`
- `credit(amount_minor: int) -> bool`
- `debit(amount_minor: int) -> bool`
- `snapshot() -> Dictionary`
- `restore(snapshot_value: Dictionary) -> bool`

A wallet returned by `create()` starts at zero balance and is valid immediately. A direct `new()` shell starts invalid and cannot perform money mutations.

`credit()` accepts only positive integer minor-unit amounts on a valid wallet. A successful credit increases the balance. An invalid wallet, zero or negative amount, or overflow is rejected without changing state.

`debit()` accepts only positive integer minor-unit amounts on a valid wallet when the current balance is sufficient. Invalid wallets, insufficient funds, zero amounts and negative amounts are rejected without changing state.

## Integer and JSON contract

The wallet supports balances from `0` through `9_007_199_254_740_991` (`2^53 - 1`). This is the largest integer range that can be preserved exactly through the repository's real Godot JSON number boundary.

Runtime/API money remains `int`. `snapshot()` also emits `balance_minor` as an integer. Godot's JSON parser exposes JSON numbers as `float`; `restore()` therefore accepts an integer-valued finite transport float only after validating that it is non-negative, integral and inside the exact JSON-safe range, and immediately normalizes it back to `int`. Fractional, non-finite, negative and out-of-range values are rejected.

This transport normalization does not create a floating-point wallet state or floating-point money API.

## Snapshot and restore contract

The snapshot shape remains:

```text
schema_id: "vnext_personal_wallet_v1"
owner_person_id: <valid person stable ID>
balance_minor: <non-negative integer minor units>
```

`snapshot()` is a simple projection of current fields. A snapshot from an uninitialized shell contains an empty owner and is therefore not a valid restorable wallet snapshot.

`restore()` validates the complete candidate before committing either field. Wrong schemas, missing fields, invalid/non-person owners and invalid balances leave the current object unchanged. A valid snapshot may be restored into either an already valid wallet or an empty `new()` shell; successful restore makes the shell valid without creating a second owner.

## Integration status

This PR does not modify `scripts/vnext/world_runtime.gd`, `scripts/vnext/persistence/**`, player-action work, travel work, event work, or the formal product. The wallet is an isolated vNext authority ready for a later composition task once the player/session owner and persistence composition rules are established.

The repository variable-state generators are rerun whenever this production file changes. Their mechanically generated audit documents contain no manual ownership reinterpretation.
