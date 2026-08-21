# Local-first P2P Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 Flutter 客户端从服务端任务 API 切换为两台 Android 设备之间的本地追加式事件同步，并实现设备身份、事件加密、确定性合并、状态冲突确认和换机撤销。

**Architecture:** 新运行时只依赖 Android 客户端本地 SQLite Event Store。设备通过二维码/短码完成信任，通过局域网或设备热点建立认证会话，双向传输签名事件；物化任务状态可以从事件重建，FastAPI/PostgreSQL 仅作为 Phase 0-3 历史基线。

**Tech Stack:** Flutter 3.47.0、Dart 3.13、Android、Drift/SQLite（drift_flutter）、canonical CBOR、Dart cryptography/cryptography_flutter、Android Keystore、local_auth、mobile_scanner、qr_flutter、dart:io Socket/ServerSocket。首版不增加服务端同步、ECS、Web 完整节点或多人设备拓扑。

**Spec:** docs/superpowers/specs/2026-08-21-local-first-p2p-architecture-design.md

## Global Constraints

- Android 是首版唯一完整节点；每个工作区只有 A、B 两个成员槽位，每位成员同时只有一台 ACTIVE 设备。
- P2P 是唯一任务同步路径；新客户端不得创建 ApiClient、JWT Session、HTTP TaskRepository 或服务端数据依赖。
- SQLite events 表是事实源；事件只追加，不更新、不物理删除；物化表损坏后必须能从有效事件重建。
- 设备签名使用 Ed25519，密钥交换使用 X25519，哈希使用 SHA-256，事件载荷使用 AES-256-GCM，规范编码使用 canonical CBOR。
- 私钥不离开 Android 设备；Android Keystore 保护私钥密文或不可导出的设备保护密钥，本地解锁凭据不进入事件。
- 同一事件只生成一份密文；Event DEK 由 Epoch Key 封装，Epoch Key 分别封装给两台活动设备。
- 每设备维护独立 hash 链；因果上下文使用设备序号向量；created_at 不能用于冲突胜负。
- OPEN 状态冲突只禁止同一任务的后续状态命令，允许普通字段、延期和评论事件继续追加。
- 两台设备都丢失时没有云端恢复；现有 PostgreSQL 任务不自动导入新工作区。
- 每个任务完成一个可测试交付后提交一次独立 Git commit；不要把未相关的旧后端重构混入 P2P 任务。

## Repository Map

新增本地运行时放在 client/lib/local/，职责固定如下：

- client/lib/local/crypto/：规范编码、AEAD、签名、X25519、HKDF 和密钥封装；
- client/lib/local/identity/：设备密钥、成员槽位、工作区、配对和撤销；
- client/lib/local/storage/：Drift 数据库、迁移、Event Store 和同步游标；
- client/lib/local/events/：事件信封、事件工厂、验证和因果上下文；
- client/lib/local/projection/：任务、延期、评论和活动的物化状态；
- client/lib/local/merge/：自动合并、候选集、冲突审批和解决事件；
- client/lib/local/sync/：帧格式、会话状态机、缺失计划、分块和 ACK；
- client/lib/local/transport/：PeerTransport 抽象和局域网/热点实现；
- client/lib/local/presentation/：工作区、配对、同步和冲突控制器。

保留现有 UI 可消费的 client/lib/task/task_repository.dart 抽象，并新增 LocalTaskRepository；HttpTaskRepository 和 auth/core API 文件只作为历史兼容代码保留，运行时注入切换完成后不再被 main.dart 引用。

---

### Task 1: Add Local Runtime Dependencies and Android Boundaries

Files:

- Modify: client/pubspec.yaml
- Modify: client/android/app/src/main/AndroidManifest.xml
- Test: client/test/local/runtime_dependency_test.dart

Interfaces:

- Produces the package and platform baseline consumed by every later task.
- Keeps the existing Flutter SDK and Android compile SDK baseline unchanged.

- [ ] Step 1: Add dependencies without changing application behavior

Run from client:

    flutter pub add cryptography cryptography_flutter drift drift_flutter sqlite3 cbor path path_provider local_auth mobile_scanner qr_flutter
    flutter pub add --dev build_runner drift_dev

Keep pubspec.lock committed. Do not add a cloud SDK, HTTP sync SDK, peer-discovery service, or a second state-management framework.

- [ ] Step 2: Add only the Android permissions required for the first transport

Add camera permission to client/android/app/src/main/AndroidManifest.xml for QR scanning. Keep INTERNET for local TCP sockets. Do not add location, Bluetooth, nearby-device, or cloud permissions in this task because the first transport is local network/hotspot.

- [ ] Step 3: Add a dependency import smoke test

Create client/test/local/runtime_dependency_test.dart:

    import 'package:cryptography/cryptography.dart';
    import 'package:flutter_test/flutter_test.dart';

    void main() {
      test('local runtime exposes the approved cryptography primitives', () {
        expect(AesGcm.with256bits(), isA<Cipher>());
        expect(Ed25519(), isA<SignatureAlgorithm>());
        expect(X25519(), isA<KeyExchangeAlgorithm>());
      });
    }

The test must instantiate AES-GCM, Ed25519 and X25519; use the resolved package's concrete matcher types if a generic analyzer diagnostic requires them.

- [ ] Step 4: Verify the dependency baseline

Run:

    cd client
    dart format --output=none --set-exit-if-changed .
    flutter analyze
    flutter test test/local/runtime_dependency_test.dart

Expected: the existing legacy tests and the new import test pass.

- [ ] Step 5: Commit

    git add client/pubspec.yaml client/pubspec.lock client/android client/test/local/runtime_dependency_test.dart
    git commit -m "build: add local-first p2p dependencies"

### Task 2: Implement Canonical Encoding and Cryptographic Primitives

Files:

- Create: client/lib/local/crypto/crypto_types.dart
- Create: client/lib/local/crypto/canonical_codec.dart
- Create: client/lib/local/crypto/crypto_service.dart
- Create: client/lib/local/crypto/dart_crypto_service.dart
- Test: client/test/local/crypto/canonical_codec_test.dart
- Test: client/test/local/crypto/crypto_service_test.dart

