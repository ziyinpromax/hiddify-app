import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/flash_pool.dart';
import 'package:hiddify/core/flash_public.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfilesPage extends HookConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);
    // Flâsh fork only: Private/Public filter. Default shows all; the
    // public-id list is never auto-populated (absent id = Private).
    final flashFilter = useState(FlashProfileFilter.all);
    final flashPublicIds = ref.watch(Preferences.flashPublicProfileIds);
    final flashPublishedIds = ref.watch(Preferences.flashPublishedProfileIds);
    // Flâsh fork only (v0.2): pool fetch status line.
    final flashPoolStatus = useState<String>('');

    ref.listen(hasAnyProfileProvider, (_, next) {
      if (next.value == false) {
        context.goNamed('home');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.profiles.title),
        actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.sync_rounded),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          IconButton(
            onPressed: () => ref.read(dialogNotifierProvider.notifier).showSortProfiles(),
            icon: const Icon(Icons.sort_rounded),
            tooltip: t.common.sort,
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async => await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
        label: Text(t.pages.profiles.add),
        icon: const Icon(Icons.add_rounded),
      ),
      body: asyncProfiles.when(
        data: (data) {
          final visible = data
              .where((p) => flashProfileVisible(flashFilter.value, flashPublicIds.contains(p.id)))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SegmentedButton<FlashProfileFilter>(
                  segments: const [
                    ButtonSegment(value: FlashProfileFilter.all, label: Text('All')),
                    ButtonSegment(value: FlashProfileFilter.private, label: Text('🔒 Private')),
                    ButtonSegment(value: FlashProfileFilter.public, label: Text('🌍 Public')),
                  ],
                  selected: {flashFilter.value},
                  onSelectionChanged: (selected) => flashFilter.value = selected.first,
                ),
              ),
              // Flâsh fork only (v0.2): fetch from the NEW Flâsh Hiddify
              // pool. Adds fetched links as new profiles (de-dupe by link);
              // never overwrites existing profiles, never auto-connects.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final poolUrl = ref.read(Preferences.flashPoolUrl);
                        if (poolUrl.isEmpty) {
                          flashPoolStatus.value = 'Pool URL မထည့်ရသေးပါ — Settings → 🌍 Flâsh Pool မှာ ထည့်ပါ';
                          return;
                        }
                        flashPoolStatus.value = 'Pool မှ ယူနေသည်…';
                        try {
                          final entries = await FlashPoolClient().fetchPool(poolUrl);
                          final existingUrls = data
                              .whereType<RemoteProfileEntity>()
                              .map((p) => p.url)
                              .toSet();
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
                          await ref
                              .read(Preferences.flashPoolImportedKeys.notifier)
                              .update(imported.toList());
                          flashPoolStatus.value = 'Pool မှ $added ခု ထည့်ပြီးပြီ, $skipped ခု ကျော်လိုက်သည်';
                        } catch (e) {
                          flashPoolStatus.value = 'Pool ယူမရပါ: $e';
                        }
                      },
                      icon: const Icon(Icons.public_rounded),
                      label: const Text('🌍 Pool ယူမယ်'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        flashPoolStatus.value,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12).copyWith(bottom: 84),
                  separatorBuilder: (context, index) => const Gap(12),
                  itemBuilder: (context, index) => ProfileTile(
                    key: ValueKey(visible[index].id),
                    profile: visible[index],
                    isPublic: flashPublicIds.contains(visible[index].id),
                    isPublished: flashPublishedIds.contains(visible[index].id),
                  ),
                  itemCount: visible.length,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Text(t.presentShortError(error)),
      ),
    );
  }
}
