import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/core/flash_pool.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ConfigOptionSection {
  warp,
  fragment;

  static final _warpKey = GlobalKey(debugLabel: "warp-section-key");
  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.warp => _warpKey,
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // final scrollController = useScrollController();

    // useMemoized(
    //   () {
    //     if (section != null) {
    //       WidgetsBinding.instance.addPostFrameCallback(
    //         (_) {
    //           final box = section!.key.currentContext?.findRenderObject() as RenderBox?;

    //           final offset = box?.localToGlobal(Offset.zero);
    //           if (offset == null) return;
    //           final height = scrollController.offset + offset.dy - MediaQueryData.fromView(View.of(context)).padding.top - kToolbarHeight;
    //           scrollController.animateTo(
    //             height,
    //             duration: const Duration(milliseconds: 500),
    //             curve: Curves.decelerate,
    //           );
    //         },
    //       );
    //     }
    //   },
    // );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.title),
        actions: [
          MenuAnchor(
            menuChildren: <Widget>[
              SubmenuButton(
                menuChildren: <Widget>[
                  MenuItemButton(
                    onPressed: () async => await ref
                        .read(dialogNotifierProvider.notifier)
                        .showConfirmation(
                          title: t.common.msg.import.confirm,
                          message: t.dialogs.confirmation.settings.import.msg,
                        )
                        .then((shouldImport) async {
                          if (shouldImport) {
                            await ref.read(configOptionNotifierProvider.notifier).importFromClipboard();
                          }
                        }),
                    child: Text(t.pages.settings.options.import.clipboard),
                  ),
                  MenuItemButton(
                    onPressed: () async => await ref
                        .read(dialogNotifierProvider.notifier)
                        .showConfirmation(
                          title: t.common.msg.import.confirm,
                          message: t.dialogs.confirmation.settings.import.msg,
                        )
                        .then((shouldImport) async {
                          if (shouldImport) {
                            await ref.read(configOptionNotifierProvider.notifier).importFromJsonFile();
                          }
                        }),
                    child: Text(t.pages.settings.options.import.file),
                  ),
                ],
                child: Text(t.common.import),
              ),
              SubmenuButton(
                menuChildren: <Widget>[
                  MenuItemButton(
                    onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonClipboard(),
                    child: Text(t.pages.settings.options.export.anonymousToClipboard),
                  ),
                  MenuItemButton(
                    onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(),
                    child: Text(t.pages.settings.options.export.anonymousToFile),
                  ),
                  const PopupMenuDivider(),
                  MenuItemButton(
                    onPressed: () async => await ref
                        .read(configOptionNotifierProvider.notifier)
                        .exportJsonClipboard(excludePrivate: false),
                    child: Text(t.pages.settings.options.export.allToClipboard),
                  ),
                  MenuItemButton(
                    onPressed: () async =>
                        await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(excludePrivate: false),
                    child: Text(t.pages.settings.options.export.allToFile),
                  ),
                ],
                child: Text(t.common.export),
              ),
              const PopupMenuDivider(),
              MenuItemButton(
                child: Text(t.pages.settings.options.reset),
                onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).resetOption(),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: ListView(
        children: [
          // TipCard(message: t.settings.experimentalMsg),
          // Flâsh fork only (v0.2): pool URL + publish password for the
          // NEW Flâsh Hiddify pool. Opens a dialog; nothing is published
          // from here, and the password is never logged or exported.
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('🌍 Flâsh Pool'),
            subtitle: Text(
              ref.watch(Preferences.flashPoolUrl).isEmpty
                  ? 'Pool URL မထည့်ရသေးပါ — နှိပ်ပြီး ထည့်ပါ'
                  : ref.watch(Preferences.flashPoolUrl),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showFlashPoolSettingsDialog(context, ref),
          ),
          SettingsSection(
            title: t.pages.settings.general.title,
            icon: Icons.layers_rounded,
            namedLocation: context.namedLocation('general'),
          ),
          if (ref.watch(hasAnyProfileProvider).value ?? false)
            SettingsSection(
              title: t.pages.settings.chain.title,
              icon: Icons.webhook_rounded,
              subtitle: Text(t.pages.settings.chain.subtitle),
              namedLocation: context.namedLocation('chainOptions'),
            ),
          SettingsSection(
            title: t.pages.settings.routing.title,
            icon: Icons.route_rounded,
            namedLocation: context.namedLocation('routingOptions'),
          ),
          SettingsSection(
            title: t.pages.settings.dns.title,
            icon: Icons.dns_rounded,
            namedLocation: context.namedLocation('dnsOptions'),
          ),
          SettingsSection(
            title: t.pages.settings.inbound.title,
            icon: Icons.input_rounded,
            namedLocation: context.namedLocation('inboundOptions'),
          ),
          SettingsSection(
            title: t.pages.settings.tlsTricks.title,
            icon: Icons.content_cut_rounded,
            namedLocation: context.namedLocation('tlsTricks'),
          ),
          if (PlatformUtils.isIOS || PlatformUtils.isMacOS)
            Material(
              child: ListTile(
                title: Text(t.pages.settings.resetTunnel),
                leading: const Icon(Icons.autorenew_rounded),
                onTap: () async {
                  await ref.read(resetTunnelNotifierProvider.notifier).run();
                },
              ),
            ),
          if (Breakpoint(context).isMobile()) ...[
            SettingsSection(
              title: t.pages.logs.title,
              icon: Icons.description_rounded,
              namedLocation: context.namedLocation('logs'),
            ),
            SettingsSection(
              title: t.pages.about.title,
              icon: Icons.info_rounded,
              namedLocation: context.namedLocation('about'),
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    required this.namedLocation,
  });

  final String title;
  final Widget? subtitle;
  final IconData icon;
  final String namedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(namedLocation),
    );
  }
}

/// Flâsh fork only (v0.2): edit the pool URL + publish password.
/// The password field is obscured; both values are stored in the app's
/// preferences (not secure storage) and are never logged.
Future<void> showFlashPoolSettingsDialog(BuildContext context, WidgetRef ref) async {
  final urlController = TextEditingController(text: ref.read(Preferences.flashPoolUrl));
  final passwordController = TextEditingController(text: ref.read(Preferences.flashPoolPassword));
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('🌍 Flâsh Pool'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: urlController,
            decoration: const InputDecoration(
              labelText: 'Pool URL',
              hintText: 'https://flash-hiddify-pool.<subdomain>.workers.dev',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Publish password'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Published links become public — anyone with the pool URL can '
            'fetch and use them. Never publish a private subscription URL '
            'unless you intend it to become public.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
      ],
    ),
  );
  if (saved == true) {
    await ref.read(Preferences.flashPoolUrl.notifier).update(normalizePoolUrl(urlController.text));
    await ref.read(Preferences.flashPoolPassword.notifier).update(passwordController.text.trim());
  }
}