Interfaces:

    final class PublicDeviceKeys {
      const PublicDeviceKeys({
        required this.signingKey,
        required this.exchangeKey,
      });
      final Uint8List signingKey;
      final Uint8List exchangeKey;
    }

    final class EncryptedBlob {
      const EncryptedBlob({
        required this.nonce,
        required this.ciphertext,
        required this.tag,
      });
      final Uint8List nonce;
      final Uint8List ciphertext;
      final Uint8List tag;
    }

    abstract interface class IdentityKeyStore {
      Future<void> create(String alias);
      Future<Uint8List?> readPrivateKey(String alias);
      Future<void> writePrivateKey(String alias, Uint8List value);
      Future<void> delete(String alias);
      Future<bool> exists(String alias);
    }

    abstract interface class CryptoService {
      Future<void> generateIdentity(String keyAlias);
      Future<PublicDeviceKeys> publicKeys(String keyAlias);
      Future<Uint8List> sign(String keyAlias, Uint8List message);
      Future<bool> verify(
        Uint8List publicSigningKey,
        Uint8List message,
        Uint8List signature,
      );
      Future<EncryptedBlob> encrypt(
        Uint8List key,
        Uint8List plaintext, {
        required Uint8List aad,
      });
      Future<Uint8List> decrypt(
        Uint8List key,
        EncryptedBlob blob, {
        required Uint8List aad,
      });
      Future<Uint8List> sealKey(
        Uint8List key,
        Uint8List recipientExchangeKey,
      );
      Future<Uint8List> openKey(
        String keyAlias,
        Uint8List sealedKey,
      );
      Future<Uint8List> sha256(Uint8List bytes);
    }

`DartCryptoService` accepts an `IdentityKeyStore` in its constructor. Task 2 tests use an in-memory implementation; Task 3 supplies the Android Keystore-backed implementation without changing the crypto call sites.

- [ ] Step 1: Write canonical encoding failure tests

Create tests that encode the same map with different insertion order and assert identical bytes, reject unsupported floating-point values, and round-trip byte strings, lists, maps, strings, integers and booleans.

    test('canonical map ordering is stable', () {
      final first = codec.encode({'b': 2, 'a': 1});
      final second = codec.encode({'a': 1, 'b': 2});
      expect(first, orderedEquals(second));
    });

- [ ] Step 2: Implement canonical CBOR boundary

CanonicalCodec must expose encode(Object value) -> Uint8List and decode(Uint8List bytes) -> Object. Normalize map keys to UTF-8 byte ordering, reject NaN/infinity, preserve byte strings, and never encode a DateTime implicitly; event factories pass UTC ISO strings or integer microseconds explicitly.

- [ ] Step 3: Write cryptographic vector tests

Cover AES-GCM round trip with AAD, authentication failure after one-byte ciphertext/AAD changes, Ed25519 signature verification and rejection, X25519 shared-key agreement, HKDF-derived equal keys, and SHA-256 output length.

- [ ] Step 4: Implement DartCryptoService

Use package:cryptography only through DartCryptoService and include `cryptography_flutter` so supported Android primitives use platform-backed implementations. Generate random 256-bit DEKs and Epoch keys from a cryptographically secure source, use a fresh AES-GCM nonce per encryption, and keep raw key bytes behind the service boundary. The service must never derive a data key from a task ID, timestamp, device sequence, login password or user ID.

- [ ] Step 5: Run focused verification

    cd client
    dart format --output=none --set-exit-if-changed lib/local/crypto test/local/crypto
    flutter test test/local/crypto
    flutter analyze

Expected: all vector tests pass and no UI/API code imports package:cryptography directly.

- [ ] Step 6: Commit

    git add client/lib/local/crypto client/test/local/crypto
    git commit -m "feat: add local crypto primitives and canonical encoding"

### Task 3: Add Android Keystore and Local Unlock Adapters

Files:

- Create: client/lib/local/identity/device_key_store.dart
- Create: client/lib/local/identity/local_unlock.dart
- Modify: client/lib/local/crypto/dart_crypto_service.dart
- Create: client/android/app/src/main/kotlin/com/muyu/app/keystore/KeystoreBridge.kt
- Modify: client/android/app/src/main/kotlin/com/muyu/app/MainActivity.kt
- Test: client/test/local/identity/device_key_store_test.dart
- Test: client/test/local/identity/local_unlock_test.dart
- Test: client/integration_test/keystore_test.dart

Interfaces:

    abstract interface class DeviceKeyStore implements IdentityKeyStore {
      Future<void> create(String alias);
      Future<Uint8List?> readPrivateKey(String alias);
      Future<void> writePrivateKey(String alias, Uint8List value);
      Future<void> delete(String alias);
      Future<bool> exists(String alias);
    }

    abstract interface class LocalUnlock {
      Future<bool> authenticate(String reason);
    }

The MethodChannel name is muyu/keystore. KeystoreBridge owns the Android Keystore AES wrapping key and never returns it to Dart. Private-key bytes are returned to the Dart crypto service only after local unlock and remain in process memory; the bridge exposes no wrapping key and no private-key persistence outside its encrypted blob.

- [ ] Step 1: Write fake adapter tests

Verify create/read/write/delete behavior, missing alias behavior, and that LocalUnlock returns false without mutating key material when authentication is canceled.

- [ ] Step 2: Implement the platform channel

Create a non-exportable Android Keystore AES key per device alias. The bridge encrypts/decrypts the Dart-generated private key blob with AES-GCM and returns nonce/ciphertext/tag. Use local_auth for user presence where the platform supports PIN, passcode, pattern or biometric confirmation; cancellation is a normal failure, not a data reset.

- [ ] Step 3: Connect Dart adapters to CryptoService

