<?php
declare(strict_types=1);

namespace Tsutsuura\Server\App;

use DateTimeImmutable;
use DateTimeZone;
use JsonException;
use PDO;
use PDOException;
use RuntimeException;
use Tsutsuura\Server\Auth\Presenter;
use Tsutsuura\Server\Auth\UserService;
use Tsutsuura\Server\Auth\SessionService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Http\ApiException;
use Tsutsuura\Server\Security\Crypto;

final class LifecycleService
{
    public function __construct(
        private readonly Database $database,
        private readonly Crypto $crypto,
        private readonly Config $config,
        private readonly SessionService $sessions,
        private readonly AnswerMediaService $answerMedia,
    ) {
    }

    /** @return array{id: string, name: string} */
    public function renameFamily(int $actorUserId, mixed $nameValue): array
    {
        $name = self::name($nameValue, 'family_name', 'name');
        return $this->database->transaction(function (PDO $pdo) use ($actorUserId, $name): array {
            $membership = $this->membership($pdo, $actorUserId, true);
            $this->requireOwner($membership);
            $update = $pdo->prepare(
                'UPDATE families SET name = :name, name_tracks_owner = 0, updated_at = CURRENT_TIMESTAMP WHERE id = :family'
            );
            $update->execute(['name' => $name, 'family' => $membership['family_id']]);
            $this->audit(
                $pdo,
                $actorUserId,
                (int) $membership['family_id'],
                'family.rename',
                'family',
                (string) $membership['family_id'],
                ['name' => $name],
            );
            return ['id' => (string) $membership['family_id'], 'name' => $name];
        });
    }

    /** @return array<string, mixed> */
    public function renameMember(int $actorUserId, string $memberIdValue, mixed $nameValue): array
    {
        $memberId = self::id($memberIdValue, 'member');
        $name = self::name($nameValue, 'display_name', 'displayName');
        return $this->database->transaction(function (PDO $pdo) use (
            $actorUserId,
            $memberId,
            $name,
        ): array {
            $actor = $this->membership($pdo, $actorUserId, true);
            $target = $this->familyMember($pdo, (int) $actor['family_id'], $memberId, true);
            if ($actorUserId !== $memberId) {
                $this->requireOwner($actor);
                if (!(bool) $target['managed']) {
                    throw new ApiException(
                        403,
                        'managed_member_required',
                        'Only managed family members can be renamed by the owner.',
                    );
                }
            }
            $update = $pdo->prepare(
                'UPDATE users SET display_name = :name, updated_at = CURRENT_TIMESTAMP WHERE id = :user'
            );
            $update->execute(['name' => $name, 'user' => $memberId]);
            UserService::syncOwnerFamilyName($pdo, $memberId, $name);
            $this->audit(
                $pdo,
                $actorUserId,
                (int) $actor['family_id'],
                'family.member.rename',
                'user',
                (string) $memberId,
                ['displayName' => $name],
            );
            return Presenter::user($this->userRow($pdo, $memberId));
        });
    }

    public function removeMember(int $actorUserId, string $memberIdValue): void
    {
        $memberId = self::id($memberIdValue, 'member');
        $result = $this->database->transaction(function (PDO $pdo) use (
            $actorUserId,
            $memberId,
        ): array {
            $actor = $this->membership($pdo, $actorUserId, true);
            $this->requireOwner($actor);
            if ($actorUserId === $memberId) {
                throw new ApiException(409, 'owner_cannot_remove_self', 'Use the leave or delete-account operation.');
            }
            $target = $this->familyMember($pdo, (int) $actor['family_id'], $memberId, true);
            if ((string) $target['role'] === 'owner') {
                throw new ApiException(409, 'owner_cannot_be_removed', 'Transfer ownership before removing the owner.');
            }

            $storageKeys = $this->storageKeysForUser($pdo, $memberId);
            $this->audit(
                $pdo,
                $actorUserId,
                (int) $actor['family_id'],
                'family.member.remove',
                'user',
                (string) $memberId,
                ['managed' => (bool) $target['managed']],
            );
            if ((bool) $target['managed']) {
                $delete = $pdo->prepare('DELETE FROM users WHERE id = :user');
                $delete->execute(['user' => $memberId]);
            } else {
                $this->detachRegularMember($pdo, $memberId);
            }
            return ['storageKeys' => $storageKeys];
        });
        $this->answerMedia->deleteStorageKeys($result['storageKeys']);
    }

