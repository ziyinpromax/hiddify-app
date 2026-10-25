import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/flash_pool.dart';
import 'package:hiddify/core/flash_public.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/model/trusted_links.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_icons/simple_icons.dart';

class ProfileTile extends HookConsumerWidget {
  const ProfileTile({
    super.key,
    required this.profile,
    this.isMain = false,
    this.margin = EdgeInsets.zero,
    this.isPublic = false,
    this.isPublished = false,
  });

  final ProfileEntity profile;

  /// home screen active profile card
  final bool isMain;
  final EdgeInsets margin;

  /// Flâsh fork only: true when the user marked this profile Public.
  /// Default false (Private). Other call sites keep the default.
  final bool isPublic;

  /// Flâsh fork only (v0.2): true when this profile was successfully
  /// published to the Flâsh Hiddify pool. Default false.
  final bool isPublished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    // Flâsh fork only (v0.3): derive Public/Published from Preferences
    // here, not from the call site. ProfilesModal and the Home main card
    // used to create ProfileTile without isPublic/isPublished, so the
    // menu always said "Mark as Public" and Publish never appeared in
    // the sheet the user actually uses on mobile. Watching prefs here
    // makes every call site correct; the constructor params are kept
    // and OR-ed in so ProfilesPage's explicit values still work.
    final flashPublicIds = ref.watch(Preferences.flashPublicProfileIds);
    final flashPublishedIds = ref.watch(Preferences.flashPublishedProfileIds);
    final effectiveIsPublic = isPublic || flashPublicIds.contains(profile.id);
    final effectiveIsPublished = isPublished || flashPublishedIds.contains(profile.id);

    final selectActiveMutation = useMutation(
      initialOnFailure: (err) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.presentShortError(err));
      },
      initialOnSuccess: () {
        if (context.mounted && context.canPop()) context.pop();
      },
    );

    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };

    final showActionButton = profile is RemoteProfileEntity || !isMain;

    void handleTap() {
      if (isMain) {
        if (Breakpoint(context).isMobile()) {
          ref.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview();
        } else {
          context.goNamed('profiles');
        }
        return;
      }
      if (selectActiveMutation.state.isInProgress) return;
      selectActiveMutation.setFuture(ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id));
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('home');
      }
    }

    // Provider links (profile-web-page-url / support-url) show as separate pills
    // below the main card, for remote profiles.
    final RemoteProfileEntity? remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    final bool showLinks =
        ProfileTileConst.showProviderLinks &&
        isMain &&
        remote != null &&
        ((remote.webPageUrl?.isNotEmpty ?? false) || (remote.supportUrl?.isNotEmpty ?? false));

    final card = Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: profile.active ? BorderSide(color: theme.colorScheme.outline) : BorderSide.none,
        borderRadius: showLinks ? ProfileTileConst.topOnlyBorderRadius : ProfileTileConst.cardBorderRadius,
      ),
      elevation: profile.active ? 0 : 1,
      child: IntrinsicHeight(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showActionButton) ...[
                SizedBox(
                  width: 48,
                  child: Semantics(
                    sortKey: const OrdinalSortKey(1),
                    child: ProfileActionButton(
                      profile,
                      !isMain,
                      squareBottom: showLinks,
                      isPublic: effectiveIsPublic,
                      isPublished: effectiveIsPublished,
                    ),
                  ),
                ),
                if (profile.active) VerticalDivider(width: 1, color: theme.colorScheme.outline) else const Gap(1),
              ],
              Expanded(
                child: _body(context, t, theme, subInfo, showActionButton, handleTap, showLinks, effectiveIsPublic, effectiveIsPublished),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: showLinks
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                card,
                ProfileLinkButtons(webPageUrl: remote.webPageUrl, supportUrl: remote.supportUrl),
              ],
            )
          : card,
    );
  }

  /// The tappable content: the profile name (wrapped with a dropdown
  /// affordance on the main card) followed by the subscription info.
  Widget _body(
    BuildContext context,
    TranslationsEn t,
    ThemeData theme,
    SubscriptionInfo? subInfo,
    bool showActionButton,
    VoidCallback onTap,
    bool squareBottom,
    bool effectiveIsPublic,
    bool effectiveIsPublished,
  ) {
    return Semantics(
      button: true,
      sortKey: isMain ? const OrdinalSortKey(0) : null,
      focused: isMain,
      liveRegion: isMain,
      namesRoute: isMain,
      label: isMain ? t.pages.profiles.viewAllProfiles : null,
      child: InkWell(
        borderRadius: showActionButton
            ? ProfileTileConst.endBorderRadius(Directionality.of(context), squareBottom: squareBottom)
            : (squareBottom ? ProfileTileConst.topOnlyBorderRadius : ProfileTileConst.cardBorderRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(t, theme, effectiveIsPublic, effectiveIsPublished),
              if (subInfo != null) ...[
                const Gap(4),
                RemainingTrafficIndicator(subInfo.ratio),
                const Gap(4),
                ProfileSubscriptionInfo(subInfo),
                const Gap(4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Profile name with a trailing affordance: a dropdown on the main card, or a
  /// pin badge on list rows when the profile is pinned.
  Widget _title(TranslationsEn t, ThemeData theme, bool effectiveIsPublic, bool effectiveIsPublished) {
    final nameText = Text(
      profile.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null),
      semanticsLabel: isMain || profile.active
          ? t.pages.profiles.activeProfileName(name: profile.name)
          : t.pages.profiles.nonActiveProfileName(name: profile.name),
    );

    final Widget? trailing = isMain
        ? const Icon(Icons.arrow_drop_down_rounded)
        : profile.pinned
        ? Icon(Icons.push_pin, size: 16, color: theme.colorScheme.onSurfaceVariant)
        : null;

    // Flâsh fork only: a 🌍 chip on Public profiles, nothing extra on Private.
    if (effectiveIsPublic) {
      final row = Row(
        children: [
          Expanded(child: nameText),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Text(effectiveIsPublished ? '🌍✓' : '🌍', semanticsLabel: effectiveIsPublished ? 'Public, published' : 'Public'),
          ),
          if (trailing != null) Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: trailing),
        ],
      );
      if (!isMain) return row;
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row);
    }

    if (trailing == null) return nameText;

    final row = Row(
      children: [
        Expanded(child: nameText),
        Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: trailing),
      ],
    );
    if (!isMain) return row;

    // On the main card the title is wrapped so it reads as a single affordance.
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row);
  }
}

