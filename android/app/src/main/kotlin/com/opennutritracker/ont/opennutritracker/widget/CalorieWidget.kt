package com.opennutritracker.ont.opennutritracker.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import com.opennutritracker.ont.opennutritracker.MainActivity
import com.opennutritracker.ont.opennutritracker.R
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.math.abs
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android home-screen widgets (#832), in four sizes that read the same data.
 *
 * The app cannot be asked for figures while the widget draws: its database is
 * encrypted and Flutter may not be running. So Home writes a snapshot into the
 * plugin's shared preferences whenever it loads (`CalorieWidgetSnapshot` and
 * `CalorieWidgetLabels` on the Dart side), and these providers only render it.
 * The labels arrive translated, so no copy lives here.
 */
class CalorieWidgetSmallProvider : CalorieWidgetProvider(CalorieWidgetSize.SMALL)

class CalorieWidgetMediumProvider : CalorieWidgetProvider(CalorieWidgetSize.MEDIUM)

class CalorieWidgetStripProvider : CalorieWidgetProvider(CalorieWidgetSize.STRIP)

class CalorieWidgetLargeProvider : CalorieWidgetProvider(CalorieWidgetSize.LARGE)

enum class CalorieWidgetSize(val layout: Int) {
  SMALL(R.layout.calorie_widget_small),
  MEDIUM(R.layout.calorie_widget_medium),
  STRIP(R.layout.calorie_widget_strip),
  LARGE(R.layout.calorie_widget_large),
}

abstract class CalorieWidgetProvider(private val size: CalorieWidgetSize) : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val labels = CalorieWidgetLabels.read(widgetData)
    val snapshot = CalorieWidgetSnapshot.read(widgetData)?.takeIf { it.isCurrentAt(LocalDateTime.now()) }
    val extras = if (snapshot != null) PolarWidgetExtras.read(widgetData) else null
    val views = CalorieWidgetRenderer(context, size, labels, extras).render(snapshot)
    appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    PolarWidgetExtras.maybeRefresh(context, widgetData)
  }
}

/**
 * Fork-only: the Polar rows and status line Home (or the background
 * refresh) writes next to the snapshot — `polar_widget_extras.dart`.
 */
class PolarWidgetExtras(val status: String?, val details: List<Pair<String, String>>) {
  companion object {
    private const val EXTRAS_KEY = "ont_calorie_extras"
    private const val BASE_KEY = "ont_polar_widget_base"
    private const val REFRESHED_AT_KEY = "ont_polar_refreshed_at"
    private const val REFRESH_EVERY_MS = 14 * 60 * 1000L

    fun read(prefs: SharedPreferences): PolarWidgetExtras? =
        try {
          prefs.getString(EXTRAS_KEY, null)?.let { raw ->
            val json = JSONObject(raw)
            val rows = json.optJSONArray("details") ?: JSONArray()
            PolarWidgetExtras(
                json.optString("status").ifEmpty { null },
                (0 until rows.length()).mapNotNull { i ->
                  rows.optJSONArray(i)?.let { Pair(it.optString(0), it.optString(1)) }
                },
            )
          }
        } catch (e: Exception) {
          null
        }

    /**
     * Starts the Dart background refresh (InfluxDB → goal) when Polar is on
     * and the last computation is older than ~15 minutes. Every provider
     * redraws on the same schedule, so the time is claimed here first and
     * only one of them starts it.
     */
    fun maybeRefresh(context: Context, prefs: SharedPreferences) {
      if (!prefs.contains(BASE_KEY)) return
      val last = prefs.getString(REFRESHED_AT_KEY, null)?.toLongOrNull() ?: 0L
      val now = System.currentTimeMillis()
      if (now - last < REFRESH_EVERY_MS) return
      prefs.edit().putString(REFRESHED_AT_KEY, now.toString()).apply()
      try {
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("opennutritracker://widget/refresh")).send()
      } catch (e: Exception) {
        // The next redraw tries again.
      }
    }
  }
}