    /** @return array{id: string, ownerUserId: string} */
    public function transferOwnership(int $actorUserId, string $memberIdValue): array
    {
        $memberId = self::id($memberIdValue, 'member');
        return $this->database->transaction(function (PDO $pdo) use (
            $actorUserId,
            $memberId,
        ): array {
            // Recovery consumes credentials and rotates sessions for this same
            // user. Lock the user first in both paths so the eligibility check
            // below cannot observe a code/session that recovery then removes
            // before the ownership update commits.
            $targetUser = $this->lockUserRow($pdo, $memberId);
            $actor = $this->membership($pdo, $actorUserId, true);
            if ($actorUserId === $memberId) {
                throw new ApiException(409, 'already_family_owner', 'This user already owns the family.');
            }
            if ($targetUser === null) {
                throw new ApiException(404, 'family_member_not_found', 'Family member not found.');
            }
            $target = $this->familyMember($pdo, (int) $actor['family_id'], $memberId, true);

            // Retrying the exact handoff after a lost response is safe. The
            // former owner is now a member and the requested successor is the
            // sole owner, so return the committed outcome without mutating it.
            if ((string) $actor['role'] !== 'owner') {
                if ((string) $target['role'] === 'owner') {
                    return [
                        'id' => (string) $actor['family_id'],
                        'ownerUserId' => (string) $memberId,
                    ];
                }
                $this->requireOwner($actor);
            }
            $eligibility = $this->ownershipEligibility($pdo, $memberId, $targetUser);
            if ((bool) $target['managed'] && !$eligibility['activeSession']) {
                throw new ApiException(
                    409,
                    'owner_device_setup_required',
                    'The new owner must first finish setup on their own device.',
                );
            }
            if (!$eligibility['recoverable']) {
                throw new ApiException(
                    409,
                    'owner_recovery_required',
                    'The new owner must register an email address or create an unexpired recovery code.',
                );
            }

            // A caregiver-created profile becomes an independent account when
            // it accepts family ownership. Managed targets must already have
            // an active device session, and every successor must have a durable
            // email/recovery path, so the handoff cannot create a lockout.
            // Existing bearer sessions and recovery credentials remain valid.
            if ((bool) $target['managed']) {
                $promoteIndependent = $pdo->prepare(
                    'DELETE FROM managed_profiles
                     WHERE user_id = :user AND family_id = :family'
                );
                $promoteIndependent->execute([
                    'user' => $memberId,
                    'family' => $actor['family_id'],
                ]);
                if ($promoteIndependent->rowCount() !== 1) {
                    throw new RuntimeException('Managed owner promotion did not update exactly one profile.');
                }
                $revokePairings = $pdo->prepare(
                    'DELETE FROM device_pairings
                     WHERE managed_user_id = :user AND family_id = :family'
                );
                $revokePairings->execute([
                    'user' => $memberId,
                    'family' => $actor['family_id'],
                ]);
            }

            $reassignManagedProfiles = $pdo->prepare(
                'UPDATE managed_profiles SET created_by_user_id = :new_owner
                 WHERE family_id = :family'
            );
            $reassignManagedProfiles->execute([
                'new_owner' => $memberId,
                'family' => $actor['family_id'],
            ]);
            $reassignPairings = $pdo->prepare(
                'UPDATE device_pairings SET created_by_user_id = :new_owner
                 WHERE family_id = :family'
            );
            $reassignPairings->execute([
                'new_owner' => $memberId,
                'family' => $actor['family_id'],
            ]);

            $demote = $pdo->prepare(
                "UPDATE family_members SET role = 'member' WHERE family_id = :family AND user_id = :user"
            );
            $demote->execute(['family' => $actor['family_id'], 'user' => $actorUserId]);
            $promote = $pdo->prepare(
                "UPDATE family_members SET role = 'owner' WHERE family_id = :family AND user_id = :user"
            );
            $promote->execute(['family' => $actor['family_id'], 'user' => $memberId]);
            UserService::syncOwnerFamilyName($pdo, $memberId, (string) $targetUser['display_name']);
            if ($demote->rowCount() !== 1 || $promote->rowCount() !== 1) {
                throw new RuntimeException('Ownership transfer did not update exactly two memberships.');
            }
            $this->audit(
                $pdo,
                $actorUserId,
                (int) $actor['family_id'],
                'family.ownership.transfer',
                'user',
                (string) $memberId,
                [
                    'previousOwnerUserId' => (string) $actorUserId,
                    'promotedManagedMember' => (bool) $target['managed'],
                ],
            );
            return [
                'id' => (string) $actor['family_id'],
                'ownerUserId' => (string) $memberId,
            ];
        });
    }