class ProfileActionButton extends HookConsumerWidget {
  const ProfileActionButton(
    this.profile,
    this.showAllActions, {
    super.key,
    this.squareBottom = false,
    this.isPublic = false,
    this.isPublished = false,
  });

  final ProfileEntity profile;
  final bool showAllActions;

  /// Flâsh fork only, forwarded to the actions menu.
  final bool isPublic;

  /// Flâsh fork only (v0.2), forwarded to the actions menu.
  final bool isPublished;

  /// Zeroes this button's bottom corner, matching the card when a link chip
  /// is attached flush below it.
  final bool squareBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // Flâsh fork only (v0.3): same self-watching fix as ProfileTile —
    // derive Public/Published from Preferences so the menu is correct
    // even when a call site omits the params.
    final effectiveIsPublic = isPublic || ref.watch(Preferences.flashPublicProfileIds).contains(profile.id);
    final effectiveIsPublished = isPublished || ref.watch(Preferences.flashPublishedProfileIds).contains(profile.id);
    final update = ref.watch(updateProfileNotifierProvider(profile.id));
    final isUpdating = update.isLoading;
    // Success/failure flash is derived straight from the provider state, which
    // UpdateProfileNotifier holds for 2s then resets. It lives in the provider
    // (not widget state), so it survives the list re-sorting after an update.
    final bool? outcome = isUpdating
        ? null
        : update.hasError
        ? false
        : (update.value != null ? true : null);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.6, curve: Curves.easeOut),
          reverseCurve: Curves.easeIn,
        ),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn),
          child: child,
        ),
      ),
      // Expand children so the interactive leading keeps its full tap target.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: _leading(context, ref, t, isUpdating, outcome, effectiveIsPublic, effectiveIsPublished),
    );
  }

  /// The current leading content. Each state carries a distinct key so the
  /// [AnimatedSwitcher] cross-fades between them.
  Widget _leading(BuildContext context, WidgetRef ref, TranslationsEn t, bool isUpdating, bool? outcome, bool effectiveIsPublic, bool effectiveIsPublished) {
    if (profile case RemoteProfileEntity()) {
      // While updating, the leading is a spinning indicator; its action is blocked.
      if (isUpdating) {
        return Semantics(
          key: const ValueKey('updating'),
          label: t.pages.profiles.update,
          liveRegion: true,
          child: Tooltip(message: t.pages.profiles.update, child: const _UpdatingIndicator()),
        );
      }

      // Transient success/failure feedback shown for 2s right after the spinner.
      if (outcome case final success?) {
        return Semantics(
          key: ValueKey(success),
          label: success ? t.pages.profiles.msg.update.success : t.pages.profiles.msg.update.failure,
          liveRegion: true,
          child: Icon(
            success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: success ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        );
      }

      if (!showAllActions) {
        return Semantics(
          key: const ValueKey('update'),
          button: true,
          child: Tooltip(
            message: t.pages.profiles.update,
            child: InkWell(
              borderRadius: ProfileTileConst.startBorderRadius(Directionality.of(context), squareBottom: squareBottom),
              onTap: () => ref
                  .read(updateProfileNotifierProvider(profile.id).notifier)
                  .updateProfile(profile as RemoteProfileEntity),
              child: const Icon(Icons.sync_rounded),
            ),
          ),
        );
      }
    }
    return ProfileActionsMenu(
      profile,
      (context, toggleVisibility, _) {
        return Semantics(
          button: true,
          child: Tooltip(
            message: MaterialLocalizations.of(context).showMenuTooltip,
            child: InkWell(
              borderRadius: ProfileTileConst.startBorderRadius(Directionality.of(context), squareBottom: squareBottom),
              onTap: toggleVisibility,
              child: Icon(AdaptiveIcon(context).more),
            ),
          ),
        );
      },
      key: const ValueKey('menu'),
      isPublic: effectiveIsPublic,
      isPublished: effectiveIsPublished,
    );
  }
}

