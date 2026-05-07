package com.memai.memai_android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Displays up to four pinned prompt-job titles from HomeWidget-backed prefs (Flutter [HomeWidget.saveWidgetData]).
 */
class PromptJobsWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val rowLayouts =
        intArrayOf(
            R.id.row_slot_0,
            R.id.row_slot_1,
            R.id.row_slot_2,
            R.id.row_slot_3,
        )
    val titles =
        intArrayOf(
            R.id.title_slot_0,
            R.id.title_slot_1,
            R.id.title_slot_2,
            R.id.title_slot_3,
        )

    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.prompt_jobs_widget)
      for (i in 0 until 4) {
        val tid = widgetData.getString("pinned_${i}_id", "") ?: ""
        val label = widgetData.getString("pinned_${i}_title", "") ?: ""
        views.setTextViewText(titles[i], if (label.isNotBlank()) label else "—")
        val uri =
            if (tid.isNotEmpty()) {
              Uri.parse("memai://prompt?templateId=$tid")
            } else {
              Uri.parse("memai://open")
            }
        val pi = launchPi(context, uri, REQUEST_BASE + i)
        views.setOnClickPendingIntent(rowLayouts[i], pi)
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  private fun launchPi(context: Context, uri: Uri, requestCode: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
    intent.data = uri
    intent.action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
    var flags = PendingIntent.FLAG_UPDATE_CURRENT
    if (Build.VERSION.SDK_INT >= 23) {
      flags = flags or PendingIntent.FLAG_IMMUTABLE
    }
    return PendingIntent.getActivity(context, requestCode, intent, flags)
  }

  companion object {
    private const val REQUEST_BASE = 9100
  }
}
