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
}