DartCryptoService must receive a key alias and ask DeviceKeyStore/KeystoreBridge for operations instead of exposing private key bytes to callers. `generateIdentity(alias)` creates the Ed25519 and X25519 pairs and writes their private material through DeviceKeyStore, whose Android implementation encrypts it before persistence; `publicKeys(alias)` derives public material only after local unlock, and Task 4 persists public keys plus the alias in the trusted-device table. Deleting an alias removes the device identity and requires pairing again.

- [ ] Step 4: Add Android integration coverage

integration_test/keystore_test.dart must create an alias, write a sentinel private-key value, read it back after unlock, delete it, and assert that deleted aliases cannot be read. Run on an Android emulator or device; do not treat a host fake as Android Keystore coverage.

- [ ] Step 5: Verify builds

    cd client
    flutter test test/local/identity
    flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8090

Expected: the debug APK builds with the bridge and legacy API define remains ignored by the local runtime.

- [ ] Step 6: Commit

    git add client/lib/local/crypto/dart_crypto_service.dart client/lib/local/identity client/android/app/src/main/kotlin/com/muyu/app/keystore client/android/app/src/main/kotlin/com/muyu/app/MainActivity.kt client/integration_test client/test/local/identity
    git commit -m "feat: protect device identity with android keystore"

### Task 4: Create the Local SQLite Schema and Event Store

Files:

- Create: client/lib/local/storage/tables.dart
- Create: client/lib/local/storage/app_database.dart
- Create: client/lib/local/storage/database_provider.dart
- Create: client/lib/local/storage/event_store.dart
- Create: client/lib/local/storage/drift_converters.dart
- Create: client/lib/local/events/causal_context.dart
- Create: client/lib/local/events/event_envelope.dart
- Create: client/lib/local/sync/sync_cursor.dart
- Create: client/test/local/storage/app_database_test.dart
- Create: client/test/local/storage/event_store_test.dart
- Generate: client/lib/local/storage/app_database.g.dart

Interfaces:

    final class CausalContext {
      const CausalContext(this.sequences);
      final Map<String, int> sequences;
      bool isAncestorOf(CausalContext other);
      bool isConcurrentWith(CausalContext other);
      Uint8List toCanonicalBytes();
    }

    final class EventEnvelope {
      const EventEnvelope({
        required this.workspaceId,
        required this.eventId,
        required this.memberId,
        required this.originDeviceId,
        required this.eventType,
        required this.schemaVersion,
        required this.deviceSequence,
        required this.previousHash,
        required this.causalContext,
        required this.epochId,
        required this.nonce,
        required this.encryptedDek,
        required this.ciphertext,
        required this.ciphertextHash,
        required this.createdAt,
        required this.signature,
      });
      final String workspaceId;
      final String eventId;
      final String memberId;
      final String originDeviceId;
      final String eventType;
      final int schemaVersion;
      final int deviceSequence;
      final Uint8List? previousHash;
      final CausalContext causalContext;
      final int epochId;
      final Uint8List nonce;
      final Uint8List encryptedDek;
      final Uint8List ciphertext;
      final Uint8List ciphertextHash;
      final DateTime createdAt;
      final Uint8List signature;
    }

    abstract interface class EventStore {
      Future<bool> containsEvent(String eventId);
      Future<void> appendVerified(EventEnvelope event);
      Future<EventEnvelope?> event(String eventId);
      Future<List<EventEnvelope>> eventsForDevice(
        String deviceId, {
        required int afterSequence,
      });
      Future<List<EventEnvelope>> allEvents();
      Future<void> saveSyncCursor(SyncCursor cursor);
      Future<SyncCursor?> syncCursor(String deviceId);
    }

    final class SyncCursor {
      const SyncCursor({
        required this.deviceId,
        required this.acknowledgedSequence,
        required this.acknowledgedEventId,
      });
      final String deviceId;
      final int acknowledgedSequence;
      final String acknowledgedEventId;
    }

`appendVerified` is called only after `EventVerifier` has accepted the envelope; the store still enforces event identity, chain uniqueness and hash idempotency inside its transaction.

Drift tables must cover events, epoch keys, trusted devices, sync state, conflicts, conflict approvals, task projections, delay projections and member profiles. Store binary values as BLOBs, timestamps as UTC integer microseconds, and causal contexts as canonical CBOR blobs.

- [ ] Step 1: Write migration and constraint tests

Assert schema version 1 opens on a new file, event_id is unique, device_id plus device_sequence is unique, a conflict approval is unique per conflict/member, and deleting a projection row does not delete an event row.

- [ ] Step 2: Define Drift tables and converters

Keep encrypted event columns separate from projection columns. Event rows must include workspace ID, event ID, member ID, origin device ID, event type, schema version, device sequence, previous hash, causal context, epoch ID, nonce, encrypted DEK, ciphertext (AES-GCM ciphertext concatenated with its tag), ciphertext hash, created timestamp, signature, and verification state.

- [ ] Step 3: Implement AppDatabase and migration hooks

Use a single database provider per app process. Open the native database with `drift_flutter` and inject an in-memory executor for unit tests. Expose a transaction callback so append plus projection updates can be committed atomically later. Set schemaVersion to 1 and keep the migration object ready for future versions; do not create a migration for the old PostgreSQL schema.

- [ ] Step 4: Implement EventStore idempotency

appendVerified must return without mutation when the same event ID and envelope hash already exist, reject the same event ID with a different hash, and reject a duplicate device sequence with a different event ID. Do not update a verified event in place.

- [ ] Step 5: Run database tests and generate code

    cd client
    dart run build_runner build --delete-conflicting-outputs
    flutter test test/local/storage
    flutter analyze

- [ ] Step 6: Commit

    git add client/lib/local/storage client/lib/local/events/causal_context.dart client/lib/local/events/event_envelope.dart client/lib/local/sync/sync_cursor.dart client/test/local/storage client/pubspec.lock
    git commit -m "feat: add local sqlite event store"

### Task 5: Implement Event Payloads, Codec and Verification

Files:

