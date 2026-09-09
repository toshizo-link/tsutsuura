<?php
declare(strict_types=1);

use Tsutsuura\Server\App\AnswerMediaService;
use Tsutsuura\Server\Config;
use Tsutsuura\Server\Database;
use Tsutsuura\Server\Security\Crypto;

require dirname(__DIR__) . '/src/Autoload.php';

date_default_timezone_set('UTC');
$basePath = dirname(__DIR__);
$config = Config::fromEnvironment($basePath);
$database = new Database($config);
$pdo = $database->connection();
$cutoffs = [
    ['DELETE FROM email_otp_challenges WHERE expires_at < :cutoff', '-1 day'],
    ['DELETE FROM email_enrollment_challenges WHERE expires_at < :cutoff', '-1 day'],
    [
        'UPDATE device_pairings
         SET activation_key_hash = NULL,
             activation_response_encrypted = NULL,
             activation_replay_expires_at = NULL
         WHERE activation_replay_expires_at < :cutoff',
        'now',
    ],
    [
        'UPDATE device_recovery_codes
         SET redemption_key_hash = NULL,
             redemption_response_encrypted = NULL,
             redemption_replay_expires_at = NULL
         WHERE redemption_replay_expires_at < :cutoff',
        'now',
    ],
    [
        'UPDATE phone_otp_challenges
         SET verification_key_hash = NULL,
             verification_response_encrypted = NULL,
             verification_replay_expires_at = NULL
         WHERE verification_replay_expires_at < :cutoff',
        'now',
    ],
    [
        'UPDATE phone_enrollment_challenges
         SET verification_key_hash = NULL,
             verification_response_encrypted = NULL,
             verification_replay_expires_at = NULL
         WHERE verification_replay_expires_at < :cutoff',
        'now',
    ],
    [
        'DELETE FROM phone_otp_challenges
         WHERE expires_at < :cutoff
           AND verification_replay_expires_at IS NULL',
        '-1 day',
    ],
    [
        'DELETE FROM phone_enrollment_challenges
         WHERE expires_at < :cutoff
           AND verification_replay_expires_at IS NULL',
        '-1 day',
    ],
    [
        'DELETE FROM phone_enrollment_challenges
         WHERE consumed_at < :cutoff
           AND verification_replay_expires_at IS NULL',
        '-1 day',
    ],
    ['DELETE FROM oauth_states WHERE expires_at < :cutoff', '-1 day'],
    ['DELETE FROM auth_exchange_codes WHERE expires_at < :cutoff', '-1 day'],
    [
        'DELETE FROM device_pairings
         WHERE expires_at < :cutoff
           AND activation_replay_expires_at IS NULL',
        '-1 day',
    ],
    [
        'DELETE FROM device_pairings
         WHERE consumed_at < :cutoff
           AND activation_replay_expires_at IS NULL',
        '-1 day',
    ],
    [
        'DELETE FROM device_pairings
         WHERE revoked_at < :cutoff
           AND activation_replay_expires_at IS NULL',
        '-1 day',
    ],
    ['DELETE FROM rate_limits WHERE updated_at < :cutoff', '-2 days'],
    ['DELETE FROM sessions WHERE expires_at < :cutoff', '-30 days'],
    ['DELETE FROM sessions WHERE revoked_at < :cutoff', '-30 days'],
    [
        'DELETE FROM device_recovery_codes
         WHERE expires_at < :cutoff
           AND redemption_replay_expires_at IS NULL',
        '-30 days',
    ],
    [
        'DELETE FROM device_recovery_codes
         WHERE consumed_at < :cutoff
           AND redemption_replay_expires_at IS NULL',
        '-30 days',
    ],
    ['DELETE FROM comment_mutation_receipts WHERE expires_at < :cutoff', 'now'],
    ['DELETE FROM setup_mutation_receipts WHERE expires_at < :cutoff', 'now'],
    ['DELETE FROM otp_mutation_receipts WHERE expires_at < :cutoff', 'now'],
    // Reports also preserve the reporter's hide choice. Keep them after
    // moderation; foreign keys remove them with the content or account.
    ['DELETE FROM notification_reminder_dispatches WHERE local_date < :cutoff', '-90 days'],
    [
        "DELETE FROM notification_event_outbox
         WHERE status IN ('delivered', 'skipped', 'failed') AND completed_at < :cutoff",
        '-90 days',
    ],
    ['DELETE FROM account_audit_log WHERE created_at < :cutoff', '-730 days'],
];

$deleted = 0;
foreach ($cutoffs as [$sql, $relativeCutoff]) {
    $statement = $pdo->prepare($sql);
    $statement->execute([
        'cutoff' => (new DateTimeImmutable('now'))->modify($relativeCutoff)->format('Y-m-d H:i:s'),
    ]);
    $deleted += $statement->rowCount();
}
$orphanedMedia = (new AnswerMediaService(
    $database,
    new Crypto($config->appKey),
    $config,
))->cleanupOrphanedFiles();
echo sprintf(
    "deleted %d expired rows and %d orphaned media files\n",
    $deleted,
    $orphanedMedia,
);
