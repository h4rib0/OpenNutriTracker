import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_link.dart';

/// #832: the links the Android widgets launch the app with.
void main() {
  test('reads each widget action', () {
    expect(
      CalorieWidgetLink.parse(Uri.parse('opennutritracker://widget/open')),
      CalorieWidgetLink.open,
    );
    expect(
      CalorieWidgetLink.parse(Uri.parse('opennutritracker://widget/add-food')),
      CalorieWidgetLink.addFood,
    );
    expect(
      CalorieWidgetLink.parse(Uri.parse('opennutritracker://widget/add-water')),
      CalorieWidgetLink.addWater,
    );
  });

  test('an unknown action from another widget version opens Home', () {
    expect(
      CalorieWidgetLink.parse(Uri.parse('opennutritracker://widget/scan')),
      CalorieWidgetLink.open,
    );
    expect(
      CalorieWidgetLink.parse(Uri.parse('opennutritracker://widget')),
      CalorieWidgetLink.open,
    );
  });

  test('anything that is not a widget link is ignored', () {
    expect(CalorieWidgetLink.parse(null), isNull);
    expect(
      CalorieWidgetLink.parse(Uri.parse('https://example.org/widget/open')),
      isNull,
    );
    expect(
      CalorieWidgetLink.parse(Uri.parse('opennutritracker://share/x')),
      isNull,
    );
  });

  group('isFresh', () {
    final now = DateTime(2026, 10, 29, 8, 37);
    Uri tapAt(DateTime at) => Uri.parse(
      'opennutritracker://widget/add-food?at=${at.millisecondsSinceEpoch}',
    );

    test('a tap from just now is followed', () {
      expect(
        CalorieWidgetLink.isFresh(
          tapAt(now.subtract(const Duration(seconds: 20))),
          now,
        ),
        isTrue,
      );
    });

    test('a tap replayed by a restored activity hours later is not', () {
      expect(
        CalorieWidgetLink.isFresh(
          tapAt(now.subtract(const Duration(hours: 10))),
          now,
        ),
        isFalse,
      );
    });

    test('a link without a stamp is taken as fresh', () {
      expect(
        CalorieWidgetLink.isFresh(
          Uri.parse('opennutritracker://widget/open'),
          now,
        ),
        isTrue,
      );
    });
  });
}
