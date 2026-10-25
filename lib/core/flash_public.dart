/// Flâsh fork only: Private/Public profile logic.
///
/// Pure functions with no Flutter, Riverpod or storage dependency, so they
/// are unit-testable without a device. The persisted list of public ids
/// lives in [Preferences.flashPublicProfileIds]; absent id = Private.
///
/// Private means: not a member of the Public list, never auto-published,
/// never auto-shared. It does NOT remove upstream's manual per-profile
/// share menu (URL/QR/JSON), which is a separate user-initiated action.
enum FlashProfileFilter { all, private, public }

/// True when a profile with [isPublic] passes [filter].
bool flashProfileVisible(FlashProfileFilter filter, bool isPublic) {
  switch (filter) {
    case FlashProfileFilter.all:
      return true;
    case FlashProfileFilter.private:
      return !isPublic;
    case FlashProfileFilter.public:
      return isPublic;
  }
}

/// Return a new id list with [id] marked public (or private).
/// No duplicates; removing an absent id is a no-op.
List<String> flashTogglePublic(List<String> ids, String id, bool makePublic) {
  if (makePublic) {
    if (ids.contains(id)) return List<String>.from(ids);
    return [...ids, id];
  }
  return ids.where((e) => e != id).toList();
}

/// Return a new id list with [id] removed (used on profile delete).
List<String> flashRemovePublicId(List<String> ids, String id) => flashTogglePublic(ids, id, false);
