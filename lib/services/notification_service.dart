// Notifications: pushed announcements from FCM, and two reminders the device
// schedules for itself.
//
// The split matters. A new challenge is news only we know, so it is pushed to a
// topic. "Your hint is back" and "your streak is about to lapse" are facts the
// phone can already work out, so they are scheduled locally — they arrive with
// no network, cost no delivery, and cannot be sent to someone they are not true
// for.
//
// Everything here is best-effort in the same way analytics is: a notification
// that fails to schedule must never cost the player their game. Every platform
// call is wrapped, and [supported] keeps the whole thing away from web and from
// `flutter test`, where there is no plugin host to answer.
//
// PERMISSION IS NOT REQUESTED AT LAUNCH. It is asked for after the first level
// is finished, by [NotificationPromptDialog] — a request that arrives before
// the player knows what the app is gets refused, and on both platforms a
// refusal is close to permanent.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/challenge.dart';
import 'challenge_service.dart';
import 'free_hint_service.dart';

/// What a scheduled reminder is about. The value is the notification id, so
/// cancelling is by name rather than by a number nobody can read.
enum LocalReminder {
  hintReady(1),
  streakAtRisk(2);

  const LocalReminder(this.id);
  final int id;
}

/// FCM topics. `all` carries general announcements, `challenges` the weekly
/// drop; they are separate so a player can keep one without the other.
class NotificationTopics {
  NotificationTopics._();
  static const challenges = 'challenges';
  static const all = 'all';
}

class NotificationService {
  NotificationService._();

  // ----- preference keys -----
  static const _promptedKey = 'notification_prompted';
  static const _challengesKey = 'notif_challenge_alerts';
  static const _hintsKey = 'notif_hint_reminders';
  static const _streaksKey = 'notif_streak_reminders';
  static const _tokenKey = 'fcm_token';

  /// How long after a hint is spent the next one arrives. Mirrors
  /// [FreeHintService.regenerates] — the reminder is only correct if it fires
  /// exactly when the hint is actually back.
  static const hintRegenerates = Duration(hours: 24);

  /// How far before a challenge closes to warn about the streak. Two days on a
  /// seven-day window is "day 5", and leaves a weekend to act; warning on the
  /// last day is a notification that mostly arrives too late to be acted on.
  static const streakWarningLead = Duration(days: 2);

  /// The hour a scheduled reminder is allowed to arrive, local time. A streak
  /// warning computed to land at 03:00 is a notification that wakes someone up
  /// to tell them about a puzzle.
  static const _civilHour = 18;

  static SharedPreferences? _prefs;
  static FlutterLocalNotificationsPlugin? _local;
  static bool _tzReady = false;

  // Defaults are on: a player who granted permission asked for these. The
  // toggles exist to turn them off, not to be found and switched on.
  static bool _challengeAlerts = true;
  static bool _hintReminders = true;
  static bool _streakReminders = true;
  static bool _prompted = false;
  static bool _permissionGranted = false;
  static String? _token;

  /// Where notifications can run at all. Same shape as the other services:
  /// [kIsWeb] first, because the `dart:io` check below cannot run there.
  static bool get supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static bool get challengeAlerts => _challengeAlerts;
  static bool get hintReminders => _hintReminders;
  static bool get streakReminders => _streakReminders;

  /// Whether the player has already been asked. Asked once, ever — a prompt
  /// that returns every launch is how an app gets muted at the OS level.
  static bool get hasBeenPrompted => _prompted;

  /// Whether the OS is currently letting us post anything.
  static bool get permissionGranted => _permissionGranted;

  /// The FCM registration token, kept for future targeted sends. Null until
  /// permission is granted and the token arrives.
  static String? get token => _token;

  /// Whether the prompt should be shown after a level win.
  static bool get shouldPrompt => supported && !_prompted && !_permissionGranted;

  // ---------------------------------------------------------------- lifecycle

