/// What a tap on an Android home-screen widget asks the app to do (#832).
///
/// The widgets launch the app with `opennutritracker://widget/<action>`;
/// the host part keeps these links apart from any other the app may get.
enum CalorieWidgetLink {
  /// The widget body: just open Home.
  open,

  /// The add button: open the add-item sheet, as the + button does.
  addFood,

  /// The water button: open the water dialog.
  addWater;

  static const scheme = 'opennutritracker';
  static const host = 'widget';

  /// How long after the tap a link is still followed. Android restores an
  /// activity with the intent it was launched with, so after the process
  /// was ended a later start from the launcher or the recents screen would
  /// otherwise replay a tap from hours ago.
  static const maxAge = Duration(minutes: 2);

  /// Whether [uri] is a tap from the last [maxAge]. `MainActivity` stamps
  /// every tap with `at` (milliseconds since the epoch); a link without a
  /// stamp is taken as fresh.
  static bool isFresh(Uri uri, DateTime now) {
    final at = int.tryParse(uri.queryParameters['at'] ?? '');
    if (at == null) return true;
    final age = now.difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age <= maxAge && !age.isNegative;
  }

  /// The link for [uri], or null when it is not a widget link. An unknown
  /// action from an older or newer widget opens Home.
  static CalorieWidgetLink? parse(Uri? uri) {
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    final action = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return switch (action) {
      'add-food' => CalorieWidgetLink.addFood,
      'add-water' => CalorieWidgetLink.addWater,
      _ => CalorieWidgetLink.open,
    };
  }
}