/// A minimal, continuously spinning icon shown in the leading slot while a
/// remote profile is being updated.
class _UpdatingIndicator extends StatefulWidget {
  const _UpdatingIndicator();

  @override
  State<_UpdatingIndicator> createState() => _UpdatingIndicatorState();
}

class _UpdatingIndicatorState extends State<_UpdatingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: ReverseAnimation(_controller),
      child: Icon(Icons.sync_rounded, color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class ProfileActionsMenu extends HookConsumerWidget {
  const ProfileActionsMenu(
    this.profile,
    this.builder, {
    super.key,
    this.child,
    this.isPublic = false,
    this.isPublished = false,
  });

  final ProfileEntity profile;
  final AdaptiveMenuBuilder builder;
  final Widget? child;

  /// Flâsh fork only: whether this profile is currently Public.
  final bool isPublic;

  /// Flâsh fork only (v0.2): whether this profile was published to the pool.
  final bool isPublished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    // Flâsh fork only (v0.3): derive Public/Published from Preferences
    // here too, so the menu is correct even when a call site passes the
    // defaults. The toggle flips the CURRENT prefs state, never a stale
    // prop: tapping "Mark as Public" on an already-Public profile used
    // to be a no-op that just closed the menu.
    final effectiveIsPublic = isPublic || ref.watch(Preferences.flashPublicProfileIds).contains(profile.id);
    final effectiveIsPublished = isPublished || ref.watch(Preferences.flashPublishedProfileIds).contains(profile.id);

    final menuItems = [
      AdaptiveMenuItem(
        title: profile.pinned ? t.common.unpin : t.common.pin,
        leadingIcon: Icon(profile.pinned ? Icons.push_pin : Icons.push_pin_outlined),
        onTap: () => ref.read(profilesNotifierProvider.notifier).togglePin(profile),
      ),
      // Flâsh fork only: Private/Public toggle. Explicit user tap only;
      // nothing here publishes to any server, and Private is the default.
      AdaptiveMenuItem(
        title: effectiveIsPublic ? '🔒 Mark as Private' : '🌍 Mark as Public',
        leadingIcon: Icon(effectiveIsPublic ? Icons.lock_outline_rounded : Icons.public_rounded),
        onTap: () async {
          final current = ref.read(Preferences.flashPublicProfileIds);
          final makePublic = !current.contains(profile.id);
          final next = flashTogglePublic(current, profile.id, makePublic);
          await ref.read(Preferences.flashPublicProfileIds.notifier).update(next);
        },
      ),
      // Flâsh fork only: Public export, visible only for Public profiles.
      // User tap only: shares the subscription link (remote) or the
      // profile name (local). No server publish, no bulk export.
      if (effectiveIsPublic)
        AdaptiveMenuItem(
          title: '🌍 Export Public',
          leadingIcon: const Icon(Icons.share_rounded),
          onTap: () async {
            final text = switch (profile) {
              RemoteProfileEntity(:final url, :final name) => LinkParser.generateSubShareLink(url, name),
              _ => profile.name,
            };
            if (text.isEmpty) return;
            try {
              await Share.share(text);
            } catch (_) {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
              }
            }
          },
        ),
      // Flâsh fork only (v0.2): publish to the NEW Flâsh Hiddify pool.
      // Visible only for Public profiles. Explicit user tap only, after
      // a confirmation warning that published links become public.
      // Remote profiles publish their subscription URL as ONE pool entry
      // labelled "subscription" (the app model exposes no node list);
      // local profiles publish the individual links extracted from their
      // raw config. Nothing is invented: if no publishable link is found,
      // publishing is refused with a clear message. Server errors are
      // shown verbatim; success is never faked.
      if (effectiveIsPublic)
        AdaptiveMenuItem(
          title: effectiveIsPublished ? '🌍 Publish to Pool ✓' : '🌍 Publish to Pool',
          leadingIcon: const Icon(Icons.public_rounded),
          onTap: () async {
            final notifications = ref.read(inAppNotificationControllerProvider);
            final poolUrl = ref.read(Preferences.flashPoolUrl);
            if (poolUrl.isEmpty) {
              notifications.showErrorToast('Pool URL မထည့်ရသေးပါ — Settings → 🌍 Flâsh Pool မှာ ထည့်ပါ');
              return;
            }
            final password = ref.read(Preferences.flashPoolPassword);
            if (password.isEmpty) {
              notifications.showErrorToast('Publish password မထည့်ရသေးပါ — Settings → 🌍 Flâsh Pool မှာ ထည့်ပါ');
              return;
            }
            final confirmed = await ref.read(dialogNotifierProvider.notifier).showConfirmation(
              title: '🌍 Publish to Pool',
              message:
                  'Published links become public — anyone with the pool URL '
                  'can fetch and use them. Publish "${profile.name}" to the '
                  'Flâsh Hiddify pool?',
            );
            if (!confirmed) return;
            // Build the publish entries for this profile.
            final entries = <({String name, String key})>[];
            switch (profile) {
              case RemoteProfileEntity(:final url):
                entries.add((name: profile.name, key: url));
              case LocalProfileEntity():
                try {
                  final repo = ref.read(profileRepositoryProvider).requireValue;
                  final raw = await repo.getRawConfig(profile.id).run();
                  raw.match(
                    (failure) => notifications.showErrorToast(t.presentShortError(failure)),
                    (config) {
                      for (final link in extractPublishableLinks(config)) {
                        entries.add((name: profile.name, key: link));
                      }
                    },
                  );
                } catch (e) {
                  notifications.showErrorToast(e.toString());
                  return;
                }
                if (entries.isEmpty) {
                  notifications.showErrorToast('No publishable link in this profile — nothing published');
                  return;
                }
            }
            final client = FlashPoolClient();
            var published = 0;
            var firstError = '';
            for (final entry in entries) {
              final result = await client.publishEntry(
                poolUrl: poolUrl,
                password: password,
                name: entry.name,
                key: entry.key,
              );
              if (result.ok) {
                published++;
              } else if (firstError.isEmpty) {
                firstError = result.error;
              }
            }
            if (published > 0) {
              final current = ref.read(Preferences.flashPublishedProfileIds);
              if (!current.contains(profile.id)) {
                await ref
                    .read(Preferences.flashPublishedProfileIds.notifier)
                    .update([...current, profile.id]);
              }
              notifications.showSuccessToast('🌍 Published $published to pool'
                  '${firstError.isEmpty ? '' : ' (some failed: $firstError)'}');
            } else {
              notifications.showErrorToast('Publish မရပါ: $firstError');
            }
          },
        ),
      if (profile case RemoteProfileEntity())
        AdaptiveMenuItem(
          title: t.common.update,
          leadingIcon: const Icon(Icons.sync_rounded),
          onTap: () {
            if (ref.read(updateProfileNotifierProvider(profile.id)).isLoading) {
              return;
            }
            ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile as RemoteProfileEntity);
          },
        ),
      AdaptiveMenuItem(
        title: t.common.share,
        leadingIcon: Icon(AdaptiveIcon(context).share),
        subItems: [
          if (profile case RemoteProfileEntity(:final url, :final name)) ...[
            AdaptiveMenuItem(
              title: t.pages.profiles.share.urlToClipboard,
              onTap: () async {
                final link = LinkParser.generateSubShareLink(url, name);
                if (link.isNotEmpty) {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ref
                        .read(inAppNotificationControllerProvider)
                        .showSuccessToast(t.common.msg.export.clipboard.success);
                  }
                }
              },
            ),
            AdaptiveMenuItem(
              title: t.pages.profiles.share.showUrlQr,
              onTap: () async {
                final link = LinkParser.generateSubShareLink(url, name);
                if (link.isNotEmpty) {
                  await ref.read(dialogNotifierProvider.notifier).showQrCode(link, title: name);
                }
              },
            ),
          ],
          AdaptiveMenuItem(
            title: t.pages.profiles.share.jsonToClipboard,
            onTap: () async => await ref.read(profilesNotifierProvider.notifier).exportConfigToClipboard(profile),
          ),
        ],
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.edit_rounded),
        title: t.common.edit,
        onTap: () {
          if (Breakpoint(context).isMobile()) context.pop();
          context.goNamed('profileDetails', pathParameters: {'id': profile.id});
        },
      ),
      AdaptiveMenuItem(
        leadingIcon: const Icon(Icons.delete_outline_rounded),
        title: t.common.delete,
        onTap: () async => await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: t.dialogs.confirmation.profile.delete.title,
              message: t.dialogs.confirmation.profile.delete.msg,
            )
            .then((deleteConfirmed) async {
              if (!deleteConfirmed) return;
              await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
            }),
      ),
    ];

    return AdaptiveMenu(builder: builder, items: menuItems, child: child);
  }
}

