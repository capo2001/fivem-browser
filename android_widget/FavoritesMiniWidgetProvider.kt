package de.gio.fivembrowser.fivem_browser

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// Compact (roughly 2x1 cells) widget - shows just the single top favorite.
// Reads the same "favoritesJson" payload as FavoritesWidgetProvider.
class FavoritesMiniWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val servers = parseFavorites(widgetData)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.favorites_mini_widget_layout)
            if (servers.length() == 0) {
                views.setViewVisibility(R.id.mini_empty, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.mini_empty, View.GONE)
                val entry = servers.getJSONObject(0)
                views.setTextViewText(R.id.mini_name, entry.optString("name"))
                views.setTextViewText(R.id.mini_players, entry.optString("players"))
                val bitmap = decodeIcon(entry)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.mini_icon, bitmap)
                } else {
                    views.setImageViewResource(R.id.mini_icon, R.mipmap.ic_launcher)
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
