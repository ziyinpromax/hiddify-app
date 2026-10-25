import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/flash_pool.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfilesModal extends HookConsumerWidget {
  const ProfilesModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);

    ref.listen(profilesNotifierProvider, (_, next) {
      if (next.hasValue && next.value!.isEmpty) {
        if (context.canPop()) context.pop();
      }
    });

    final initialSize = PlatformUtils.isDesktop ? .60 : .35;
    return SafeArea(
      child: asyncProfiles.when(
        data: (data) => DraggableScrollableSheet(
          initialChildSize: initialSize,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) => ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: Stack(
              children: [
                ListView.separated(
                  padding: const EdgeInsets.all(12).copyWith(bottom: 12 + 8 + 32),
                  separatorBuilder: (context, index) => const Gap(12),
                  controller: scrollController,
                  itemBuilder: (context, index) => ProfileTile(key: ValueKey(data[index].id), profile: data[index]),
                  itemCount: data.length,
                ),
                Positioned(
                  bottom: 0,
                  left: 16,
                  right: 16,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          label: Text(t.common.sort, maxLines: 1, overflow: TextOverflow.ellipsis),
                          icon: const Icon(Icons.sort_rounded),
                          onPressed: () => ref.read(dialogNotifierProvider.notifier).showSortProfiles(),
                        ),
                        FilledButton.icon(
                          label: Text(
                            t.pages.profiles.updateSubscriptions,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          icon: const Icon(Icons.sync_rounded),
                          onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
                        ),
                        // Flâsh fork only (v0.3): pool fetch in the modal.
                        // On mobile the ProfilesPage fetch button is
                        // unreachable (Profiles tab hidden from bottom
                        // nav), so the modal is the user's only path.
                        // Same logic as ProfilesPage: dedupe by link,
                        // never overwrite, never auto-connect.
                        FilledButton.icon(
                          label: const Text('🌍 Pool ယူမယ်', maxLines: 1, overflow: TextOverflow.ellipsis),
                          icon: const Icon(Icons.public_rounded),
                          onPressed: () async {
                            final notifications = ref.read(inAppNotificationControllerProvider);
                            final poolUrl = ref.read(Preferences.flashPoolUrl);
                            if (poolUrl.isEmpty) {
                              notifications.showErrorToast('Pool URL မထည့်ရသေးပါ — Settings → 🌍 Flâsh Pool မှာ ထည့်ပါ');
                              return;
                            }
                            try {
                              final entries = await FlashPoolClient().fetchPool(poolUrl);
                              final existingUrls = data.whereType<RemoteProfileEntity>().map((p) => p.url).toSet();
                              final imported = ref.read(Preferences.flashPoolImportedKeys).toSet();
                              var added = 0;
                              var skipped = 0;
                              for (final entry in entries) {
                                if (existingUrls.contains(entry.key) || imported.contains(entry.key)) {
                                  skipped++;
                                  continue;
                                }
                                await ref.read(addProfileNotifierProvider.notifier).addClipboard(entry.key);
                                if (ref.read(addProfileNotifierProvider).hasError) {
                                  skipped++;
                                  continue;
                                }
                                imported.add(entry.key);
                                added++;
                              }
                              await ref.read(Preferences.flashPoolImportedKeys.notifier).update(imported.toList());
                              notifications.showSuccessToast('Pool မှ $added ခု ထည့်ပြီးပြီ, $skipped ခု ကျော်လိုက်သည်');
                            } catch (e) {
                              notifications.showErrorToast('Pool ယူမရပါ: $e');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Text(t.presentShortError(error)),
      ),
    );
  }
}