/// Provider links from the `profile-web-page-url` / `support-url` subscription
/// headers, rendered as a single full-width pill below the main card.
///
/// One link fills the row as a static chip. Two links share the slot and
/// swap every few seconds: the current chip slides fully up and out, then
/// the next slides down from the top into place.
class ProfileLinkButtons extends HookConsumerWidget {
  const ProfileLinkButtons({super.key, this.webPageUrl, this.supportUrl});

  final String? webPageUrl;
  final String? supportUrl;

  /// Top-line label:
  /// - Telegram (`t.me` / `telegram.me`): the path after the host, which covers
  ///   every form — `hiddify`, `c/2681822178/1`, `joinchat/xxx`, `+xxx`.
  /// - GitHub: the provider (repo owner) — e.g. `barry-far`.
  /// - anything else: the domain.
  static String _value(String url) {
    final uri = Uri.parse(url);
    final host = uri.host.startsWith("www.") ? uri.host.substring(4) : uri.host;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (const ["t.me", "telegram.me"].contains(host)) {
      return segments.isEmpty ? host : segments.join("/");
    }
    if (host == "github.com" && segments.isNotEmpty) {
      return segments.first;
    }
    return host;
  }

  /// Brand icon for the link's platform (leading), or null for a generic site.
  static IconData? _leadingIcon(String url) {
    final host = Uri.parse(url).host;
    final bare = host.startsWith("www.") ? host.substring(4) : host;
    if (const ["t.me", "telegram.me"].contains(bare)) return SimpleIcons.telegram;
    if (bare == "github.com") return SimpleIcons.github;
    return null;
  }