- Create: client/lib/local/events/event_payloads.dart
- Create: client/lib/local/events/event_codec.dart
- Create: client/lib/local/events/event_factory.dart
- Create: client/lib/local/events/event_verifier.dart
- Test: client/test/local/events/causal_context_test.dart
- Test: client/test/local/events/event_codec_test.dart
- Test: client/test/local/events/event_verifier_test.dart

Interfaces:

Task 4 provides the `CausalContext`, `EventEnvelope` and `SyncCursor` value objects consumed here. This task adds payload types, envelope encoding, event creation and verification behavior.

    abstract interface class EventFactory {
      Future<EventEnvelope> create({
        required String eventType,
        required Map<String, Object?> payload,
        String? deterministicEventId,
      });
    }

    abstract interface class EventVerifier {
      Future<VerifiedEvent> verify(EventEnvelope event);
    }

    final class VerifiedEvent {
      const VerifiedEvent({required this.envelope, required this.payload});
      final EventEnvelope envelope;
      final Map<String, Object?> payload;
    }

- [ ] Step 1: Write causal relation tests

Cover empty context, same-device ancestor, cross-device concurrent contexts, merged contexts, sequence gaps, and deterministic serialized ordering. The candidate set hash must sort event IDs lexicographically before hashing.

- [ ] Step 2: Write envelope codec tests

Round-trip every envelope field through canonical CBOR, reject missing required fields, reject negative device sequences, reject malformed byte lengths, and assert that changing any signed field changes the signature input bytes.

- [ ] Step 3: Implement EventFactory

On each local event, read the current device sequence and previous hash, snapshot the known causal context, choose a cryptographically random event ID unless `deterministicEventId` is provided for an idempotent protocol event, canonical-encode the payload, generate a random event DEK, encrypt the payload with AES-GCM and header AAD, concatenate the ciphertext and authentication tag into the envelope ciphertext field, encrypt the DEK with the current Epoch Key into `encryptedDek`, hash the full ciphertext field, and sign the canonical envelope. `sealKey`/`openKey` are reserved for Epoch-key envelopes addressed to device exchange keys.

- [ ] Step 4: Implement EventVerifier

Verify workspace membership, known origin device, sequence continuity, previous hash, signature, ciphertext hash and allowed schema version before decrypting the DEK. Return a VerifiedEvent containing the envelope and decrypted payload; malformed or unauthorized events return typed verification errors and never reach the projection.

- [ ] Step 5: Test tamper and replay behavior

Add tests for changed workspace ID, device ID, sequence, previous hash, ciphertext, encrypted DEK and signature; add duplicate replay tests that prove EventStore remains unchanged.

- [ ] Step 6: Commit

    git add client/lib/local/events client/test/local/events
    git commit -m "feat: add signed encrypted event envelopes"

### Task 6: Implement Workspace, Pairing and Device Replacement Domain

Files:

- Create: client/lib/local/identity/workspace_models.dart
- Create: client/lib/local/identity/pairing_invite.dart
- Create: client/lib/local/identity/pairing_service.dart
- Create: client/lib/local/identity/trusted_device_service.dart
- Create: client/lib/local/identity/epoch_key_service.dart
- Create: client/lib/local/projection/member_projection.dart
- Test: client/test/local/identity/pairing_service_test.dart
- Test: client/test/local/identity/trusted_device_service_test.dart
- Test: client/test/local/identity/epoch_key_service_test.dart
- Test: client/test/local/projection/member_projection_test.dart

Interfaces:

    enum MemberSlot { a, b }

    enum DeviceTrust { pending, active, revoked }

    final class PairingInvite {
      const PairingInvite({
        required this.workspaceId,
        required this.inviteNonce,
        required this.inviterDeviceId,
        required this.payload,
      });
      final String workspaceId;
      final Uint8List inviteNonce;
      final String inviterDeviceId;
      final Uint8List payload;
    }

    final class WorkspaceSnapshot {
      const WorkspaceSnapshot({
        required this.hasWorkspace,
        required this.workspaceId,
        required this.localDeviceId,
        required this.hasActivePeer,
        required this.locked,
      });
      final bool hasWorkspace;
      final String? workspaceId;
      final String? localDeviceId;
      final bool hasActivePeer;
      final bool locked;
    }

    final class TrustedDevice {
      const TrustedDevice({
        required this.deviceId,
        required this.memberId,
        required this.slot,
        required this.publicKeys,
        required this.trust,
      });
      final String deviceId;
      final String memberId;
      final MemberSlot slot;
      final PublicDeviceKeys publicKeys;
      final DeviceTrust trust;
    }

    final class EpochKeyEnvelope {
      const EpochKeyEnvelope({
        required this.epochId,
        required this.deviceId,
        required this.sealedKey,
      });
      final int epochId;
      final String deviceId;
      final Uint8List sealedKey;
    }

    abstract interface class TrustedDeviceService {
      Future<List<TrustedDevice>> activeDevices();
      Future<TrustedDevice?> find(String deviceId);
      Future<void> applyLifecycleEvent(VerifiedEvent event);
    }

    abstract interface class EpochKeyService {
      Future<int> currentEpochId();
      Future<Uint8List> currentEpochKey();
      Future<void> rotate(Iterable<TrustedDevice> recipients);
      Future<void> rewrapHistoryFor(TrustedDevice device);
    }

EpochKeyService returns raw Epoch bytes only to the unlocked local crypto service; SQLite stores only sealed envelopes and never a plaintext Epoch key.

    abstract interface class WorkspaceService {
      Future<WorkspaceSnapshot> restore();
      Future<WorkspaceSnapshot> createWorkspace();
    }

    class LocalWorkspaceService implements WorkspaceService {
      LocalWorkspaceService({
        required EventFactory eventFactory,
        required EventVerifier eventVerifier,
        required EventStore eventStore,
        required TrustedDeviceService trustedDevices,
        required EpochKeyService epochs,
      });
    }

    abstract interface class PairingService {
      Future<PairingInvite> createInvite();
      Future<void> acceptInvite(PairingInvite invite, MemberSlot slot);
      Future<void> approveReplacement(PairingInvite invite, MemberSlot slot);
      Future<void> revokeDevice(String deviceId);
    }

    class LocalPairingService implements PairingService {
      LocalPairingService({
        required EventFactory eventFactory,
        required EventVerifier eventVerifier,
        required EventStore eventStore,
        required TrustedDeviceService trustedDevices,
        required EpochKeyService epochs,
      });
    }

