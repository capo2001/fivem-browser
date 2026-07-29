package de.gio.fivembrowser.fivem_browser

import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

// Shared by both FavoritesWidgetProvider (4 rows) and
// FavoritesMiniWidgetProvider (1 row) - both read the same "favoritesJson"
// payload the Flutter side writes via HomeWidget.saveWidgetData.

data class WidgetRow(val rowId: Int, val iconId: Int, val nameId: Int, val playersId: Int)

fun parseFavorites(widgetData: SharedPreferences): JSONArray {
    return try {
        val json = widgetData.getString("favoritesJson", null)
        if (json != null) JSONArray(json) else JSONArray()
    } catch (e: Exception) {
        JSONArray()
    }
}

// The server logo isn't reachable from native code directly, so the
// Flutter side downloads it and embeds it as Base64 in the same JSON
// entry; here it's just decoded back into a Bitmap.
fun decodeIcon(entry: JSONObject): Bitmap? {
    val icon = entry.optString("icon", "")
    if (icon.isEmpty()) return null
    return try {
        val bytes = Base64.decode(icon, Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    } catch (e: Exception) {
        null
    }
}
