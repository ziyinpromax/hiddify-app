import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/flash_public.dart';

void main() {
  group('flashProfileVisible', () {
    test('all passes both', () {
      expect(flashProfileVisible(FlashProfileFilter.all, true), isTrue);
      expect(flashProfileVisible(FlashProfileFilter.all, false), isTrue);
    });
    test('private passes only private', () {
      expect(flashProfileVisible(FlashProfileFilter.private, false), isTrue);
      expect(flashProfileVisible(FlashProfileFilter.private, true), isFalse);
    });
    test('public passes only public', () {
      expect(flashProfileVisible(FlashProfileFilter.public, true), isTrue);
      expect(flashProfileVisible(FlashProfileFilter.public, false), isFalse);
    });
  });

  group('flashTogglePublic', () {
    test('marking public adds once, no duplicates', () {
      final once = flashTogglePublic([], 'a', true);
      expect(once, ['a']);
      expect(flashTogglePublic(once, 'a', true), ['a']);
    });
    test('marking private removes, absent is a no-op', () {
      expect(flashTogglePublic(['a', 'b'], 'a', false), ['b']);
      expect(flashTogglePublic(['b'], 'a', false), ['b']);
    });
    test('does not mutate the input list', () {
      final input = ['a'];
      flashTogglePublic(input, 'b', true);
      expect(input, ['a']);
    });
  });

  group('flashRemovePublicId', () {
    test('removes on delete', () {
      expect(flashRemovePublicId(['a', 'b'], 'a'), ['b']);
    });
  });
}