The service writes WorkspaceGenesis, MemberJoined, DeviceAdded, DeviceReplaced, DeviceRevoked and EpochRotated events. It is the only service allowed to change the trusted device table or active member slot.

- [ ] Step 1: Write topology tests

Assert A can create a workspace, B can join after short-code confirmation, a third member is rejected, a second ACTIVE device for one member is rejected, and all pairing writes are rolled back on a failed signature.

- [ ] Step 2: Write replacement and revocation tests

Create A1/B1, replace A1 with A2 after B approval, assert A1 is REVOKED, assert A2 receives old Epoch envelopes and the new Epoch, and assert a revoked A1 cannot authenticate or receive future keys.

- [ ] Step 3: Implement invite validation

Use a random single-use nonce, workspace ID, inviter public keys, endpoint metadata and protocol version. Require manual short-code equality before accepting. Never put private keys, plaintext task fields or Epoch key bytes in the invite.

- [ ] Step 4: Implement Epoch key lifecycle

Persist every Epoch key envelope needed to read retained history. On replacement, re-seal historical Epoch keys and generate a new Epoch for future events. Keep old Epochs available to trusted devices; do not implement key garbage collection.

Apply member and device lifecycle events to the member projection in the same transaction as the Event Store write so AccountScreen can rebuild member names, slots and trust state from events.

- [ ] Step 5: Verify domain state

    cd client
    flutter test test/local/identity/pairing_service_test.dart test/local/identity/trusted_device_service_test.dart test/local/identity/epoch_key_service_test.dart test/local/projection/member_projection_test.dart

- [ ] Step 6: Commit

    git add client/lib/local/identity client/lib/local/projection/member_projection.dart client/test/local/identity client/test/local/projection/member_projection_test.dart
    git commit -m "feat: add workspace pairing and device lifecycle"

### Task 7: Build the Local Task Projection and Repository

Files:

- Create: client/lib/local/projection/task_projection.dart
- Create: client/lib/local/projection/task_commands.dart
- Create: client/lib/local/projection/task_read_model.dart
- Create: client/lib/local/merge/merge_models.dart
- Create: client/lib/local/repositories/local_task_repository.dart
- Modify: client/lib/models/task.dart
- Modify: client/lib/task/task_repository.dart
- Modify: client/lib/task/task_controller.dart
- Test: client/test/local/projection/task_projection_test.dart
- Test: client/test/local/repositories/local_task_repository_test.dart
- Modify: client/test/support/fake_task_repository.dart

Interfaces:

    enum ConflictStatus { open, resolved, superseded }

    final class StatusCandidate {
      const StatusCandidate({
        required this.eventId,
        required this.status,
        required this.payload,
      });
      final String eventId;
      final String status;
      final Map<String, Object?> payload;
    }

    final class TargetTaskState {
      const TargetTaskState({
        required this.status,
        this.blockedReason,
        this.resumeHandlerId,
        this.waitingForUserId,
      });
      final String status;
      final String? blockedReason;
      final String? resumeHandlerId;
      final String? waitingForUserId;
    }

    final class TaskConflict {
      const TaskConflict({
        required this.id,
        required this.taskId,
        required this.baseFrontierHash,
        required this.candidateEventIds,
        required this.candidates,
        required this.status,
      });
      final String id;
      final String taskId;
      final Uint8List baseFrontierHash;
      final List<String> candidateEventIds;
      final List<StatusCandidate> candidates;
      final ConflictStatus status;
    }

    final class TaskConflictFailure extends TaskFailure {
      const TaskConflictFailure(this.conflict)
          : super('该任务存在未解决的状态冲突');
      final TaskConflict conflict;
    }

    class LocalTaskRepository implements TaskRepository {
      LocalTaskRepository({
        required EventFactory eventFactory,
        required EventVerifier eventVerifier,
        required EventStore eventStore,
        required TaskProjection projection,
      });
    }

Keep the existing TaskRepository method names so the current TaskController and task screens can be migrated incrementally. Remove HTTP status_version assumptions from the interface. TaskItem gains pendingConflictId, localCandidateStatus and projectionFrontier fields; statusVersion is no longer used for writes.

- [ ] Step 1: Write projection tests from events only

Cover TaskCreated, TaskFieldPatched, assignee add/remove, TaskDelayRecorded, TaskStatusChanged, TaskCommentAdded and TaskDeleted. Delete and recreate the projection from the same events and assert equal TaskItem values.

- [ ] Step 2: Implement TaskProjection

Apply valid event payloads to task read models. Store the last confirmed status separately from a local candidate and conflict flag. Keep delay history and activity history append-only. Enforce the existing domain rules for one-level subtasks, assignee/handler consistency, WAITING payloads and delay reasons.

- [ ] Step 3: Implement LocalTaskRepository reads and additive commands

list/get read from projection. create/update/transfer/delay/block/unblock/delete create signed events through EventFactory, verify them with EventVerifier, and append them through EventStore. Append the verified event and apply its projection update in one local transaction; replay the event after a projection failure. Do not mutate a projection directly from a repository method. Start/complete/reopen/cancel create TaskStatusChanged and raise TaskConflictFailure when the task has an OPEN conflict.

- [ ] Step 4: Update task model and controller error flow

Parse local projection values instead of API JSON. TaskController stores the typed conflict from TaskConflictFailure, keeps the current task list on failure, and exposes clearConflict() after a resolution refresh.

- [ ] Step 5: Run focused repository tests

    cd client
    flutter test test/local/projection test/local/repositories test/task/task_controller_test.dart
    flutter analyze

