import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/flash_public.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
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
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12).copyWith(bottom: 84),
                  separatorBuilder: (context, index) => const Gap(12),
                  itemBuilder: (context, index) => ProfileTile(
                    key: ValueKey(visible[index].id),
                    profile: visible[index],
                    isPublic: flashPublicIds.contains(visible[index].id),
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
