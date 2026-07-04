# Plan BB — Store Integrity & Data-Loss Hardening

**Status:** ✅ Shipped ([#157](https://github.com/straff2002/OpenGlasses/pull/157)) — `JSONStore` (backup-on-corrupt, salvage decode, unreadable-state save suppression); PlaybookStore/AgentDocumentStore overwrite fixes; SemanticMemoryStore parameterized SQL + save reporting; encrypted-ConversationStore serialization; same pattern across Teleprompter/Study/SafetyAssessment/Vault stores (`StoreIntegrityTests`).

## The problem
A July 2026 six-track code audit found the persistence layer's biggest risk is not corruption —
every file write is already `.atomic` and the SQLite stores use WAL — but **our own recovery paths
destroying recoverable data**, plus save failures that never reach the user:

1. **PlaybookStore auto-destroys user playbooks on init.** `load()` is `try?`-decode → any decode
   failure (realistic trigger: schema evolution — one new non-optional `Codable` field or unknown
   enum case fails the whole-array decode) leaves `playbooks == []`, and `init` sees empty →
   seeds factory defaults → **saves over the user's data on launch** (`PlaybookStore.swift:689-694`,
   `:260-267`). Custom/edited playbooks, including medical templates, are gone permanently.
2. **AgentDocumentStore clobbers `soul.md`/`memory.md` on a transient read failure.** A thrown read
   (e.g. file protection during a locked-device background launch — glasses reconnect, scheduled
   agent task) is treated as "first run" and the default is written over the real file
   (`AgentDocumentStore.swift:285-294`). `memory.md` is the agent's accumulated learned facts.
3. **SemanticMemoryStore never saves memories containing an apostrophe — while reporting success.**
   The SQL upsert escapes the *value* but interpolates the *key* raw (`SemanticMemoryStore.swift:457-470`;
   same for `deleteMemory`, `fetchEmbedding`, and the namespace at `:153`/`:486`).
   `[REMEMBER: daughter's birthday = June 3]` → SQL syntax error, result discarded, `remember()`
   logs success. `forget` silently no-ops the same way. (`writeMemoryEmbedding` already does it
   right with parameterized statements.)
4. **The silent-decode-empty → save-destroys-the-file amplification pattern** in four more JSON
   stores: `ConversationStore` (`:494-500`), `TeleprompterScriptStore` (`:113-117` — worse:
   `importPendingShares()` in *init* can trigger the destroying save), `StudyStore` (`:59-66`),
   `SafetyAssessmentStore` (`:47-49`).
5. **Encrypted ConversationStore integrity holes:** fire-and-forget detached encrypt Tasks per save
   (out-of-order writes — older snapshot can win), `lock()` clears `threads` with no guard on
   `save()` (a wake-word session while locked encrypts `[newThread]` over the full history), and the
   async encrypted load leaves a `threads == []` window where any save persists empty
   (`ConversationStore.swift:435-441, 449-462, 479-491`).
6. **Save failures propagate nowhere.** Every store `try?`-discards write errors
   (ConversationStore, TeleprompterScriptStore, AgentNotificationQueue, AgentDocumentStore,
   PlaybookStore) and every SQLite `exec`/`step` result is discarded; `BrainStore.openDatabase`
   failure leaves `db = nil` and all brain ops silently no-op **while the spoken reply says "saved"**.
7. Smaller: `VaultStore.append` read-failure clobbers the job log + no actor isolation;
   `SharedTeleprompterInbox` cross-process drain-before-commit race (no `NSFileCoordinator`);
   legacy `user_memories.json` never deleted after migration, so `clearAll()` + relaunch
   **resurrects "forgotten" memories** (privacy failure).

## What we build
One shared, tested persistence helper plus targeted fixes — no store rewrites:

### The deterministic core: `JSONFileStore`
A small helper (`Sources/Services/Persistence/JSONFileStore.swift`) that every JSON store adopts:
- **Backup-before-loss:** on decode failure, rename/copy the blob to `<name>.corrupt-<ISO date>`
  *before* anything can save over it; report `loadResult` as `.corrupt(backupURL)` vs `.absent`
  vs `.loaded(T)` — callers stop conflating "no data yet" with "data I couldn't read".
- **Element-wise array decode** (`FailableDecodable`): one bad element drops that element, not the
  collection.
- **Throwing save** (still `.atomic`), so callers can propagate.

### Targeted fixes
- **PlaybookStore:** seed defaults only on `.absent`; on `.corrupt` keep the backup, surface a
  one-line notice, and start with defaults *without saving* until the user acts.
- **AgentDocumentStore:** distinguish `fileExists` from read-throw; never write defaults after a
  thrown read; treat an intentionally-empty doc as valid.
- **SemanticMemoryStore:** parameterized statements for `upsert`/`deleteMemory`/`fetchEmbedding` and
  namespace binds (copy the `writeMemoryEmbedding` pattern); delete/rename `user_memories.json`
  after successful migration.
- **ConversationStore encrypted mode:** serialize saves (generation counter), `save()` no-ops while
  `isLocked` or before the initial load completes.
- **VaultStore:** distinguish missing-vs-error on `append`'s read; make it an actor (or `@MainActor`
  like every other store).
- **SharedTeleprompterInbox:** `NSFileCoordinator` around load/drain; delete the inbox only after
  the store's save succeeds.
- **Error propagation at the tool boundary:** store `save()` returns/throws; `remember`/`save_note`/
  playbook/study tool paths say "I couldn't save that" instead of lying.

## Scope
In: the helper + the fixes above + tests. Out: any schema changes, new features, iCloud/backup
strategy, encryption-by-default (separate decision).

## Build order
1. `JSONFileStore` + `FailableDecodable` + tests (pure: corrupt blob → backup + `.corrupt`;
   absent → `.absent`; bad element dropped; save error propagates).
2. SemanticMemoryStore parameterized SQL + migration-file cleanup + tests (apostrophe/quote/emoji
   keys round-trip; forget works; migration doesn't resurrect).
3. PlaybookStore + AgentDocumentStore on the helper + tests (corrupt blob survives a relaunch;
   defaults never overwrite; locked-read simulation never clobbers).
4. The four amplification stores on the helper + tests.
5. Encrypted-mode serialization + lock guard + tests.
6. VaultStore/SharedTeleprompterInbox + tool-boundary error surfacing.

## Tests
All headless. Key invariant, asserted per store: **no code path may write over a file whose last
load failed, without first producing a `.corrupt-*` backup.**

## Why this matters
These are the highest-severity findings of the audit: real, silent, permanent user-data loss in the
memory features the product is built around ("brain is native-first"). The fix is one small pure
helper plus mechanical adoption — squarely deterministic-core-first.