- [ ] Step 6: Commit

    git add client/lib/local/projection client/lib/local/repositories client/lib/models/task.dart client/lib/task client/test/local/projection client/test/local/repositories client/test/task/task_controller_test.dart client/test/support/fake_task_repository.dart
    git commit -m "feat: expose local task projection repository"

### Task 8: Implement Deterministic Merge and Conflict Resolution

Files:

- Create: client/lib/local/merge/merge_engine.dart
- Create: client/lib/local/merge/conflict_resolver.dart
- Create: client/lib/local/merge/conflict_events.dart
- Create: client/lib/local/repositories/local_conflict_repository.dart
- Modify: client/lib/local/projection/task_projection.dart
- Test: client/test/local/merge/merge_engine_test.dart
- Test: client/test/local/merge/conflict_resolver_test.dart

Interfaces:

Task 7 provides `ConflictStatus`, `StatusCandidate`, `TargetTaskState` and `TaskConflict`; this task adds deterministic merge behavior and conflict events.

    final class MergeReport {
      const MergeReport({required this.changed, required this.conflict});
      final bool changed;
      final TaskConflict? conflict;
    }

    abstract interface class MergeEngine {
      Future<MergeReport> ingest(VerifiedEvent event);
      Future<TaskConflict?> openConflict(String taskId);
    }

    abstract interface class ConflictResolver {
      Future<void> approve(
        String conflictId,
        TargetTaskState target,
      );
      Future<void> resolveIfBothApproved(String conflictId);
    }

    abstract interface class ConflictRepository {
      Future<List<TaskConflict>> open();
      Future<TaskConflict> get(String conflictId);
      Future<TaskConflict> approve(String conflictId, TargetTaskState target);
    }

    class LocalConflictRepository implements ConflictRepository {
      LocalConflictRepository({
        required ConflictResolver resolver,
        required EventVerifier eventVerifier,
        required EventStore eventStore,
      });
    }

- [ ] Step 1: Write permutation tests

Feed the same event set in every order and assert the same materialized state, event count, candidate set hash and conflict ID. Test additive events, ordinary field tie-breaks, and concurrent status events separately.

- [ ] Step 2: Implement automatic merge rules

Use causal contexts for ancestor/concurrent classification. Deduplicate by event ID, retain all additive events, merge field operations deterministically, and keep losing concurrent field values in activity history.

- [ ] Step 3: Implement conflict candidate sets

For a task, candidate IDs are sorted lexicographically before hashing. conflict_id is derived from task ID, common frontier hash and sorted candidate IDs. Store the last shared status and all complete candidate payloads. An OPEN conflict blocks new known status commands for that task.

- [ ] Step 4: Implement approval and resolution events

ConflictApproval binds conflict ID, candidate set hash, target state hash and complete WAITING payload. When both member approvals match, create one deterministic ConflictResolved event containing both approval event IDs and signatures. If a newer candidate set appears, invalidate old approvals. Create ConflictSuperseded with superseded conflict IDs when a newer candidate frontier explicitly covers an old conflict.

- [ ] Step 5: Add convergence and invalid-target tests

Test different target approvals remain OPEN, equal target approvals resolve exactly once, a target with an invalid state transition is rejected, a WAITING target replays blocked_reason/resume_handler_id/waiting_for_user_id, and a resolution whose target already equals the shared state does not duplicate a status event.

- [ ] Step 6: Commit

    git add client/lib/local/merge client/lib/local/repositories/local_conflict_repository.dart client/lib/local/projection/task_projection.dart client/test/local/merge
    git commit -m "feat: add deterministic local conflict resolution"

### Task 9: Implement Local Network Transport and Sync Session

Files:

- Create: client/lib/local/transport/peer_transport.dart
- Create: client/lib/local/transport/local_network_transport.dart
- Create: client/lib/local/sync/sync_frames.dart
- Create: client/lib/local/sync/sync_session.dart
- Test: client/test/local/transport/local_network_transport_test.dart
- Test: client/test/local/sync/sync_session_test.dart

Interfaces:

    final class PeerEndpoint {
      const PeerEndpoint({
        required this.host,
        required this.port,
        required this.token,
      });
      final String host;
      final int port;
      final Uint8List token;
    }

    abstract interface class PeerConnection {
      Stream<Uint8List> get frames;
      Future<void> send(Uint8List frame);
      Future<void> close();
    }

    final class SyncReport {
      const SyncReport({
        required this.sentEvents,
        required this.receivedEvents,
        required this.committedCursor,
      });
      final int sentEvents;
      final int receivedEvents;
      final SyncCursor committedCursor;
    }

    enum SyncPhase {
      discover,
      authenticate,
      exchangeHeads,
      planMissingEvents,
      transferBidirectional,
      verifyAndCommit,
      merge,
      ack,
      done,
    }

    abstract interface class PeerTransport {
      Future<PeerEndpoint> listen(PairingInvite invite);
      Future<PeerConnection> connect(PairingInvite invite);
      Future<void> close();
    }

    abstract interface class SyncSession {
      Stream<SyncPhase> get phases;
      Future<SyncReport> run(PeerConnection connection);
    }

    enum SyncFrameType {
      hello,
      heads,
      request,
      eventChunk,
      ack,
      commit,
      error,
    }

    final class SyncFrame {
      const SyncFrame({
        required this.type,
        required this.counter,
        required this.encryptedPayload,
      });
      final SyncFrameType type;
      final int counter;
      final Uint8List encryptedPayload;
    }

    abstract interface class SyncFrameCodec {
      Uint8List encode(SyncFrame frame);
      SyncFrame decode(Uint8List bytes);
    }

- [ ] Step 1: Write fake-session tests

Use an in-memory transport to assert DISCOVER, AUTHENTICATE, EXCHANGE_HEADS, PLAN_MISSING_EVENTS, TRANSFER_BIDIRECTIONAL, VERIFY_AND_COMMIT, MERGE, ACK and DONE transitions. Assert unsupported protocol, workspace mismatch, revoked device, bad signature and missing key produce stable typed errors without projection writes.

- [ ] Step 2: Implement LocalNetworkTransport

