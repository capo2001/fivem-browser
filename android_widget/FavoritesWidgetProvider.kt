package de.gio.fivembrowser.fivem_browser

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// Large (4x2) favorites widget - reads the "favoritesJson" key the Flutter
// side writes via HomeWidget.saveWidgetData: a JSON array of up to 4
// objects with "name", "players" and an optional Base64 "icon" field.
class FavoritesWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rows = listOf(
            WidgetRow(R.id.widget_row1, R.id.widget_row1_icon, R.id.widget_row1_name, R.id.widget_row1_players),
            WidgetRow(R.id.widget_row2, R.id.widget_row2_icon, R.id.widget_row2_name, R.id.widget_row2_players),
            WidgetRow(R.id.widget_row3, R.id.widget_row3_icon, R.id.widget_row3_name, R.id.widget_row3_players),
            WidgetRow(R.id.widget_row4, R.id.widget_row4_icon, R.id.widget_row4_name, R.id.widget_row4_players),
        )
        val servers = parseFavorites(widgetData)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.favorites_widget_layout)
            views.setViewVisibility(R.id.widget_empty, if (servers.length() == 0) View.VISIBLE else View.GONE)
            for ((index, row) in rows.withIndex()) {
                if (index < servers.length()) {
                    val entry = servers.getJSONObject(index)
                    views.setViewVisibility(row.rowId, View.VISIBLE)
                    views.setTextViewText(row.nameId, entry.optString("name"))
                    views.setTextViewText(row.playersId, entry.optString("players"))
                    val bitmap = decodeIcon(entry)
                    if (bitmap != null) {
                        views.setImageViewBitmap(row.iconId, bitmap)
                    } else {
                        views.setImageViewResource(row.iconId, R.mipmap.ic_launcher)
                    }
                } else {
                    views.setViewVisibility(row.rowId, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