/** Keys and JSON shapes must match `calorie_widget_snapshot.dart`. */
data class CalorieWidgetSnapshot(
    val day: LocalDate,
    val offsetMinutes: Int,
    val consumedKcal: Int,
    val goalKcal: Int,
    val burnedKcal: Int,
    val carbs: Pair<Int, Int>,
    val fat: Pair<Int, Int>,
    val protein: Pair<Int, Int>,
    val waterMl: Int,
    val waterGoalMl: Int,
    val meals: List<Int>,
) {
  val leftKcal: Int
    get() = goalKcal - consumedKcal

  /** Same rule as `DayBoundaryCalc`: before the offset, it is still yesterday. */
  fun isCurrentAt(now: LocalDateTime): Boolean =
      now.minusMinutes(offsetMinutes.toLong()).toLocalDate() == day

  companion object {
    private const val KEY = "ont_calorie_snapshot"

    fun read(prefs: SharedPreferences): CalorieWidgetSnapshot? =
        try {
          prefs.getString(KEY, null)?.let { parse(JSONObject(it)) }
        } catch (e: Exception) {
          null
        }

    private fun parse(json: JSONObject): CalorieWidgetSnapshot? {
      if (!json.optBoolean("hasData")) return null
      val macros = json.optJSONObject("macros") ?: JSONObject()
      val water = json.optJSONArray("water")
      val meals = json.optJSONObject("meals") ?: JSONObject()
      return CalorieWidgetSnapshot(
          day = LocalDate.parse(json.getString("day")),
          offsetMinutes = json.optInt("offsetMinutes"),
          consumedKcal = json.optInt("consumed"),
          goalKcal = json.optInt("goal"),
          burnedKcal = json.optInt("burned"),
          carbs = pair(macros.optJSONArray("carbs")),
          fat = pair(macros.optJSONArray("fat")),
          protein = pair(macros.optJSONArray("protein")),
          waterMl = water?.optInt(0) ?: 0,
          waterGoalMl = water?.optInt(1) ?: 0,
          meals = listOf("breakfast", "lunch", "dinner", "snack").map { meals.optInt(it) },
      )
    }

    private fun pair(array: JSONArray?) = Pair(array?.optInt(0) ?: 0, array?.optInt(1) ?: 0)
  }
}

/** English until the app's first write; keys match `CalorieWidgetLabels.languageJson`. */
class CalorieWidgetLabels(private val json: JSONObject) {
  fun get(key: String, fallback: String): String = json.optString(key).ifEmpty { fallback }

  companion object {
    private const val KEY = "ont_calorie_labels"

    fun read(prefs: SharedPreferences): CalorieWidgetLabels =
        CalorieWidgetLabels(
            try {
              JSONObject(prefs.getString(KEY, null) ?: "{}")
            } catch (e: Exception) {
              JSONObject()
            },
        )
  }
}