  /// Read preferences and, if permission already exists, wire everything up.
  ///
  /// Deliberately does NOT request permission. On a first launch this settles
  /// into "no permission, nothing scheduled, nothing subscribed" and waits for
  /// the player to be asked properly.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _prompted = prefs.getBool(_promptedKey) ?? false;
      _challengeAlerts = prefs.getBool(_challengesKey) ?? true;
      _hintReminders = prefs.getBool(_hintsKey) ?? true;
      _streakReminders = prefs.getBool(_streaksKey) ?? true;
      _token = prefs.getString(_tokenKey);
    } catch (_) {
      // No storage. Defaults stand for the session.
    }
    if (!supported) return;

    try {
      await _initLocal();
      // Whether the OS still allows this can change outside the app — Settings,
      // a long-press "turn off notifications" — so it is asked every launch
      // rather than remembered from the day permission was granted.
      _permissionGranted = await _checkPermission();
      if (_permissionGranted) {
        await _applyTopicSubscriptions();
        await syncReminders();
      }
      _listenForTaps();
    } catch (e) {
      debugPrint('notifications: init failed, continuing without: $e');
    }
  }

  /// The plugin, the timezone database and the three Android channels.
  static Future<void> _initLocal() async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {
        // Unknown zone name. UTC is wrong by hours but still fires; a reminder
        // at the wrong hour beats a reminder that never schedules.
      }
      _tzReady = true;
    }

    final plugin = _local = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        // The same white silhouette the pushed notifications use, so a
        // scheduled reminder and a pushed one are the same app in the status
        // bar. It replaces '@mipmap/ic_launcher', which Android reduced to a
        // featureless block: it keeps only the alpha, and the launcher icon is
        // opaque corner to corner.
        android: AndroidInitializationSettings('ic_notification'),
        // All three false: iOS permission is requested by the prompt dialog,
        // not silently at startup by the plugin.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => _onTap(r.payload),
    );

    // Channels are created up front rather than on first send. An Android
    // channel's importance is fixed at creation and a player's own changes to
    // it are respected forever after, so creating them late — or with the wrong
    // importance — is not something a later release can correct.
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      for (final c in _channels) {
        await android.createNotificationChannel(c);
      }
    }
  }

  static const _channels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      NotificationTopics.challenges,
      'Challenges',
      description: 'New weekly challenges and streak reminders',
    ),
    AndroidNotificationChannel(
      'hints',
      'Hints',
      description: 'When your free hint is ready again',
      // Low: a hint coming back is useful to know and not worth a sound.
      importance: Importance.low,
    ),
    AndroidNotificationChannel(
      'streaks',
      'Streaks',
      description: 'When a challenge is about to expire',
    ),
  ];

  // --------------------------------------------------------------- permission

  /// Re-read whether the OS is allowing notifications, and re-apply the topic
  /// subscriptions if it has started.
  ///
  /// Permission can change while the app is alive — the player can walk to the
  /// system settings and back — so anything showing its state has to ask again
  /// rather than trust what was true at launch.
  static Future<bool> refreshPermission() async {
    if (!supported) return false;
    final was = _permissionGranted;
    _permissionGranted = await _checkPermission();
    if (_permissionGranted && !was) unawaited(_afterPermissionGranted());
    return _permissionGranted;
  }

  /// What follows permission being granted, and what nothing on screen is
  /// waiting for.
  ///
  /// Never await this from anything a player is looking at. Every call in here
  /// goes to Google's servers or to APNs: [FirebaseMessaging.subscribeToTopic]
  /// needs a registration token before it can do anything, and on iOS a token
  /// does not exist until APNs has handed one over. With no network those do
  /// not fail, they wait — the plugin retries on its own schedule — so a future
  /// that never completes rather than an error a `catch` could turn into a
  /// result. That is what left the prompt spinning after permission had already
  /// been granted.
  ///
  /// The deadlines below are the second half of that: unawaited work still
  /// should not sit pending forever, and a subscription that has not gone
  /// through in fifteen seconds is not going through on this attempt. Both are
  /// re-applied on the next launch by [init].
  static Future<void> _afterPermissionGranted() async {
    await _applyTopicSubscriptions();
    await _captureToken();
    await syncReminders();
  }

  /// How long any single call out to FCM or APNs is given before it is treated
  /// as not happening this time.
  static const _remoteDeadline = Duration(seconds: 15);

  static Future<bool> _checkPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return _granted(settings);
    } catch (_) {
      return false;
    }
  }

  static bool _granted(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized ||
      s.authorizationStatus == AuthorizationStatus.provisional;

  /// Ask the OS. Returns whether we may post.
  ///
  /// Returns as soon as the player has answered the system dialog, and not one
  /// step later. The answer is the whole of what a caller is waiting for —
  /// subscribing to topics and fetching a token are consequences of it, not
  /// part of it, and are left to run on their own in [_afterPermissionGranted].
  /// Waiting for them meant the prompt kept spinning after permission had been
  /// granted, on exactly the path where there was something to wait for: a
  /// refusal had nothing to do afterwards and so always dismissed correctly.
  ///
  /// Marks the player as prompted either way, and before the system dialog
  /// rather than after: someone who has seen the OS prompt has been asked,
  /// whatever they answered and whatever happens next. A crash mid-dialog
  /// should not mean being asked again.
  static Future<bool> requestPermission() async {
    markPrompted();
    if (!supported) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      _permissionGranted = _granted(settings);
    } catch (e) {
      debugPrint('notifications: permission request failed: $e');
      return false;
    }
    if (_permissionGranted) unawaited(_afterPermissionGranted());
    return _permissionGranted;
  }

  /// Remember that the question has been put, without asking it.
  static void markPrompted() {
    _prompted = true;
    _write(_promptedKey, true);
  }

  static Future<void> _captureToken() async {
    try {
      // On iOS this returns null until APNs has handed over a device token, so
      // a null here is "not yet", not "failed". It can also simply not come
      // back — an unreachable APNs, or a build without the push capability —
      // hence the deadline.
      final t = await FirebaseMessaging.instance
          .getToken()
          .timeout(_remoteDeadline);
      if (t == null) return;
      _token = t;
      unawaited(_prefs?.setString(_tokenKey, t).catchError((_) => false));
    } catch (e) {
      debugPrint('notifications: token unavailable: $e');
    }
  }

  // ------------------------------------------------------------------- topics

  /// Bring topic subscriptions in line with the current preference.
  static Future<void> _applyTopicSubscriptions() async {
    await _setTopic(NotificationTopics.challenges, _challengeAlerts);
    // `all` is general announcements and rides with the same switch — there is
    // no separate toggle for it, so it should not survive one being turned off.
    await _setTopic(NotificationTopics.all, _challengeAlerts);
  }

  static Future<void> _setTopic(String topic, bool on) async {
    try {
      final fm = FirebaseMessaging.instance;
      await (on ? fm.subscribeToTopic(topic) : fm.unsubscribeFromTopic(topic))
          .timeout(_remoteDeadline);
    } catch (e) {
      debugPrint('notifications: topic $topic failed: $e');
    }
  }

  // ------------------------------------------------------------------ toggles

  static Future<void> setChallengeAlerts(bool on) async {
    _challengeAlerts = on;
    _write(_challengesKey, on);
    if (!supported || !_permissionGranted) return;
    await _applyTopicSubscriptions();
  }

  static Future<void> setHintReminders(bool on) async {
    _hintReminders = on;
    _write(_hintsKey, on);
    // Turning it off has to clear what is already queued; a reminder scheduled
    // yesterday will otherwise still arrive tomorrow.
    if (!on) await cancel(LocalReminder.hintReady);
  }

  static Future<void> setStreakReminders(bool on) async {
    _streakReminders = on;
    _write(_streaksKey, on);
    if (!on) await cancel(LocalReminder.streakAtRisk);
  }

  static void _write(String key, Object value) {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(
      (value is bool
              ? prefs.setBool(key, value)
              : prefs.setString(key, value as String))
          .catchError((_) => false),
    );
  }

  // ------------------------------------------------------- scheduling: when

  /// When the "hint is ready" reminder should fire, given the moment it was
  /// spent — exactly when the hint actually returns.
  ///
  /// Pure, so the arithmetic is testable without a plugin host.
  static DateTime hintReadyTime(DateTime spentAt) =>
      spentAt.add(hintRegenerates);

  /// When to warn that a challenge is about to close, or null if there is no
  /// useful moment left.
  ///
  /// Null covers the cases where a reminder would be wrong rather than merely
  /// late: a challenge already finished, and one whose warning point has passed
  /// — a "expires soon" that arrives after it expired is worse than silence.
  ///
  /// The time is nudged to a civil hour so the warning does not land overnight,
  /// but never nudged past the deadline it is warning about.
  static DateTime? streakWarningTime(Challenge challenge, DateTime now) {
    final deadline = challenge.endDate;
    if (!deadline.isAfter(now)) return null;

    var at = deadline.subtract(streakWarningLead);
    at = DateTime(at.year, at.month, at.day, _civilHour);
    // Nudging to 18:00 can move it backwards past now, or forwards past the
    // deadline. Either way fall back to something that is still in range.
    if (!at.isAfter(now) || !at.isBefore(deadline)) {
      final midpoint = now.add(deadline.difference(now) ~/ 2);
      return midpoint.isAfter(now) ? midpoint : null;
    }
    return at;
  }

  // ------------------------------------------------------- scheduling: doing

  /// Queue the reminder that a free hint has come back.
  ///
  /// Called when a hint is spent. Cancels first, so spending a second hint
  /// moves the reminder rather than leaving the older one to fire early.
  static Future<void> scheduleHintReady(DateTime spentAt) =>
      _scheduleHintReadyAt(hintReadyTime(spentAt));

  static Future<void> _scheduleHintReadyAt(DateTime readyAt) async {
    if (!supported || !_hintReminders || !_permissionGranted) return;
    await _schedule(
      LocalReminder.hintReady,
      at: readyAt,
      channel: 'hints',
      title: 'Your hint is ready!',
      body: 'A free hint is waiting for you in Dotto',
      payload: 'hint',
    );
  }

  /// Queue the warning that this week's challenge is about to close.
  ///
  /// Does nothing when the challenge is already beaten — the streak is safe, so
  /// there is nothing at risk to warn about.
  static Future<void> scheduleStreakAtRisk(
    Challenge challenge, {
    required bool completed,
    DateTime? now,
  }) async {
    if (!supported || !_streakReminders || !_permissionGranted) return;
    if (completed) {
      await cancel(LocalReminder.streakAtRisk);
      return;
    }
    final at = streakWarningTime(challenge, now ?? DateTime.now());
    if (at == null) return;
    await _schedule(
      LocalReminder.streakAtRisk,
      at: at,
      channel: 'streaks',
      title: "Don't break your streak!",
      body: "This week's challenge expires soon",
      payload: 'challenge',
    );
  }

  /// Bring both reminders in line with what is actually true right now.
  ///
  /// Called at launch and whenever permission changes. Reconciling rather than
  /// only ever adding is what keeps a stale reminder from firing: a hint spent
  /// on another device and already regenerated, a challenge completed since the
  /// warning was queued, a week that has since ended. Each branch either
  /// schedules the correct time or cancels.
  static Future<void> syncReminders({DateTime? now}) async {
    if (!supported || !_permissionGranted) return;
    final at = now ?? DateTime.now();

    if (!_hintReminders || FreeHintService.availableAt(at)) {
      // Nothing to wait for — the hint is already there, so a reminder would
      // announce something the player has had for hours.
      await cancelHintReady();
    } else {
      await _scheduleHintReadyAt(at.add(FreeHintService.remainingAt(at)));
    }

    final challenge = ChallengeService.currentAt(at);
    if (challenge == null) {
      await cancel(LocalReminder.streakAtRisk);
    } else {
      await scheduleStreakAtRisk(
        challenge,
        completed: ChallengeService.isCompleted(challenge.id),
        now: at,
      );
    }
  }

  /// Drop the streak warning. Called when the challenge is completed.
  static Future<void> cancelStreakAtRisk() => cancel(LocalReminder.streakAtRisk);

  /// Drop the hint reminder. Called when the hint is available again unspent,
  /// so a stale reminder cannot announce a hint the player already has.
  static Future<void> cancelHintReady() => cancel(LocalReminder.hintReady);

  static Future<void> cancel(LocalReminder reminder) async {
    if (!supported) return;
    try {
      await _local?.cancel(id: reminder.id);
    } catch (e) {
      debugPrint('notifications: cancel ${reminder.name} failed: $e');
    }
  }

  static Future<void> _schedule(
    LocalReminder reminder, {
    required DateTime at,
    required String channel,
    required String title,
    required String body,
    required String payload,
  }) async {
    final plugin = _local;
    if (plugin == null) return;
    // A time already gone would either fire immediately or throw, depending on
    // the platform. Neither is a reminder.
    if (!at.isAfter(DateTime.now())) return;
    try {
      await plugin.cancel(id: reminder.id);
      await plugin.zonedSchedule(
        id: reminder.id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            _channels.firstWhere((c) => c.id == channel).name,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Inexact: exact alarms need a special Android permission that a puzzle
        // game has no business asking for, and "some time that evening" is the
        // right precision for both of these anyway.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      debugPrint('notifications: schedule ${reminder.name} failed: $e');
    }
  }

  // -------------------------------------------------------------------- taps

  /// Where a tapped notification should take the player, or null to stay put.
  ///
  /// Pure and separate from the navigation itself so the mapping can be tested.
  static String? routeForPayload(String? payload) => switch (payload) {
        'challenge' => '/challenges',
        // A hint reminder is about the game in general, not one level. Opening
        // the menu is honest; deep-linking into a level they were not playing
        // is not.
        'hint' => null,
        _ => null,
      };

  /// FCM in all three states, plus the local-notification tap wired in
  /// [_initLocal].
  static void _listenForTaps() {
    // Tapped while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _onTap(_payloadOf(m)));
    // Tapped while the app was not running at all. The message is delivered
    // once, at startup, and only if a notification actually launched the app.
    unawaited(
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _onTap(_payloadOf(m));
      }).catchError((Object e) {
        debugPrint('notifications: initial message failed: $e');
      }),
    );
    // Foreground messages are deliberately not turned into banners here. The
    // player is already looking at the game; interrupting it to say a challenge
    // exists is worse than letting them find it, and the menu already badges.
  }

  static String? _payloadOf(RemoteMessage m) =>
      m.data['route'] as String? ?? m.data['type'] as String?;

  static void _onTap(String? payload) {
    final route = routeForPayload(payload);
    if (route == null) return;
    _navigate?.call(route);
  }

  /// Set by the app so a tap can reach the navigator. Left as a hook rather
  /// than importing a screen here: this file should not depend on the widget
  /// tree it happens to be driving.
  static void Function(String route)? _navigate;
  static set onNavigate(void Function(String route)? handler) =>
      _navigate = handler;

  /// Tests only.
  @visibleForTesting
  static void resetForTest({
    bool prompted = false,
    bool permissionGranted = false,
    bool challengeAlerts = true,
    bool hintReminders = true,
    bool streakReminders = true,
  }) {
    _prefs = null;
    _local = null;
    _prompted = prompted;
    _permissionGranted = permissionGranted;
    _challengeAlerts = challengeAlerts;
    _hintReminders = hintReminders;
    _streakReminders = streakReminders;
    _token = null;
    _navigate = null;
  }
}
