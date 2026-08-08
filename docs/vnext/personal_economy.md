# vNext personal economy

## Scope

This task establishes the first vNext personal-money authority without connecting it to the formal product or to the legacy Alpha economy stack.

- Fixed base: `b2584cdf6cfc5579f20a792826f6acb284164dfb`.
- Runtime type: `VNextPersonalWallet`.
- Snapshot schema: `vnext_personal_wallet_v1`.
- Owned mutable state: `owner_person_id` and `balance_minor` only.
- Money is represented only in integer minor units inside the wallet.

The first version intentionally excludes loans, interest, tax, wages, careers, enterprises, world markets, banks and currency exchange.

## Ownership boundary

A wallet may be created only for a valid vNext stable ID whose kind is `person`. `place:*`, `organization:*`, malformed IDs and other stable-ID kinds are rejected by `VNextPersonalWallet.create()`.

The wallet is the sole owner of its personal balance. This change does not add a wallet registry, `EconomyManager`, `LedgerManager`, context/service-locator object, or a second money owner.

`FormalWorldEconomyService` remains a world-economy authority and is not used as a player-wallet owner. `AlphaLedgerService` remains quarantined legacy code. The reuse inventory classifies both as `REUSE_WITH_ADAPTER`; this task only carries forward already-verified behavioral constraints such as non-negative cash, rejection before mutation and transactional restore. No adapter is connected because doing so in this phase would introduce a second wallet/account authority.

## API

`VNextPersonalWallet` provides:

- `owner_id() -> String`
- `balance_minor() -> int`
- `can_debit(amount_minor: int) -> bool`
- `credit(amount_minor: int) -> bool`
- `debit(amount_minor: int) -> bool`
- `snapshot() -> Dictionary`
- `restore(snapshot_value: Dictionary) -> bool`

A newly created wallet starts at zero balance.

`credit()` accepts only positive integer minor-unit amounts. A successful credit increases the balance. A zero, negative, or overflow credit is rejected without changing state.

`debit()` accepts only positive integer minor-unit amounts when the current balance is sufficient. Insufficient funds, zero amounts and negative amounts are rejected without changing state.

## Integer and JSON contract

The wallet supports balances from `0` through `9_007_199_254_740_991` (`2^53 - 1`). This is the largest integer range that can be preserved exactly through the repository's real Godot JSON number boundary.

Runtime/API money remains `int`. `snapshot()` also emits `balance_minor` as an integer. Godot's JSON parser exposes JSON numbers as `float`; `restore()` therefore accepts an integer-valued finite transport float only after validating that it is non-negative, integral and inside the exact JSON-safe range, and immediately normalizes it back to `int`. Fractional, non-finite, negative and out-of-range values are rejected.

This transport normalization does not create a floating-point wallet state or floating-point money API.

## Snapshot contract

A wallet snapshot has the following fields:

```text
schema_id: "vnext_personal_wallet_v1"
owner_person_id: <valid person stable ID>
balance_minor: <non-negative integer minor units>
```

`restore()` validates the complete candidate before committing either field. Wrong schemas, missing fields, invalid/non-person owners and invalid balances leave the current wallet unchanged.

## Integration status

This PR does not modify `scripts/vnext/world_runtime.gd`, `scripts/vnext/persistence/**`, player-action work, travel work, event work, or the formal product. The wallet is an isolated vNext authority ready for a later composition task once the player/session owner and persistence composition rules are established.

The repository variable-state generators were rerun after adding the wallet. Their mechanically generated audit summary and member inventory are committed with this task and contain no manual ownership reinterpretation.