    /** @return array{accountDeleted: bool} */
    public function leaveFamily(
        int $userId,
        mixed $idempotencyKeyValue = null,
    ): array
    {
        $keyHash = $idempotencyKeyValue === null
            ? null
            : $this->mutationKeyHash(
                'family.leave',
                $this->idempotencyKey($idempotencyKeyValue),
            );
        $result = $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $keyHash,
        ): array {
            if ($keyHash !== null) {
                $replayed = $this->reserveMutationReceipt(
                    $pdo,
                    $keyHash,
                    'family.leave',
                );
                if ($replayed !== null) {
                    return [
                        'storageKeys' => [],
                        'accountDeleted' => (bool) ($replayed['accountDeleted'] ?? false),
                    ];
                }
            }
            $membership = $this->membership($pdo, $userId, true);
            if ((string) $membership['role'] === 'owner') {
                $count = $this->familyMemberCount($pdo, (int) $membership['family_id']);
                throw new ApiException(
                    409,
                    $count > 1 ? 'ownership_transfer_required' : 'last_owner_cannot_leave',
                    $count > 1
                        ? 'Transfer ownership before leaving the family.'
                        : 'Delete the account to remove its last family.',
                );
            }
            $target = $this->familyMember($pdo, (int) $membership['family_id'], $userId, true);
            $storageKeys = $this->storageKeysForUser($pdo, $userId);
            $this->audit(
                $pdo,
                $userId,
                (int) $membership['family_id'],
                'family.leave',
                'user',
                (string) $userId,
                ['managedAccountDeleted' => (bool) $target['managed']],
            );
            $response = ['accountDeleted' => (bool) $target['managed']];
            if ($keyHash !== null) {
                $this->completeMutationReceipt(
                    $pdo,
                    $keyHash,
                    'family.leave',
                    $response,
                );
            }
            if ((bool) $target['managed']) {
                $delete = $pdo->prepare('DELETE FROM users WHERE id = :user');
                $delete->execute(['user' => $userId]);
            } else {
                $this->detachRegularMember($pdo, $userId);
            }
            return [
                'storageKeys' => $storageKeys,
                'accountDeleted' => $response['accountDeleted'],
            ];
        });
        $this->answerMedia->deleteStorageKeys($result['storageKeys']);
        return ['accountDeleted' => $result['accountDeleted']];
    }

    /** @return array<string, mixed> */
    public function exportAccount(int $userId): array
    {
        return $this->database->transaction(
            fn (PDO $pdo): array => $this->exportAccountWithConnection($pdo, $userId),
        );
    }

    /** @return array<string, mixed> */
    private function exportAccountWithConnection(PDO $pdo, int $userId): array
    {
        $user = $this->userRow($pdo, $userId);
        $membership = $this->optionalMembership($pdo, $userId);
        $answers = $pdo->prepare(
            'SELECT a.id, a.answer_date, a.body, a.created_at, a.updated_at,
                    q.prompt
             FROM answers a JOIN questions q ON q.id = a.question_id
             WHERE a.user_id = :user ORDER BY a.id ASC'
        );
        $answers->execute(['user' => $userId]);
        $answerRows = $answers->fetchAll();
        $mediaByAnswer = $this->answerMedia->forAnswers(array_map(
            static fn (array $row): int => (int) $row['id'],
            $answerRows,
        ));
        $exportedAnswers = array_map(static function (array $row) use ($mediaByAnswer): array {
            return [
                'id' => (string) $row['id'],
                'date' => (string) $row['answer_date'],
                'prompt' => (string) $row['prompt'],
                'body' => (string) $row['body'],
                'media' => array_values($mediaByAnswer[(int) $row['id']] ?? []),
                'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
                'updatedAt' => Presenter::utcTimestamp((string) $row['updated_at']),
            ];
        }, $answerRows);

        $comments = $pdo->prepare(
            'SELECT id, answer_id, parent_comment_id, body, created_at, updated_at
             FROM comments WHERE user_id = :user ORDER BY id ASC'
        );
        $comments->execute(['user' => $userId]);
        $likes = $pdo->prepare(
            'SELECT answer_id, created_at FROM answer_likes WHERE user_id = :user ORDER BY answer_id ASC'
        );
        $likes->execute(['user' => $userId]);
        $audit = $pdo->prepare(
            'SELECT action, target_type, target_id, metadata_json, created_at
             FROM account_audit_log WHERE actor_user_id = :user ORDER BY id ASC'
        );
        $audit->execute(['user' => $userId]);

        $account = Presenter::user($user, true);
        $account['phoneNumber'] = $user['phone_e164'] === null ? null : (string) $user['phone_e164'];
        return [
            'schemaVersion' => 1,
            'exportedAt' => gmdate(DATE_ATOM),
            'account' => $account,
            'family' => $membership === null ? null : $this->exportFamily($pdo, (int) $membership['family_id']),
            'answers' => $exportedAnswers,
            'comments' => array_map(static fn (array $row): array => [
                'id' => (string) $row['id'],
                'answerId' => (string) $row['answer_id'],
                'parentCommentId' => $row['parent_comment_id'] === null
                    ? null
                    : (string) $row['parent_comment_id'],
                'body' => (string) $row['body'],
                'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
                'updatedAt' => Presenter::utcTimestamp((string) $row['updated_at']),
            ], $comments->fetchAll()),
            'likedAnswerIds' => array_map(
                static fn (array $row): string => (string) $row['answer_id'],
                $likes->fetchAll(),
            ),
            'notificationPreferences' => $this->notificationPreferences($userId),
            'auditLog' => array_map(static function (array $row): array {
                try {
                    $metadata = json_decode((string) $row['metadata_json'], true, 32, JSON_THROW_ON_ERROR);
                } catch (JsonException) {
                    $metadata = [];
                }
                return [
                    'action' => (string) $row['action'],
                    'targetType' => (string) $row['target_type'],
                    'targetId' => $row['target_id'] === null ? null : (string) $row['target_id'],
                    'metadata' => is_array($metadata) ? $metadata : [],
                    'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
                ];
            }, $audit->fetchAll()),
        ];
    }

    public function deleteAccount(
        int $userId,
        mixed $idempotencyKeyValue = null,
    ): void
    {
        $keyHash = $idempotencyKeyValue === null
            ? null
            : $this->mutationKeyHash(
                'account.delete',
                $this->idempotencyKey($idempotencyKeyValue),
            );
        $result = $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $keyHash,
        ): array {
            if ($keyHash !== null) {
                $replayed = $this->reserveMutationReceipt(
                    $pdo,
                    $keyHash,
                    'account.delete',
                );
                if ($replayed !== null) {
                    return ['storageKeys' => []];
                }
            }
            $this->userRow($pdo, $userId);
            $membership = $this->optionalMembership($pdo, $userId, true);
            $deleteFamily = false;
            $familyId = null;
            if ($membership !== null) {
                $familyId = (int) $membership['family_id'];
                if ((string) $membership['role'] === 'owner') {
                    if ($this->familyMemberCount($pdo, $familyId) > 1) {
                        throw new ApiException(
                            409,
                            'ownership_transfer_required',
                            'Transfer ownership before deleting this account.',
                        );
                    }
                    $deleteFamily = true;
                }
            }
            $storageKeys = $deleteFamily && $familyId !== null
                ? $this->storageKeysForFamily($pdo, $familyId)
                : $this->storageKeysForUser($pdo, $userId);
            $this->audit(
                $pdo,
                $userId,
                $familyId,
                'account.delete',
                'user',
                (string) $userId,
                ['familyDeleted' => $deleteFamily],
            );
            if ($keyHash !== null) {
                $this->completeMutationReceipt(
                    $pdo,
                    $keyHash,
                    'account.delete',
                    [],
                );
            }
            if ($deleteFamily && $familyId !== null) {
                $delete = $pdo->prepare('DELETE FROM families WHERE id = :family');
                $delete->execute(['family' => $familyId]);
            }
            $deleteUser = $pdo->prepare('DELETE FROM users WHERE id = :user');
            $deleteUser->execute(['user' => $userId]);
            if ($deleteUser->rowCount() !== 1) {
                throw new ApiException(404, 'user_not_found', 'User not found.');
            }
            return ['storageKeys' => $storageKeys];
        });
        $this->answerMedia->deleteStorageKeys($result['storageKeys']);
    }

    /** @return array<string, mixed>|null */
    public function replayMutation(
        string $operation,
        mixed $idempotencyKeyValue,
    ): ?array {
        if ($idempotencyKeyValue === null) {
            return null;
        }
        $keyHash = $this->mutationKeyHash(
            $operation,
            $this->idempotencyKey($idempotencyKeyValue),
        );
        $statement = $this->database->connection()->prepare(
            'SELECT result_json FROM lifecycle_mutation_receipts
             WHERE key_hash = :key AND operation = :operation
             LIMIT 1'
        );
        $statement->execute(['key' => $keyHash, 'operation' => $operation]);
        $json = $statement->fetchColumn();
        if (!is_string($json)) {
            return null;
        }
        $result = json_decode((string) $json, true, 32, JSON_THROW_ON_ERROR);
        if (!is_array($result)) {
            throw new RuntimeException('Stored lifecycle replay receipt is invalid.');
        }
        return $result;
    }

    /** @return array<string, mixed> */
    public function notificationPreferences(int $userId): array
    {
        return $this->notificationPreferencesWithConnection(
            $this->database->connection(),
            $userId,
        );
    }

    /** Update the signed-in device's timezone without resubmitting preference toggles.
     *  @param array<string, mixed> $values
     *  @return array<string, mixed>
     */
    public function updateDeviceTimezone(int $userId, array $values): array
    {
        if (array_keys($values) !== ['timeZoneIdentifier']) {
            throw new ApiException(422, 'invalid_timezone', 'Specify only timeZoneIdentifier.');
        }
        $timezone = $values['timeZoneIdentifier'];
        if (!is_string($timezone) || strlen($timezone) > 64 ||
            !in_array($timezone, DateTimeZone::listIdentifiers(DateTimeZone::ALL_WITH_BC), true)) {
            throw new ApiException(422, 'invalid_timezone', 'timeZoneIdentifier must be an IANA timezone identifier.');
        }
        return $this->database->transaction(function (PDO $pdo) use ($userId, $timezone): array {
            $this->userRow($pdo, $userId);
            // Serialize with preference edits while updating only timezone;
            // this device sync never resubmits or replaces notification choices.
            if (!$this->database->isSqlite()) {
                $lockUser = $pdo->prepare('SELECT id FROM users WHERE id = :user FOR UPDATE');
                $lockUser->execute(['user' => $userId]);
            }
            $statement = $pdo->prepare($this->database->isSqlite()
                ? 'INSERT INTO notification_preferences (user_id, timezone)
                   VALUES (:user, :timezone)
                   ON CONFLICT(user_id) DO UPDATE SET
                     timezone = excluded.timezone, updated_at = CURRENT_TIMESTAMP'
                : 'INSERT INTO notification_preferences (user_id, timezone)
                   VALUES (:user, :timezone)
                   ON DUPLICATE KEY UPDATE
                     timezone = VALUES(timezone), updated_at = CURRENT_TIMESTAMP'
            );
            $statement->execute(['user' => $userId, 'timezone' => $timezone]);
            return $this->notificationPreferencesWithConnection($pdo, $userId);
        });
    }

    /** @param array<string, mixed> $values
     *  @return array<string, mixed>
     */
    public function updateNotificationPreferences(int $userId, array $values): array
    {
        $allowed = [
            'questionRemindersEnabled',
            'questionReminderTime',
            'commentsEnabled',
            'likesEnabled',
            'familyActivityEnabled',
            'quietStart',
            'quietEnd',
            'timezone',
            'muteUntil',
        ];
        $unknown = array_diff(array_keys($values), $allowed);
        if ($unknown !== []) {
            throw new ApiException(
                422,
                'invalid_notification_preferences',
                'Notification preferences contain unsupported fields.',
            );
        }
        if ($values === []) {
            throw new ApiException(
                422,
                'invalid_notification_preferences',
                'At least one notification preference is required.',
            );
        }
        return $this->database->transaction(function (PDO $pdo) use (
            $userId,
            $values,
        ): array {
            $this->userRow($pdo, $userId);
            if (!$this->database->isSqlite()) {
                $lockUser = $pdo->prepare('SELECT id FROM users WHERE id = :user FOR UPDATE');
                $lockUser->execute(['user' => $userId]);
            }
            $current = $this->notificationPreferencesWithConnection($pdo, $userId);
            foreach ([
                'questionRemindersEnabled',
                'commentsEnabled',
                'likesEnabled',
                'familyActivityEnabled',
            ] as $field) {
                if (array_key_exists($field, $values)) {
                    if (!is_bool($values[$field])) {
                        throw new ApiException(
                            422,
                            'invalid_notification_preferences',
                            $field . ' must be a boolean.',
                        );
                    }
                    $current[$field] = $values[$field];
                }
            }
            if (array_key_exists('questionReminderTime', $values)) {
                $current['questionReminderTime'] = self::requiredTime(
                    $values['questionReminderTime'],
                    'questionReminderTime',
                );
            }
            foreach (['quietStart', 'quietEnd'] as $field) {
                if (array_key_exists($field, $values)) {
                    $current[$field] = self::quietTime($values[$field], $field);
                }
            }
            if (array_key_exists('timezone', $values)) {
                $current['timezone'] = self::timezone($values['timezone']);
            }
            if (array_key_exists('muteUntil', $values)) {
                $muteUntil = self::notificationMuteUntil($values['muteUntil']);
                $current['muteUntil'] = $muteUntil === null
                    ? null
                    : Presenter::utcTimestamp($muteUntil);
            }
            $statement = $pdo->prepare($this->database->isSqlite()
                ? 'INSERT INTO notification_preferences
                    (user_id, question_reminders_enabled, question_reminder_time,
                     comments_enabled, likes_enabled,
                     family_activity_enabled, quiet_start, quiet_end, timezone, mute_until)
                   VALUES (:user, :questions, :question_time, :comments, :likes,
                           :family, :quiet_start, :quiet_end, :timezone, :mute_until)
                   ON CONFLICT(user_id) DO UPDATE SET
                     question_reminders_enabled = excluded.question_reminders_enabled,
                     question_reminder_time = excluded.question_reminder_time,
                     comments_enabled = excluded.comments_enabled,
                     likes_enabled = excluded.likes_enabled,
                     family_activity_enabled = excluded.family_activity_enabled,
                     quiet_start = excluded.quiet_start,
                     quiet_end = excluded.quiet_end,
                     timezone = excluded.timezone,
                     mute_until = excluded.mute_until,
                     updated_at = CURRENT_TIMESTAMP'
                : 'INSERT INTO notification_preferences
                    (user_id, question_reminders_enabled, question_reminder_time,
                     comments_enabled, likes_enabled,
                     family_activity_enabled, quiet_start, quiet_end, timezone, mute_until)
                   VALUES (:user, :questions, :question_time, :comments, :likes,
                           :family, :quiet_start, :quiet_end, :timezone, :mute_until)
                   ON DUPLICATE KEY UPDATE
                     question_reminders_enabled = VALUES(question_reminders_enabled),
                     question_reminder_time = VALUES(question_reminder_time),
                     comments_enabled = VALUES(comments_enabled),
                     likes_enabled = VALUES(likes_enabled),
                     family_activity_enabled = VALUES(family_activity_enabled),
                     quiet_start = VALUES(quiet_start), quiet_end = VALUES(quiet_end),
                     timezone = VALUES(timezone), mute_until = VALUES(mute_until),
                     updated_at = CURRENT_TIMESTAMP'
            );
            $statement->execute([
                'user' => $userId,
                'questions' => $current['questionRemindersEnabled'] ? 1 : 0,
                'question_time' => $current['questionReminderTime'],
                'comments' => $current['commentsEnabled'] ? 1 : 0,
                'likes' => $current['likesEnabled'] ? 1 : 0,
                'family' => $current['familyActivityEnabled'] ? 1 : 0,
                'quiet_start' => $current['quietStart'],
                'quiet_end' => $current['quietEnd'],
                'timezone' => $current['timezone'],
                'mute_until' => self::notificationMuteUntil($current['muteUntil']),
            ]);
            $membership = $this->optionalMembership($pdo, $userId);
            $this->audit(
                $pdo,
                $userId,
                $membership === null ? null : (int) $membership['family_id'],
                'notifications.preferences.update',
                'user',
                (string) $userId,
            );
            return $this->notificationPreferencesWithConnection($pdo, $userId);
        });
    }

    /** @return array{code: string, expiresAt: string} */
    public function createRecoveryCode(int $userId): array
    {
        $code = $this->crypto->randomToken(32);
        $expires = (new DateTimeImmutable('now'))->modify('+30 days');
        $this->database->transaction(function (PDO $pdo) use ($userId, $code, $expires): void {
            if ($this->lockUserRow($pdo, $userId) === null) {
                throw new ApiException(404, 'user_not_found', 'User not found.');
            }
            $invalidate = $pdo->prepare(
                'UPDATE device_recovery_codes SET consumed_at = CURRENT_TIMESTAMP
                 WHERE user_id = :user AND consumed_at IS NULL'
            );
            $invalidate->execute(['user' => $userId]);
            $insert = $pdo->prepare(
                'INSERT INTO device_recovery_codes (user_id, code_hash, expires_at)
                 VALUES (:user, :hash, :expires)'
            );
            $insert->execute([
                'user' => $userId,
                'hash' => $this->crypto->hashOpaque('device-recovery:' . $code),
                'expires' => $expires->format('Y-m-d H:i:s'),
            ]);
            $membership = $this->optionalMembership($pdo, $userId);
            $this->audit(
                $pdo,
                $userId,
                $membership === null ? null : (int) $membership['family_id'],
                'device.recovery.create',
                'user',
                (string) $userId,
            );
        });
        return ['code' => $code, 'expiresAt' => $expires->format(DATE_ATOM)];
    }

    /** @return array<string, mixed> */
    public function recoverSession(
        mixed $codeValue,
        mixed $idempotencyKeyValue = null,
    ): array {
        if (!is_string($codeValue) ||
            preg_match('/^[A-Za-z0-9_-]{40,128}$/', trim($codeValue)) !== 1) {
            throw new ApiException(422, 'invalid_recovery_code', 'Recovery code is invalid.');
        }
        $code = trim($codeValue);
        $codeHash = $this->crypto->hashOpaque('device-recovery:' . $code);
        $idempotencyKey = $this->idempotencyKey($idempotencyKeyValue);
        $keyHash = $this->crypto->hashOpaque('recovery-redemption:' . $idempotencyKey);
        return $this->database->transaction(function (PDO $pdo) use (
            $codeHash,
            $keyHash,
        ): array {
            // The credential lookup identifies the common lock row. It is
            // deliberately followed by a second, locking read after the user
            // lock: another transaction may consume/invalidate the code while
            // this transaction waits for that lock.
            $ownerLookup = $pdo->prepare(
                'SELECT user_id FROM device_recovery_codes WHERE code_hash = :hash LIMIT 1'
            );
            $ownerLookup->execute(['hash' => $codeHash]);
            $recoveryUserId = $ownerLookup->fetchColumn();
            if ($recoveryUserId === false ||
                $this->lockUserRow($pdo, (int) $recoveryUserId) === null) {
                throw new ApiException(422, 'invalid_recovery_code', 'Recovery code is invalid or expired.');
            }

            $sql =
                'SELECT drc.id, drc.user_id, drc.expires_at, drc.consumed_at,
                        drc.redemption_key_hash, drc.redemption_response_encrypted,
                        drc.redemption_replay_expires_at,
                        u.phone_e164, u.email_address, u.email_verified_at, u.display_name, u.avatar_url, u.avatar_mark, u.created_at,
                        CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
                 FROM device_recovery_codes drc
                 JOIN users u ON u.id = drc.user_id
                 LEFT JOIN managed_profiles mp ON mp.user_id = u.id
                 WHERE drc.code_hash = :hash AND drc.user_id = :user LIMIT 1';
            if (!$this->database->isSqlite()) {
                $sql .= ' FOR UPDATE';
            }
            $statement = $pdo->prepare($sql);
            $statement->execute([
                'hash' => $codeHash,
                'user' => $recoveryUserId,
            ]);
            $row = $statement->fetch();
            if (!is_array($row)) {
                throw new ApiException(422, 'invalid_recovery_code', 'Recovery code is invalid or expired.');
            }
            $recoveryCodeId = (int) $row['id'];
            if ($row['consumed_at'] !== null) {
                if (is_string($row['redemption_key_hash']) &&
                    hash_equals($row['redemption_key_hash'], $keyHash) &&
                    is_string($row['redemption_response_encrypted']) &&
                    is_string($row['redemption_replay_expires_at']) &&
                    strtotime($row['redemption_replay_expires_at']) > time()) {
                    return $this->decryptAuthResponse(
                        $row['redemption_response_encrypted']
                    );
                }
                throw new ApiException(
                    422,
                    'invalid_recovery_code',
                    'Recovery code is invalid or expired.',
                );
            }
            if (strtotime((string) $row['expires_at']) <= time()) {
                throw new ApiException(422, 'invalid_recovery_code', 'Recovery code is invalid or expired.');
            }

            $reused = $pdo->prepare(
                'SELECT 1 FROM device_recovery_codes
                 WHERE redemption_key_hash = :key AND id <> :id LIMIT 1'
            );
            $reused->execute(['key' => $keyHash, 'id' => $recoveryCodeId]);
            if ($reused->fetchColumn() !== false) {
                throw new ApiException(
                    409,
                    'idempotency_key_reused',
                    'The idempotency key was already used for another recovery.',
                );
            }

            $revokeSessions = $pdo->prepare(
                'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP
                 WHERE user_id = :user AND revoked_at IS NULL'
            );
            $revokeSessions->execute(['user' => $row['user_id']]);
            $deletePushTokens = $pdo->prepare('DELETE FROM push_tokens WHERE user_id = :user');
            $deletePushTokens->execute(['user' => $row['user_id']]);
            $membership = $this->optionalMembership($pdo, (int) $row['user_id']);
            $this->audit(
                $pdo,
                (int) $row['user_id'],
                $membership === null ? null : (int) $membership['family_id'],
                'device.recovery.consume',
                'user',
                (string) $row['user_id'],
                [
                    'revokedSessions' => $revokeSessions->rowCount(),
                    'removedPushTokens' => $deletePushTokens->rowCount(),
                ],
            );
            $row['id'] = $row['user_id'];
            // Issue the replacement inside the same transaction so a failed
            // insert cannot consume the code and strand the account.
            $session = $this->sessions->issueWithConnection(
                $pdo,
                (int) $row['user_id']
            );
            $auth = [
                'token' => $session['token'],
                'tokenType' => 'Bearer',
                'expiresAt' => $session['expiresAt'],
                'user' => Presenter::user($row, true),
            ];

            $encoded = json_encode($auth, JSON_THROW_ON_ERROR);
            // As with pairing activation, consuming this code invalidates the
            // only credential the user supplied. Retain the encrypted exact
            // response until its issued session expires.
            $replayExpiresAt = (new DateTimeImmutable((string) $auth['expiresAt']))
                ->format('Y-m-d H:i:s');
            $consume = $pdo->prepare(
                'UPDATE device_recovery_codes
                 SET consumed_at = CURRENT_TIMESTAMP,
                     redemption_key_hash = :key,
                     redemption_response_encrypted = :response,
                     redemption_replay_expires_at = :replay_expires
                 WHERE id = :id AND consumed_at IS NULL'
            );
            $consume->execute([
                'key' => $keyHash,
                'response' => $this->crypto->encrypt($encoded),
                'replay_expires' => $replayExpiresAt,
                'id' => $recoveryCodeId,
            ]);
            if ($consume->rowCount() !== 1) {
                throw new ApiException(
                    409,
                    'recovery_state_changed',
                    'Recovery code was already used.',
                );
            }
            return $auth;
        });
    }

    /** @return array<string, mixed> */
    private function decryptAuthResponse(string $encrypted): array
    {
        $decoded = json_decode(
            $this->crypto->decrypt($encrypted),
            true,
            32,
            JSON_THROW_ON_ERROR,
        );
        if (!is_array($decoded) || !is_string($decoded['token'] ?? null)) {
            throw new RuntimeException('Stored recovery replay response is invalid.');
        }
        return $decoded;
    }

    private function idempotencyKey(mixed $value): string
    {
        if ($value === null) {
            return $this->crypto->randomToken(24);
        }
        if (!is_string($value) ||
            preg_match('/^[A-Za-z0-9._-]{16,128}$/', trim($value)) !== 1) {
            throw new ApiException(
                422,
                'invalid_idempotency_key',
                'Idempotency-Key must be 16 to 128 safe ASCII characters.',
            );
        }
        return trim($value);
    }

    private function mutationKeyHash(string $operation, string $key): string
    {
        return $this->crypto->hashOpaque(
            'lifecycle-mutation:' . $operation . ':' . $key
        );
    }

    /**
     * Reserves a globally unique lifecycle key inside the mutation
     * transaction. A concurrent duplicate blocks on the unique row and then
     * observes the exact completed response rather than rerunning against a
     * deleted account or a replacement family.
     *
     * @return array<string, mixed>|null Completed replay, or null for the
     * newly reserved request.
     */
    private function reserveMutationReceipt(
        PDO $pdo,
        string $keyHash,
        string $operation,
    ): ?array {
        $reserve = $pdo->prepare($this->database->isSqlite()
            ? 'INSERT OR IGNORE INTO lifecycle_mutation_receipts
                 (key_hash, operation, result_json)
               VALUES (:key, :operation, NULL)'
            : 'INSERT IGNORE INTO lifecycle_mutation_receipts
                 (key_hash, operation, result_json)
               VALUES (:key, :operation, NULL)'
        );
        $reserve->execute(['key' => $keyHash, 'operation' => $operation]);

        $sql =
            'SELECT operation, result_json FROM lifecycle_mutation_receipts
             WHERE key_hash = :key LIMIT 1';
        if (!$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $lookup = $pdo->prepare($sql);
        $lookup->execute(['key' => $keyHash]);
        $row = $lookup->fetch();
        if (!is_array($row) || (string) $row['operation'] !== $operation) {
            throw new RuntimeException('Lifecycle mutation receipt reservation is invalid.');
        }
        if (!is_string($row['result_json'])) {
            return null;
        }
        $result = json_decode((string) $row['result_json'], true, 32, JSON_THROW_ON_ERROR);
        if (!is_array($result)) {
            throw new RuntimeException('Stored lifecycle replay receipt is invalid.');
        }
        return $result;
    }

    /** @param array<string, mixed> $result */
    private function completeMutationReceipt(
        PDO $pdo,
        string $keyHash,
        string $operation,
        array $result,
    ): void {
        $update = $pdo->prepare(
            'UPDATE lifecycle_mutation_receipts SET result_json = :result
             WHERE key_hash = :key AND operation = :operation
               AND result_json IS NULL'
        );
        $update->execute([
            'key' => $keyHash,
            'operation' => $operation,
            'result' => json_encode($result, JSON_THROW_ON_ERROR),
        ]);
        if ($update->rowCount() !== 1) {
            throw new RuntimeException('Lifecycle mutation receipt did not complete exactly once.');
        }
    }

    /** @return array<string, mixed> */
    private function membership(PDO $pdo, int $userId, bool $forUpdate = false): array
    {
        $membership = $this->optionalMembership($pdo, $userId, $forUpdate);
        if ($membership === null) {
            throw new ApiException(409, 'family_required', 'The user does not belong to a family.');
        }
        return $membership;
    }

    /** @return array<string, mixed>|null */
    private function optionalMembership(PDO $pdo, int $userId, bool $forUpdate = false): ?array
    {
        $sql =
            'SELECT fm.family_id, fm.role, f.name AS family_name
             FROM family_members fm JOIN families f ON f.id = fm.family_id
             WHERE fm.user_id = :user';
        if ($forUpdate && !$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute(['user' => $userId]);
        $row = $statement->fetch();
        return is_array($row) ? $row : null;
    }

    /** @return array<string, mixed> */
    private function familyMember(PDO $pdo, int $familyId, int $userId, bool $forUpdate): array
    {
        $sql =
            'SELECT fm.role,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM family_members fm
             LEFT JOIN managed_profiles mp ON mp.user_id = fm.user_id
             WHERE fm.family_id = :family AND fm.user_id = :user';
        if ($forUpdate && !$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute(['family' => $familyId, 'user' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'family_member_not_found', 'Family member not found.');
        }
        return $row;
    }

    /** @return array<string, mixed>|null */
    private function lockUserRow(PDO $pdo, int $userId): ?array
    {
        $sql =
            'SELECT id, phone_e164, email_address, email_verified_at, display_name, avatar_url, avatar_mark, created_at
             FROM users WHERE id = :user';
        if (!$this->database->isSqlite()) {
            $sql .= ' FOR UPDATE';
        }
        $statement = $pdo->prepare($sql);
        $statement->execute(['user' => $userId]);
        $row = $statement->fetch();
        return is_array($row) ? $row : null;
    }

    /**
     * @param array<string, mixed> $lockedUser
     * @return array{activeSession: bool, recoverable: bool}
     */
    private function ownershipEligibility(PDO $pdo, int $userId, array $lockedUser): array
    {
        $sessionSql =
            'SELECT id FROM sessions
             WHERE user_id = :user AND revoked_at IS NULL
               AND expires_at > CURRENT_TIMESTAMP
             ORDER BY id ASC LIMIT 1';
        if (!$this->database->isSqlite()) {
            $sessionSql .= ' FOR UPDATE';
        }
        $session = $pdo->prepare($sessionSql);
        $session->execute(['user' => $userId]);
        $activeSession = $session->fetchColumn() !== false;

        $recoverable = ($lockedUser['email_address'] !== null && $lockedUser['email_verified_at'] !== null) ||
            $lockedUser['phone_e164'] !== null;
        if (!$recoverable) {
            $recoverySql =
                'SELECT id FROM device_recovery_codes
                 WHERE user_id = :user AND consumed_at IS NULL
                   AND expires_at > CURRENT_TIMESTAMP
                 ORDER BY id ASC LIMIT 1';
            if (!$this->database->isSqlite()) {
                $recoverySql .= ' FOR UPDATE';
            }
            $recovery = $pdo->prepare($recoverySql);
            $recovery->execute(['user' => $userId]);
            $recoverable = $recovery->fetchColumn() !== false;
        }

        return ['activeSession' => $activeSession, 'recoverable' => $recoverable];
    }

    private function requireOwner(array $membership): void
    {
        if ((string) $membership['role'] !== 'owner') {
            throw new ApiException(403, 'family_owner_required', 'Only the family owner can perform this action.');
        }
    }

    private function familyMemberCount(PDO $pdo, int $familyId): int
    {
        $statement = $pdo->prepare('SELECT COUNT(*) FROM family_members WHERE family_id = :family');
        $statement->execute(['family' => $familyId]);
        return (int) $statement->fetchColumn();
    }

    /** @return array<string, mixed> */
    private function userRow(PDO $pdo, int $userId): array
    {
        $statement = $pdo->prepare(
            'SELECT u.id, u.phone_e164, u.email_address, u.email_verified_at, u.display_name, u.avatar_url, u.avatar_mark, u.created_at,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM users u LEFT JOIN managed_profiles mp ON mp.user_id = u.id
             WHERE u.id = :user'
        );
        $statement->execute(['user' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'user_not_found', 'User not found.');
        }
        return $row;
    }

    private function detachRegularMember(PDO $pdo, int $userId): void
    {
        foreach ([
            'DELETE FROM comments WHERE user_id = :user',
            'DELETE FROM answer_likes WHERE user_id = :user',
            'DELETE FROM answers WHERE user_id = :user',
            'DELETE FROM device_pairings WHERE managed_user_id = :managed_user OR created_by_user_id = :creator_user',
            'DELETE FROM managed_profiles WHERE user_id = :user',
            // Preferences are scoped to the current one-family membership.
            // A replacement family starts from defaults instead of inheriting
            // mute/category choices made for people in the former family.
            'DELETE FROM notification_preferences WHERE user_id = :user',
            'DELETE FROM family_members WHERE user_id = :user',
        ] as $sql) {
            $statement = $pdo->prepare($sql);
            if (str_contains($sql, ':managed_user')) {
                $statement->execute([
                    'managed_user' => $userId,
                    'creator_user' => $userId,
                ]);
            } else {
                $statement->execute(['user' => $userId]);
            }
        }
        $familyId = $this->insertPersonalFamily($pdo);
        $member = $pdo->prepare(
            "INSERT INTO family_members (family_id, user_id, role) VALUES (:family, :user, 'owner')"
        );
        $member->execute(['family' => $familyId, 'user' => $userId]);
    }

    private function insertPersonalFamily(PDO $pdo): int
    {
        for ($attempt = 0; $attempt < 5; $attempt++) {
            $inviteCode = strtoupper(substr(bin2hex(random_bytes(8)), 0, 12));
            try {
                $insert = $pdo->prepare(
                    "INSERT INTO families (name, invite_code) VALUES ('わたしの家族', :code)"
                );
                $insert->execute(['code' => $inviteCode]);
                return (int) $pdo->lastInsertId();
            } catch (PDOException $exception) {
                if ((string) $exception->getCode() !== '23000') {
                    throw $exception;
                }
            }
        }
        throw new RuntimeException('Unable to create a replacement family.');
    }

    /** @return list<string> */
    private function storageKeysForUser(PDO $pdo, int $userId): array
    {
        $statement = $pdo->prepare(
            'SELECT am.storage_key FROM answer_media am
             JOIN answers a ON a.id = am.answer_id WHERE a.user_id = :user'
        );
        $statement->execute(['user' => $userId]);
        return array_values(array_map('strval', $statement->fetchAll(PDO::FETCH_COLUMN)));
    }

    /** @return list<string> */
    private function storageKeysForFamily(PDO $pdo, int $familyId): array
    {
        $statement = $pdo->prepare(
            'SELECT am.storage_key FROM answer_media am
             JOIN answers a ON a.id = am.answer_id WHERE a.family_id = :family'
        );
        $statement->execute(['family' => $familyId]);
        return array_values(array_map('strval', $statement->fetchAll(PDO::FETCH_COLUMN)));
    }

    /** @return array<string, mixed> */
    private function exportFamily(PDO $pdo, int $familyId): array
    {
        $family = $pdo->prepare('SELECT id, name, created_at FROM families WHERE id = :family');
        $family->execute(['family' => $familyId]);
        $row = $family->fetch();
        if (!is_array($row)) {
            throw new ApiException(404, 'family_not_found', 'Family not found.');
        }
        $members = $pdo->prepare(
            'SELECT u.id, u.display_name, u.avatar_mark, fm.role, fm.joined_at,
                    CASE WHEN mp.user_id IS NULL THEN 0 ELSE 1 END AS managed
             FROM family_members fm JOIN users u ON u.id = fm.user_id
             LEFT JOIN managed_profiles mp ON mp.user_id = u.id
             WHERE fm.family_id = :family ORDER BY fm.joined_at ASC, u.id ASC'
        );
        $members->execute(['family' => $familyId]);
        return [
            'id' => (string) $row['id'],
            'name' => (string) $row['name'],
            'createdAt' => Presenter::utcTimestamp((string) $row['created_at']),
            'members' => array_map(static fn (array $member): array => [
                'id' => (string) $member['id'],
                'displayName' => (string) $member['display_name'],
                'avatarMark' => $member['avatar_mark'],
                'role' => (string) $member['role'],
                'managed' => (bool) $member['managed'],
                'joinedAt' => Presenter::utcTimestamp((string) $member['joined_at']),
            ], $members->fetchAll()),
        ];
    }

    /** @param array<string, mixed> $metadata */
    private function audit(
        PDO $pdo,
        ?int $actorUserId,
        ?int $familyId,
        string $action,
        string $targetType,
        ?string $targetId,
        array $metadata = [],
    ): void {
        $statement = $pdo->prepare(
            'INSERT INTO account_audit_log
                (actor_user_id, family_id, action, target_type, target_id, metadata_json)
             VALUES (:actor, :family, :action, :target_type, :target_id, :metadata)'
        );
        $statement->execute([
            'actor' => $actorUserId,
            'family' => $familyId,
            'action' => $action,
            'target_type' => $targetType,
            'target_id' => $targetId,
            'metadata' => json_encode($metadata, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE),
        ]);
    }

    /** @return array<string, mixed> */
    private function notificationPreferencesWithConnection(PDO $pdo, int $userId): array
    {
        $statement = $pdo->prepare(
            'SELECT question_reminders_enabled, question_reminder_time,
                    comments_enabled, likes_enabled, family_activity_enabled,
                    quiet_start, quiet_end, timezone, mute_until, updated_at
             FROM notification_preferences WHERE user_id = :user'
        );
        $statement->execute(['user' => $userId]);
        $row = $statement->fetch();
        if (!is_array($row)) {
            return [
                'questionRemindersEnabled' => true,
                'questionReminderTime' => '09:00',
                'commentsEnabled' => true,
                'likesEnabled' => true,
                'familyActivityEnabled' => true,
                'quietStart' => null,
                'quietEnd' => null,
                'timezone' => null,
                'muteUntil' => null,
                'updatedAt' => null,
            ];
        }
        return self::presentNotificationPreferences($row);
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private static function presentNotificationPreferences(array $row): array
    {
        return [
            'questionRemindersEnabled' => (bool) $row['question_reminders_enabled'],
            'questionReminderTime' => self::presentTime($row['question_reminder_time']),
            'commentsEnabled' => (bool) $row['comments_enabled'],
            'likesEnabled' => (bool) $row['likes_enabled'],
            'familyActivityEnabled' => (bool) $row['family_activity_enabled'],
            'quietStart' => self::presentTime($row['quiet_start']),
            'quietEnd' => self::presentTime($row['quiet_end']),
            'timezone' => $row['timezone'] === null ? null : (string) $row['timezone'],
            'muteUntil' => $row['mute_until'] === null
                ? null
                : Presenter::utcTimestamp((string) $row['mute_until']),
            'updatedAt' => Presenter::utcTimestamp((string) $row['updated_at']),
        ];
    }

    private static function presentTime(mixed $value): ?string
    {
        return $value === null ? null : substr((string) $value, 0, 5);
    }

    private static function quietTime(mixed $value, string $field): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value) || preg_match('/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/', $value) !== 1) {
            throw new ApiException(
                422,
                'invalid_notification_preferences',
                $field . ' must use 24-hour HH:MM format or be null.',
            );
        }
        return $value;
    }

    private static function requiredTime(mixed $value, string $field): string
    {
        $time = self::quietTime($value, $field);
        if ($time === null) {
            throw new ApiException(
                422,
                'invalid_notification_preferences',
                $field . ' must use 24-hour HH:MM format.',
            );
        }
        return $time;
    }

    private static function timezone(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value) || strlen($value) > 64) {
            throw new ApiException(422, 'invalid_timezone', 'timezone is invalid.');
        }
        try {
            new DateTimeZone($value);
        } catch (\Exception) {
            throw new ApiException(422, 'invalid_timezone', 'timezone is invalid.');
        }
        return $value;
    }

    private static function notificationMuteUntil(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value) || preg_match(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/',
            $value,
        ) !== 1) {
            throw new ApiException(
                422,
                'invalid_notification_preferences',
                'muteUntil must be an ISO-8601 timestamp with a timezone or be null.',
            );
        }
        $normalized = str_ends_with($value, 'Z') ? substr($value, 0, -1) . '+00:00' : $value;
        $format = str_contains($normalized, '.')
            ? '!Y-m-d\\TH:i:s.uP'
            : '!Y-m-d\\TH:i:sP';
        $timestamp = DateTimeImmutable::createFromFormat($format, $normalized);
        $errors = DateTimeImmutable::getLastErrors();
        if ($timestamp === false || ($errors !== false && (
            $errors['warning_count'] > 0 || $errors['error_count'] > 0
        ))) {
            throw new ApiException(
                422,
                'invalid_notification_preferences',
                'muteUntil must be a valid ISO-8601 timestamp.',
            );
        }
        return $timestamp
            ->setTimezone(new DateTimeZone('UTC'))
            ->format('Y-m-d H:i:s');
    }

    private static function id(string $value, string $resource): int
    {
        if (preg_match('/^[1-9][0-9]{0,18}$/', $value) !== 1) {
            throw new ApiException(422, 'invalid_' . $resource . '_id', $resource . ' id is invalid.');
        }
        return (int) $value;
    }

    private static function name(mixed $value, string $errorSuffix, string $field): string
    {
        if (!is_string($value)) {
            throw new ApiException(422, 'invalid_' . $errorSuffix, $field . ' must be a string.');
        }
        $value = trim(str_replace("\0", '', preg_replace('/\s+/u', ' ', $value) ?? ''));
        if ($value === '' || mb_strlen($value, 'UTF-8') > 80) {
            throw new ApiException(
                422,
                'invalid_' . $errorSuffix,
                $field . ' must be between 1 and 80 characters.',
            );
        }
        return $value;
    }
}