class CalorieWidgetRenderer(
    private val context: Context,
    private val size: CalorieWidgetSize,
    private val labels: CalorieWidgetLabels,
    private val extras: PolarWidgetExtras? = null,
) {
  private val views = RemoteViews(context.packageName, size.layout)

  fun render(snapshot: CalorieWidgetSnapshot?): RemoteViews {
    bindLinks()
    if (snapshot == null) renderPlaceholder() else renderFigures(snapshot)
    return views
  }

  private fun bindLinks() {
    views.setOnClickPendingIntent(R.id.calorie_widget_root, launch("open"))
    if (size == CalorieWidgetSize.LARGE) {
      views.setOnClickPendingIntent(R.id.calorie_widget_add_food, launch("add-food"))
      views.setOnClickPendingIntent(R.id.calorie_widget_add_water, launch("add-water"))
      views.setTextViewText(R.id.calorie_widget_add_food_label, labels.get("add", "Add"))
    }
  }

  /** Matches `CalorieWidgetLink` on the Dart side. */
  private fun launch(action: String) =
      HomeWidgetLaunchIntent.getActivity(
          context,
          MainActivity::class.java,
          Uri.parse("opennutritracker://widget/$action"),
      )

  /** Before the first write, or once the stored day is over. */
  private fun renderPlaceholder() {
    views.setTextViewText(R.id.calorie_widget_left, "–")
    views.setTextViewText(R.id.calorie_widget_left_label, labels.get("openApp", "Open the app"))
    showRing(progress = 0, over = false)
    macroLabels()
    listOf(R.id.calorie_widget_carbs_value, R.id.calorie_widget_fat_value, R.id.calorie_widget_protein_value)
        .forEach { views.setTextViewText(it, "–") }
    listOf(R.id.calorie_widget_carbs_bar, R.id.calorie_widget_fat_bar, R.id.calorie_widget_protein_bar)
        .forEach { views.setProgressBar(it, 100, 0, false) }
    if (size == CalorieWidgetSize.LARGE) {
      views.setViewVisibility(R.id.calorie_widget_status, View.GONE)
      views.setViewVisibility(R.id.calorie_widget_detail1_row, View.GONE)
      views.setViewVisibility(R.id.calorie_widget_detail2_row, View.GONE)
      views.setViewVisibility(R.id.calorie_widget_detail3_row, View.GONE)
      views.setTextViewText(R.id.calorie_widget_goal_label, labels.get("goalTitle", "Goal"))
      views.setTextViewText(R.id.calorie_widget_goal_value, "–")
      views.setTextViewText(R.id.calorie_widget_supplied_label, labels.get("supplied", "supplied"))
      views.setTextViewText(R.id.calorie_widget_supplied_value, "–")
      mealLabels()
      listOf(
              R.id.calorie_widget_breakfast_value,
              R.id.calorie_widget_lunch_value,
              R.id.calorie_widget_dinner_value,
              R.id.calorie_widget_snack_value,
          )
          .forEach { views.setTextViewText(it, "–") }
      views.setTextViewText(R.id.calorie_widget_water_label, labels.get("water", "Water"))
    }
  }

  private fun renderFigures(s: CalorieWidgetSnapshot) {
    val unit = labels.get("unit", "kcal")
    val over = s.leftKcal < 0
    // The label says which side of the goal it is ("kcal too much"), as
    // Home does, so the figure itself carries no sign.
    views.setTextViewText(R.id.calorie_widget_left, "${abs(s.leftKcal)}")
    views.setTextViewText(
        R.id.calorie_widget_left_label,
        if (over) labels.get("kcalOver", "kcal too much") else labels.get("kcalLeft", "kcal left"),
    )
    if (size == CalorieWidgetSize.STRIP) {
      views.setTextColor(R.id.calorie_widget_left, color(if (over) R.color.calorie_widget_over else R.color.calorie_widget_text))
    }
    val share = if (s.goalKcal > 0) s.consumedKcal.toDouble() / s.goalKcal else 0.0
    showRing(progress = (share.coerceIn(0.0, 1.0) * 1000).toInt(), over = over)

    macroLabels()
    macro(R.id.calorie_widget_carbs_value, R.id.calorie_widget_carbs_bar, s.carbs)
    macro(R.id.calorie_widget_fat_value, R.id.calorie_widget_fat_bar, s.fat)
    macro(R.id.calorie_widget_protein_value, R.id.calorie_widget_protein_bar, s.protein)

    if (size == CalorieWidgetSize.LARGE) {
      views.setTextViewText(R.id.calorie_widget_goal_label, labels.get("goalTitle", "Goal"))
      views.setTextViewText(R.id.calorie_widget_goal_value, "${s.goalKcal} $unit")
      val rows = extras?.details?.takeIf { it.isNotEmpty() }
          ?: listOf(Pair(labels.get("burned", "burned"), if (s.burnedKcal > 0) "+${s.burnedKcal}" else ""))
      val detailIds = listOf(
          Triple(R.id.calorie_widget_detail1_row, R.id.calorie_widget_detail1_label, R.id.calorie_widget_detail1_value),
          Triple(R.id.calorie_widget_detail2_row, R.id.calorie_widget_detail2_label, R.id.calorie_widget_detail2_value),
          Triple(R.id.calorie_widget_detail3_row, R.id.calorie_widget_detail3_label, R.id.calorie_widget_detail3_value),
      )
      detailIds.forEachIndexed { i, (row, label, value) ->
        val entry = rows.getOrNull(i)
        detail(row, label, value, entry?.first ?: "", entry?.second?.ifEmpty { null })
      }
      val status = extras?.status
      views.setViewVisibility(R.id.calorie_widget_status, if (status == null) View.GONE else View.VISIBLE)
      if (status != null) views.setTextViewText(R.id.calorie_widget_status, status)
      views.setTextViewText(R.id.calorie_widget_supplied_label, labels.get("supplied", "supplied"))
      views.setTextViewText(R.id.calorie_widget_supplied_value, "${s.consumedKcal} $unit")
      mealLabels()
      listOf(
              R.id.calorie_widget_breakfast_value,
              R.id.calorie_widget_lunch_value,
              R.id.calorie_widget_dinner_value,
              R.id.calorie_widget_snack_value,
          )
          .zip(s.meals)
          .forEach { (id, kcal) -> views.setTextViewText(id, "$kcal") }
      val ml = labels.get("ml", "ml")
      views.setTextViewText(
          R.id.calorie_widget_water_label,
          if (s.waterGoalMl > 0) "${s.waterMl}/${s.waterGoalMl} $ml" else labels.get("water", "Water"),
      )
    }
  }

  private fun detail(row: Int, label: Int, value: Int, text: String, figure: String?) {
    if (figure == null) {
      views.setViewVisibility(row, View.GONE)
      return
    }
    views.setViewVisibility(row, View.VISIBLE)
    views.setTextViewText(label, text)
    views.setTextViewText(value, figure)
  }

  private fun showRing(progress: Int, over: Boolean) {
    views.setViewVisibility(R.id.calorie_widget_ring, if (over) View.GONE else View.VISIBLE)
    views.setViewVisibility(R.id.calorie_widget_ring_over, if (over) View.VISIBLE else View.GONE)
    views.setProgressBar(R.id.calorie_widget_ring, 1000, progress, false)
  }

  private fun macroLabels() {
    views.setTextViewText(R.id.calorie_widget_carbs_label, labels.get("carbsShort", "C"))
    views.setTextViewText(R.id.calorie_widget_fat_label, labels.get("fatShort", "F"))
    views.setTextViewText(R.id.calorie_widget_protein_label, labels.get("proteinShort", "P"))
  }

  private fun mealLabels() {
    views.setTextViewText(R.id.calorie_widget_breakfast_label, labels.get("breakfast", "Breakfast"))
    views.setTextViewText(R.id.calorie_widget_lunch_label, labels.get("lunch", "Lunch"))
    views.setTextViewText(R.id.calorie_widget_dinner_label, labels.get("dinner", "Dinner"))
    views.setTextViewText(R.id.calorie_widget_snack_label, labels.get("snack", "Snack"))
  }

  /** `66/20 g`, or `(66/20)g` on the one-line strip, red once over the goal. */
  private fun macro(valueId: Int, barId: Int, value: Pair<Int, Int>) {
    val (eaten, goal) = value
    val g = labels.get("gram", "g")
    val text = if (size == CalorieWidgetSize.STRIP) "($eaten/$goal)$g" else "$eaten/$goal $g"
    views.setTextViewText(valueId, text)
    views.setTextColor(valueId, color(if (eaten > goal) R.color.calorie_widget_over else R.color.calorie_widget_text))
    val percent = if (goal > 0) (eaten * 100 / goal).coerceIn(0, 100) else 0
    views.setProgressBar(barId, 100, percent, false)
  }

  private fun color(id: Int) = ContextCompat.getColor(context, id)
}