  /// Confirm before opening a subscription-provided link. Curated/trusted links
  /// (see [TrustedLinks]) get a light confirmation; anything else gets a serious
  /// anti-impersonation warning with a countdown, so scammers can't pass off a
  /// look-alike channel/site as an official one.
  static Future<void> _confirmAndOpen(WidgetRef ref, TranslationsEn t, String url) async {
    final notifier = ref.read(dialogNotifierProvider.notifier);
    final bool confirmed;
    if (TrustedLinks.isTrusted(url)) {
      confirmed = await notifier.showConfirmation(
        title: t.components.subscriptionInfo.openLinkTitle,
        message: url,
        positiveBtnTxt: t.components.subscriptionInfo.openLinkAction,
      );
    } else {
      confirmed = await notifier.showUnknownDomainsWarning(url: url);
    }
    if (confirmed) await UriUtils.tryLaunch(Uri.parse(url));
  }

  static const _chipRadius = BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12));

  static Widget _chip(ThemeData theme, VoidCallback onTap, String url, String title) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: _chipRadius,
      border: Border(
        left: BorderSide(color: theme.colorScheme.outline),
        right: BorderSide(color: theme.colorScheme.outline),
        bottom: BorderSide(color: theme.colorScheme.outline),
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: _chipRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (_leadingIcon(url) case final icon?) ...[
                Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
                const Gap(8),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    // const Gap(1),
                    Text(
                      _value(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              const Gap(4),
              Icon(Icons.open_in_new_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final items = [
      if (webPageUrl case final url? when url.isNotEmpty) (url, t.components.subscriptionInfo.openWebPage),
      if (supportUrl case final url? when url.isNotEmpty) (url, t.components.subscriptionInfo.support),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) {
      final (url, title) = items.single;
      return SizedBox(
        width: double.infinity,
        child: _chip(Theme.of(context), () => _confirmAndOpen(ref, t, url), url, title),
      );
    }
    return _LinkChipCarousel(items: items);
  }
}

/// Cycles [items] one at a time: holds for [holdDuration], slides fully out
/// upward over [slideDuration], swaps content while hidden, then slides the
/// next item down from the top into place.
class _LinkChipCarousel extends HookConsumerWidget {
  const _LinkChipCarousel({required this.items});

  final List<(String url, String title)> items;

  static const _holdDuration = Duration(seconds: 10);
  static const _slideDuration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final index = useState(0);
    final offset = useState(Offset.zero);
    // Paused while the confirmation dialog is open, so the chip doesn't swap
    // out from under the URL the user is reviewing.
    final paused = useState(false);

    useEffect(() {
      var active = true;
      Future<void> loop() async {
        while (active) {
          await Future.delayed(_holdDuration);
          while (active && paused.value) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
          if (!active) return;
          offset.value = const Offset(0, -1);
          await Future.delayed(_slideDuration);
          if (!active) return;
          index.value = (index.value + 1) % items.length;
          offset.value = Offset.zero;
        }
      }

      loop();
      return () => active = false;
    }, [items.length]);

    final (url, title) = items[index.value];
    return SizedBox(
      width: double.infinity,
      child: ClipRect(
        child: AnimatedSlide(
          offset: offset.value,
          duration: _slideDuration,
          curve: Curves.easeInOut,
          child: ProfileLinkButtons._chip(
            theme,
            () async {
              paused.value = true;
              await ProfileLinkButtons._confirmAndOpen(ref, t, url);
              if (context.mounted) paused.value = false;
            },
            url,
            title,
          ),
        ),
      ),
    );
  }
}

class ProfileSubscriptionInfo extends HookConsumerWidget {
  const ProfileSubscriptionInfo(this.subInfo, {super.key});

  final SubscriptionInfo subInfo;

  (String, Color?) remainingText(TranslationsEn t, ThemeData theme) {
    if (subInfo.isExpired) {
      return (t.components.subscriptionInfo.expired, theme.colorScheme.error);
    } else if (subInfo.ratio >= 1) {
      return (t.components.subscriptionInfo.noTraffic, theme.colorScheme.error);
    } else if (subInfo.remaining.inDays > 365) {
      return (t.components.subscriptionInfo.remainingUnlimited, null);
    } else {
      return (t.components.subscriptionInfo.remainingDuration(days: subInfo.remaining.inDays), null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final remaining = remainingText(t, theme);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Flexible(
            child: Text(
              subInfo.total >
                      10 *
                          1099511627776 //10TB
                  ? "∞ GiB"
                  : subInfo.consumption.sizeOf(subInfo.total),
              semanticsLabel: t.components.subscriptionInfo.remainingTrafficSemanticLabel(
                consumed: subInfo.consumption.sizeGB(),
                total: subInfo.total.sizeGB(),
              ),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Flexible(
          child: Text(
            remaining.$1,
            style: theme.textTheme.bodySmall?.copyWith(color: remaining.$2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// TODO change colors
class RemainingTrafficIndicator extends StatelessWidget {
  const RemainingTrafficIndicator(this.ratio, {super.key});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: ratio, borderRadius: BorderRadius.circular(16), minHeight: 6);
  }
}