Use dart:io ServerSocket/Socket. The invite contains a single-use endpoint token; the listener advertises an IPv4 local endpoint, and the scanner device connects using the QR payload. Keep discovery and framing behind PeerTransport so a future Nearby implementation does not touch sync logic.

- [ ] Step 3: Implement authenticated session framing

Exchange protocol version, workspace ID, device IDs, long-term public keys, ephemeral X25519 keys and signatures over the pairing nonce plus transcript. Derive directional session keys with HKDF-SHA256 and encrypt frames with AES-GCM using a monotonically increasing counter nonce. Reject replayed counters and transcript changes.

- [ ] Step 4: Implement missing-event planning and resumable transfer

Exchange per-device heads and acknowledged cursors. Send event IDs/headers first, request missing event IDs, transfer bounded chunks with chunk hash, append and verify each chunk transactionally, then ACK. If a received chain has a sequence gap, quarantine it and request the missing predecessor before acknowledging. Persist the last acknowledged cursor before sending COMMIT.

- [ ] Step 5: Add socket and interruption tests

Run two loopback ServerSocket nodes, transfer duplicate and out-of-order events, close the socket after a partial chunk, reconnect, and assert only unacknowledged events retransmit. Verify a corrupt chunk enters quarantine and does not alter projection.

- [ ] Step 6: Commit

    git add client/lib/local/transport client/lib/local/sync client/test/local/transport client/test/local/sync
    git commit -m "feat: add resumable local p2p sync"

### Task 10: Add Workspace Controller, Pairing UI and Sync UI

Files:

- Create: client/lib/local/presentation/workspace_controller.dart
- Create: client/lib/screens/workspace_setup_screen.dart
- Create: client/lib/screens/pairing_screen.dart
- Create: client/lib/screens/sync_screen.dart
- Modify: client/lib/app.dart
- Modify: client/lib/main.dart
- Modify: client/lib/screens/main_shell.dart
- Test: client/test/local/presentation/workspace_controller_test.dart
- Test: client/test/widget/pairing_screen_test.dart
- Test: client/test/widget/sync_screen_test.dart

Interfaces:

    enum WorkspaceStatus {
      loading,
      needsWorkspace,
      needsPairing,
      locked,
      ready,
      failure,
    }

    class WorkspaceController extends ChangeNotifier {
      WorkspaceController({
        required WorkspaceService workspace,
        required PairingService pairing,
        required LocalUnlock unlock,
        required PeerTransport transport,
        required SyncSession sync,
      });
      WorkspaceStatus status;
      Future<void> restore();
      Future<void> createWorkspace();
      Future<void> acceptInvite(String rawInvite);
      Future<void> approvePairing();
      Future<void> syncNow();
    }

- [ ] Step 1: Write controller state tests

Cover first launch, create workspace, pending pairing, successful approval, local unlock cancellation, sync success, sync interruption, revoked peer, and permanent workspace failure. State transitions must not expose private keys or plaintext event payloads in error strings.

- [ ] Step 2: Implement WorkspaceController

Open the local database, load identity/trusted-device state, require local unlock, and route create/pair/approve/sync commands to domain services. Keep the legacy SessionController unused by the new main entrypoint.

- [ ] Step 3: Implement pairing screens

workspace_setup_screen.dart presents Create Workspace and Join Existing Workspace. pairing_screen.dart renders the invite QR, scanner, short-code comparison, member slot, and explicit approval/rejection controls. The screen must show no task fields or private key bytes.

- [ ] Step 4: Implement sync screen

Show peer name/device ID, connection state, event counts, last successful sync time, retry, and quarantine/error status. A failed sync must leave already committed events and projection state visible.

- [ ] Step 5: Replace app bootstrap

main.dart constructs the local database, DeviceKeyStore, LocalUnlock, CryptoService, EventFactory, EventVerifier, EventStore, TrustedDeviceService, EpochKeyService, LocalWorkspaceService, LocalPairingService, LocalNetworkTransport, MergeEngine, ConflictResolver, LocalConflictRepository, SyncSession, TaskProjection and LocalTaskRepository. app.dart routes needsWorkspace/needsPairing/locked/ready. Do not instantiate ApiClient or HttpTaskRepository.

- [ ] Step 6: Verify UI and build

    cd client
    flutter test test/local/presentation test/widget/pairing_screen_test.dart test/widget/sync_screen_test.dart
    flutter analyze
    flutter build apk --debug

- [ ] Step 7: Commit

    git add client/lib/local/presentation client/lib/screens/workspace_setup_screen.dart client/lib/screens/pairing_screen.dart client/lib/screens/sync_screen.dart client/lib/app.dart client/lib/main.dart client/lib/screens/main_shell.dart client/test/local/presentation client/test/widget/pairing_screen_test.dart client/test/widget/sync_screen_test.dart
    git commit -m "feat: add local workspace pairing and sync screens"

### Task 11: Migrate Task UI and Add Conflict Presentation

Files:

- Create: client/lib/screens/conflict_list_screen.dart
- Create: client/lib/screens/conflict_detail_screen.dart
- Modify: client/lib/screens/main_shell.dart
- Modify: client/lib/screens/task_list_screen.dart
- Modify: client/lib/screens/task_detail_screen.dart
- Modify: client/lib/screens/task_form_screen.dart
- Modify: client/lib/screens/account_screen.dart
- Modify: client/lib/models/task.dart
- Modify: client/lib/task/task_controller.dart
- Test: client/test/widget/task_workspace_local_test.dart
- Test: client/test/widget/conflict_screen_test.dart

Interfaces:

Task 8 provides `ConflictRepository` and `LocalConflictRepository`; this task wires that repository into the existing shell and adds the conflict presentation.

    class MainShell extends StatefulWidget {
      const MainShell({
        super.key,
        required this.workspaceController,
        required this.taskRepository,
        required this.conflictRepository,
      });
    }

- [ ] Step 1: Write task workspace local-source tests

