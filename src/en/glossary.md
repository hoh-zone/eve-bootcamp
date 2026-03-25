# Glossary

This page provides unified explanations for frequently occurring terms that appear across multiple chapters. When reading Chapters 26-35 and Examples 11-18, use this page as a quick reference guide.

## AdminACL

An authorization control object for server-side access in World contracts. The game server or Builder backend writes approved sponsor addresses into `AdminACL`, and on-chain logic verifies whether the caller has "server representative" identity through validation functions like `verify_sponsor`.

## OwnerCap

An ownership credential for objects or structures. Many World-side permission checks don't just look at `ctx.sender()`, but require the caller to explicitly hold an `OwnerCap` associated with the target object.

## AdminCap

An admin capability object within a Builder's own module. It's typically issued to the publisher during `init` and used to configure settings, modify rules, pause functionality, or withdraw funds.

## Typed Witness

A pattern that uses the type system to tighten authorization boundaries. EVE Frontier's Gate / Turret / Storage Unit extensions often use it to restrict "only specific modules and specific entry points" from calling sensitive APIs.

## Shared Object

A shared object on Sui that can be concurrently accessed by multiple parties. World structures like Gates, Storage Units, and Registries often adopt this model.

## Derived Object

An object ID deterministically derived from a parent object and business key. Scenarios like KillMail and registry sub-objects use this to ensure the `business ID -> on-chain object ID` mapping is stable and non-repeatable.

## Sponsored Transaction

A transaction initiated by a player but with Gas paid by the Builder or server. EVE Vault supports sponsored transaction extensions, which is the core foundation for "users can use dApps without SUI".

## zkLogin

Sui's passwordless login solution. After users complete OAuth login with their Web2 identity, the wallet derives the on-chain address based on ephemeral keys, salt, and proof.

## Epoch

Sui's epoch unit. zkLogin's temporary proofs and certain caches are bound to Epochs, requiring reissuance or login state refresh after expiration.

## `0x6`

The fixed object ID for Sui's `Clock` system object. Many time-related examples in this course pass `0x6` as a parameter.

## `0x8`

The fixed object ID for Sui's `Random` system object. Examples requiring on-chain randomness typically pass this object.

## LUX and SUI

Many examples in this course "use `SUI` instead of `LUX` for demonstration" to facilitate explanation in public environments and with standard SDKs. When actually integrating with EVE Frontier, use the in-game real assets and World/wallet interfaces as the standard.

## GraphQL / Indexer

GraphQL mentioned in this book mostly refers to the query endpoints provided by Sui's indexing layer; Indexer refers to off-chain retrieval services built around events and object state. They are primarily responsible for "reads", not "writes".
