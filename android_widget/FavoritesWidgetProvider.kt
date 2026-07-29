package de.gio.fivembrowser.fivem_browser

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

// Reads the "favoritesJson" key the Flutter side writes via
// HomeWidget.saveWidgetData - a JSON array of up to 4 objects with "name"
// and "players" string fields, already formatted for direct display.
class FavoritesWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rows = listOf(
            Triple(R.id.widget_row1, R.id.widget_row1_name, R.id.widget_row1_players),
            Triple(R.id.widget_row2, R.id.widget_row2_name, R.id.widget_row2_players),
            Triple(R.id.widget_row3, R.id.widget_row3_name, R.id.widget_row3_players),
            Triple(R.id.widget_row4, R.id.widget_row4_name, R.id.widget_row4_players),
        )
        val servers = try {
            val json = widgetData.getString("favoritesJson", null)
            if (json != null) JSONArray(json) else JSONArray()
        } catch (e: Exception) {
            JSONArray()
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.favorites_widget_layout)
            views.setViewVisibility(R.id.widget_empty, if (servers.length() == 0) View.VISIBLE else View.GONE)
            for ((index, ids) in rows.withIndex()) {
                val (rowId, nameId, playersId) = ids
                if (index < servers.length()) {
                    val entry = servers.getJSONObject(index)
                    views.setViewVisibility(rowId, View.VISIBLE)
                    views.setTextViewText(nameId, entry.optString("name"))
                    views.setTextViewText(playersId, entry.optString("players"))
                } else {
                    views.setViewVisibility(rowId, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