Pump MainShell with a LocalTaskRepository backed by an in-memory database. Assert create, list, detail, delay, WAITING, unblock, delete and restart/replay all render without an HTTP client or SessionController.

- [ ] Step 2: Replace account data with local member projection

AccountScreen reads the two member profiles from the workspace projection and shows device/trust/sync status. Logout is replaced by lock; locking clears in-memory key handles but does not delete the Event Store.

- [ ] Step 3: Add conflict screens

conflict_list_screen.dart lists OPEN conflicts and status badges. conflict_detail_screen.dart displays base shared state, all candidate payloads, current approvals, the complete target state selector, and approval result. It must not let the user approve a status without its WAITING fields.

- [ ] Step 4: Handle conflict failures in task UI

When a status command raises TaskConflictFailure, preserve the current task and form state, show the conflict entry point, disable only status buttons for that task, and keep delay/comment/field controls available. Refresh the task and conflict list after RESOLVED or SUPERSEDED.

- [ ] Step 5: Add widget coverage

Test conflict count, candidate rendering, differing approvals staying OPEN, equal approvals resolving, status controls re-enabling, and local tentative status not replacing the shared status silently.

- [ ] Step 6: Run client regression

    cd client
    dart format --output=none --set-exit-if-changed .
    flutter analyze
    flutter test

- [ ] Step 7: Commit

    git add client/lib/screens client/lib/models/task.dart client/lib/task/task_controller.dart client/test/widget/task_workspace_local_test.dart client/test/widget/conflict_screen_test.dart
    git commit -m "feat: migrate task ui to local events and conflicts"

### Task 12: Device-to-Device Acceptance, Legacy Boundary and Documentation

Files:

- Create: client/test/local/integration/two_device_sync_test.dart
- Create: scripts/smoke-p2p.sh
- Modify: Makefile
- Modify: .github/workflows/ci.yml
- Modify: docs/05-development-status.md
- Modify: docs/README.md
- Create: client/README.md

Interfaces:

- Consumes the complete local runtime through WorkspaceService, LocalTaskRepository and SyncSession.
- Produces a repeatable in-process two-device acceptance harness and a manual Android device checklist.

- [ ] Step 1: Write the two-node integration harness

Create two independent database directories and two fake LocalNetworkTransport endpoints. Create one workspace on A, join B into the A/B member slots, write offline events on both nodes, synchronize both directions, and assert equal event IDs, projections, delay history, member profiles and activity history.

- [ ] Step 2: Add concurrent status acceptance

From the same base task state, let A create DONE and B create CANCELLED. Sync both directions, assert neither status silently wins, assert one deterministic conflict ID and candidate set, approve the same complete target from both nodes, and assert exactly one ConflictResolved event and equal final state.

- [ ] Step 3: Add interruption, tamper and replacement acceptance

Interrupt transfer mid-chunk and resume; mutate one event byte and assert quarantine; replace A1 with A2 after B approval and assert A1 rejection, historical read access on A2, new Epoch for future events, and equal state after sync.

- [ ] Step 4: Add Makefile and CI gates

Add client-local-test, p2p-test and smoke-p2p targets. CI runs Drift code generation check, crypto/event/merge/sync tests, full Flutter tests, flutter analyze and Android debug build. Keep backend-test as the legacy Phase 0-3 regression job, but do not wire it into the new client runtime.

- [ ] Step 5: Write the manual two-Android checklist

Document installing the debug APK on two devices, creating A, pairing B by QR/short code over a hotspot, writing offline tasks on each device, syncing, resolving a status conflict, replacing one device, locking/unlocking, and verifying that a revoked device cannot sync. Explicitly record that both devices lost means no recovery in this version.

- [ ] Step 6: Run final verification

    make test
    make p2p-test
    cd client && flutter analyze
    cd client && flutter build apk --debug
    bash -n scripts/smoke-p2p.sh

Expected: legacy backend tests remain green, all local P2P tests pass, APK builds, and the smoke harness reports equal event/projection hashes for both nodes.

- [ ] Step 7: Update development status and commit

Record exact test counts, Android build path, manual-device result and any unverified hardware limitations in docs/05-development-status.md. Then commit:

    git add client scripts/smoke-p2p.sh Makefile .github/workflows/ci.yml docs/05-development-status.md docs/README.md
    git commit -m "test: verify local-first p2p workflow"

## Plan Self-Review

Spec coverage:

- Device topology, pairing, replacement and revocation: Tasks 3, 6, 10, 12.
- Ed25519/X25519/SHA-256/AES-GCM/HKDF, canonical CBOR and Keystore: Tasks 1-3 and 5.
- Event schema, independent device chains, causal context and append-only storage: Tasks 4-5.
- Rebuildable projections, additive merge and task behavior: Tasks 7-8.
- OPEN/RESOLVED/SUPERSEDED conflicts, approvals and complete WAITING payloads: Tasks 7-8 and 11-12.
- Local transport, authenticated sessions, chunk ACKs, retry and quarantine: Task 9 and 12.
- No cloud, no server runtime dependency and no automatic PostgreSQL migration: Tasks 10, 12 and Global Constraints.
- Android-only acceptance and both-device-loss boundary: Tasks 3, 10 and 12.

No task depends on a server endpoint. The only legacy files retained are the old API/auth implementations and their regression tests; main.dart will not instantiate them after Task 10. All later interfaces are named in the task that creates them before a later task consumes them.

Validation checklist:

- The plan contains no unfinished placeholder markers.
- Every task has explicit files, test steps, verification commands and a commit boundary.
- Value objects and service interfaces are introduced before their first consumer: crypto/identity, event/storage, merge/projection, sync/transport and presentation are ordered accordingly.
- `git diff --check` must pass before this plan is committed.

## Execution Handoff

Plan complete and saved to docs/superpowers/plans/2026-08-21-local-first-p2p.md. Two execution options:

1. Subagent-Driven (recommended): dispatch a fresh subagent per task, review between tasks, and keep commits small.
2. Inline Execution: execute tasks in this session using executing-plans with checkpoints.

Choose one before implementation begins.
