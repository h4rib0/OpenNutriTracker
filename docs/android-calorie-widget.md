# Android home-screen widgets

Four read-only widgets show today's figures from Home (#832):

| Widget | Size | Shows |
| --- | --- | --- |
| Calories | 2×2 | Ring with kcal left (or too much), carbs / fat / protein eaten / goal |
| Calories and macros | 4×2 | Ring, and a progress bar per macro |
| Calories, one line | 4×1 | kcal left and the three macros as text |
| Today | 4×4 | Goal, supplied, burned, macro bars, kcal per meal, *Add* and *Water* buttons |

Light and dark follow the system theme (`values-night/calorie_widget_colors.xml`).

## Data

The widgets cannot open the encrypted Hive database, and Flutter may not be running while they draw. Home writes the same snapshot the iOS widget reads ([`ios-calorie-widget.md`](ios-calorie-widget.md)) whenever it finishes loading, into the `home_widget` plugin's shared preferences:

- `ont_calorie_snapshot` — `CalorieWidgetSnapshot`: day, offset, eaten and goal kcal, and for Android `macros` (`[eaten, goal]` grams per macro), `burned`, `water` (`[ml, goal]`) and `meals` (kcal per meal). The iOS widget ignores the Android keys.
- `ont_calorie_labels` — `CalorieWidgetLabels`, already translated. The widgets hold no copy of their own, so they follow the app's language and Weblate; they fall back to English until the first write.

`CalorieWidget.kt` only renders that snapshot. A snapshot of an earlier logical day is shown as the "Open the app" placeholder.

## Updates

- After every write, `HomeWidgetCalorieStore` asks all four providers to redraw.
- It also schedules a redraw at the day boundary (`HomeWidget.scheduleWidgetUpdates`, handled by `HomeWidgetScheduledUpdateReceiver` in the manifest), so a past day's figures do not stay up until the app is opened. Without the exact-alarm permission, which the app does not request, Android may run it a little late.
- `updatePeriodMillis` (30 min) is the system's own fallback.

## Taps

The widgets launch `MainActivity` with `opennutritracker://widget/<action>`; `MainScreen` follows it (`CalorieWidgetLink`):

- `open` — the widget body: Home.
- `add-food` — the add-item sheet, as the + button.
- `add-water` — the water dialog.

Two details make this work from every state:

- `flutter_deeplinking_enabled` is off for `MainActivity`. Otherwise Flutter also pushes the URI as a named route, which does not exist, and the navigator breaks. The app has no deep links of its own.
- A tap that reaches a restored activity arrives through `onNewIntent` before Dart listens, and the plugin forwards it only to a listener that is already there. `MainActivity` keeps such an intent as the activity's intent and stamps every tap (`?at=`), so `MainScreen` reads it once the screen is up and follows each tap exactly once.

Testing note: `adb shell am force-stop` cancels the widgets' pending intents until they are redrawn. Use `adb shell am kill` to simulate the system ending the process.
