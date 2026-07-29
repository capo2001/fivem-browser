import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:home_widget/home_widget.dart';

const Color _kDarkBg = Color(0xFF070A0F);
const Color _kDarkSurface = Color(0xFF10141C);
const Color _kLightBg = Color(0xFFF3F4F6);
const Color _kLightSurface = Color(0xFFFFFFFF);
const Color _kLightFg = Color(0xFF14171C);
const double kRadius = 5;
const String kAppVersion = '1.1.0';

// Single fixed brand accent - no more per-theme accent colors, only
// light/dark/auto vary the background/foreground now.
const Color kAccent = Color(0xFFFF8A3D);

Color get kBg => AppState.I.isDark ? _kDarkBg : _kLightBg;
Color get kSurface => AppState.I.isDark ? _kDarkSurface : _kLightSurface;
// Foreground (text/icon) color - flips from white to near-black in the
// light theme. Not used for controls overlaid on server banner images
// (those stay a fixed white, matching photo-overlay conventions).
Color get kFg => AppState.I.isDark ? Colors.white : _kLightFg;

// Foreground color at a given alpha, boosted toward fully opaque when
// high-contrast mode is on (keeping some relative fade hierarchy intact
// rather than making everything solid white/black).
Color kFgAlpha(double alpha) {
  if (!AppState.I.highContrast) return kFg.withValues(alpha: alpha);
  final boosted = (alpha + (1 - alpha) * 0.7).clamp(0.0, 1.0);
  return kFg.withValues(alpha: boosted);
}

const String kFavoriteCheckTask = 'favoriteCheckTask';

// ---------------------------------------------------------------------------
// Theme mode (light / dark / auto - follows system)
// ---------------------------------------------------------------------------

const List<String> kThemeModes = ['light', 'dark', 'auto'];

IconData themeModeIcon(String mode) {
  switch (mode) {
    case 'light':
      return Icons.wb_sunny_outlined;
    case 'dark':
      return Icons.nightlight_outlined;
    default:
      return Icons.brightness_auto_outlined;
  }
}

// Old installs may still have a color-theme key ('silver', 'blue', ...)
// persisted from before the theme system was simplified to light/dark/
// auto - every one of those was a dark theme except 'light' itself.
String _migrateThemeMode(String stored) {
  if (kThemeModes.contains(stored)) return stored;
  return stored == 'light' ? 'light' : 'dark';
}

String themeModeLabelKey(String mode) {
  switch (mode) {
    case 'light':
      return 'themeLight';
    case 'dark':
      return 'themeDark';
    default:
      return 'themeAuto';
  }
}

// ---------------------------------------------------------------------------
// Localization (lightweight - no codegen, just a lookup table)
// ---------------------------------------------------------------------------

const Map<String, Map<String, String>> _strings = {
  'appName': {'de': 'Fserver', 'en': 'Fserver', 'fr': 'Fserver', 'es': 'Fserver', 'pl': 'Fserver', 'it': 'Fserver', 'pt': 'Fserver', 'nl': 'Fserver', 'tr': 'Fserver'},
  'serverList': {'de': 'Serverliste', 'en': 'Server list', 'fr': 'Liste des serveurs', 'es': 'Lista de servidores', 'pl': 'Lista serwerów', 'it': 'Lista server', 'pt': 'Lista de servidores', 'nl': 'Serverlijst', 'tr': 'Sunucu listesi'},
  'favorites': {'de': 'Favoriten', 'en': 'Favorites', 'fr': 'Favoris', 'es': 'Favoritos', 'pl': 'Ulubione', 'it': 'Preferiti', 'pt': 'Favoritos', 'nl': 'Favorieten', 'tr': 'Favoriler'},
  'favoritesSubtitle': {'de': 'Deine gespeicherten Server', 'en': 'Your saved servers', 'fr': 'Vos serveurs enregistrés', 'es': 'Tus servidores guardados', 'pl': 'Twoje zapisane serwery', 'it': 'I tuoi server salvati', 'pt': 'Seus servidores salvos', 'nl': 'Je opgeslagen servers', 'tr': 'Kaydettiğin sunucular'},
  'serverListSubtitle': {'de': 'Alle Server durchsuchen', 'en': 'Browse all servers', 'fr': 'Parcourir tous les serveurs', 'es': 'Explorar todos los servidores', 'pl': 'Przeglądaj wszystkie serwery', 'it': 'Sfoglia tutti i server', 'pt': 'Explore todos os servidores', 'nl': 'Blader door alle servers', 'tr': 'Tüm sunuculara göz at'},
  'settings': {'de': 'Einstellungen', 'en': 'Settings', 'fr': 'Paramètres', 'es': 'Ajustes', 'pl': 'Ustawienia', 'it': 'Impostazioni', 'pt': 'Configurações', 'nl': 'Instellingen', 'tr': 'Ayarlar'},
  'search': {'de': 'Server suchen', 'en': 'Search servers', 'fr': 'Rechercher un serveur', 'es': 'Buscar servidores', 'pl': 'Szukaj serwerów', 'it': 'Cerca server', 'pt': 'Pesquisar servidores', 'nl': 'Servers zoeken', 'tr': 'Sunucu ara'},
  'retry': {'de': 'Erneut versuchen', 'en': 'Retry', 'fr': 'Réessayer', 'es': 'Reintentar', 'pl': 'Spróbuj ponownie', 'it': 'Riprova', 'pt': 'Tentar novamente', 'nl': 'Opnieuw proberen', 'tr': 'Yeniden dene'},
  'noServersFound': {'de': 'Keine Server gefunden.', 'en': 'No servers found.', 'fr': 'Aucun serveur trouvé.', 'es': 'No se encontraron servidores.', 'pl': 'Nie znaleziono serwerów.', 'it': 'Nessun server trovato.', 'pt': 'Nenhum servidor encontrado.', 'nl': 'Geen servers gevonden.', 'tr': 'Sunucu bulunamadı.'},
  'noFavoritesYet': {'de': 'Noch keine Favoriten. Tippe auf den Stern in einem Serverprofil.', 'en': 'No favorites yet. Tap the star on a server profile.', 'fr': "Pas encore de favoris. Appuyez sur l'étoile dans le profil d'un serveur.", 'es': 'Aún no hay favoritos. Toca la estrella en el perfil de un servidor.', 'pl': 'Brak ulubionych. Stuknij gwiazdkę w profilu serwera.', 'it': 'Nessun preferito ancora. Tocca la stella sul profilo di un server.', 'pt': 'Ainda sem favoritos. Toque na estrela no perfil de um servidor.', 'nl': 'Nog geen favorieten. Tik op de ster bij een serverprofiel.', 'tr': 'Henüz favori yok. Bir sunucu profilindeki yıldıza dokun.'},
  'loading': {'de': 'Lade komplette Serverliste…\ndas kann bis zu 30 Sekunden dauern', 'en': 'Loading full server list…\nthis can take up to 30 seconds', 'fr': 'Chargement de la liste complète des serveurs…\ncela peut prendre jusqu\'à 30 secondes', 'es': 'Cargando la lista completa de servidores…\npuede tardar hasta 30 segundos', 'pl': 'Ładowanie pełnej listy serwerów…\nmoże to potrwać do 30 sekund', 'it': 'Caricamento della lista completa dei server…\\npuò richiedere fino a 30 secondi', 'pt': 'Carregando a lista completa de servidores…\\npode levar até 30 segundos', 'nl': 'Volledige serverlijst laden…\\ndit kan tot 30 seconden duren', 'tr': 'Tam sunucu listesi yükleniyor…\\nbu işlem 30 saniyeye kadar sürebilir'},
  'hideEmpty': {'de': 'Leere ausblenden', 'en': 'Hide empty', 'fr': 'Masquer les vides', 'es': 'Ocultar vacíos', 'pl': 'Ukryj puste', 'it': 'Nascondi vuoti', 'pt': 'Ocultar vazios', 'nl': 'Lege verbergen', 'tr': 'Boşları gizle'},
  'hideFull': {'de': 'Volle ausblenden', 'en': 'Hide full', 'fr': 'Masquer les pleins', 'es': 'Ocultar llenos', 'pl': 'Ukryj pełne', 'it': 'Nascondi pieni', 'pt': 'Ocultar cheios', 'nl': 'Volle verbergen', 'tr': 'Doluları gizle'},
  'country': {'de': 'Land', 'en': 'Country', 'fr': 'Pays', 'es': 'País', 'pl': 'Kraj', 'it': 'Paese', 'pt': 'País', 'nl': 'Land', 'tr': 'Ülke'},
  'tagsHint': {'de': 'Tags (1x einschließen, 2x ausschließen)', 'en': 'Tags (tap once to include, twice to exclude)', 'fr': 'Tags (appuyez une fois pour inclure, deux fois pour exclure)', 'es': 'Etiquetas (toca una vez para incluir, dos para excluir)', 'pl': 'Tagi (dotknij raz, aby uwzględnić, dwa razy, aby wykluczyć)', 'it': 'Tag (tocca una volta per includere, due per escludere)', 'pt': 'Tags (toque uma vez para incluir, duas para excluir)', 'nl': 'Tags (één keer tikken om op te nemen, twee keer om uit te sluiten)', 'tr': 'Etiketler (dahil etmek için bir, hariç tutmak için iki kez dokun)'},
  'join': {'de': 'Beitreten', 'en': 'Join', 'fr': 'Rejoindre', 'es': 'Unirse', 'pl': 'Dołącz', 'it': 'Entra', 'pt': 'Entrar', 'nl': 'Deelnemen', 'tr': 'Katıl'},
  'copied': {'de': 'Kopiert', 'en': 'Copied', 'fr': 'Copié', 'es': 'Copiado', 'pl': 'Skopiowano', 'it': 'Copiato', 'pt': 'Copiado', 'nl': 'Gekopieerd', 'tr': 'Kopyalandı'},
  'overview': {'de': 'Übersicht', 'en': 'Overview', 'fr': 'Aperçu', 'es': 'Resumen', 'pl': 'Przegląd', 'it': 'Panoramica', 'pt': 'Visão geral', 'nl': 'Overzicht', 'tr': 'Genel bakış'},
  'scripts': {'de': 'Scripts', 'en': 'Scripts', 'fr': 'Scripts', 'es': 'Scripts', 'pl': 'Skrypty', 'it': 'Script', 'pt': 'Scripts', 'nl': 'Scripts', 'tr': 'Betikler'},
  'filterScripts': {'de': 'Script filtern', 'en': 'Filter scripts', 'fr': 'Filtrer les scripts', 'es': 'Filtrar scripts', 'pl': 'Filtruj skrypty', 'it': 'Filtra script', 'pt': 'Filtrar scripts', 'nl': 'Scripts filteren', 'tr': 'Betikleri filtrele'},
  'noScriptsFound': {'de': 'Keine Scripts gefunden.', 'en': 'No scripts found.', 'fr': 'Aucun script trouvé.', 'es': 'No se encontraron scripts.', 'pl': 'Nie znaleziono skryptów.', 'it': 'Nessuno script trovato.', 'pt': 'Nenhum script encontrado.', 'nl': 'Geen scripts gevonden.', 'tr': 'Betik bulunamadı.'},
  'gametype': {'de': 'Gametype', 'en': 'Gametype', 'fr': 'Type de jeu', 'es': 'Tipo de juego', 'pl': 'Typ gry', 'it': 'Tipo di gioco', 'pt': 'Tipo de jogo', 'nl': 'Speltype', 'tr': 'Oyun türü'},
  'map': {'de': 'Map', 'en': 'Map', 'fr': 'Carte', 'es': 'Mapa', 'pl': 'Mapa', 'it': 'Mappa', 'pt': 'Mapa', 'nl': 'Kaart', 'tr': 'Harita'},
  'players': {'de': 'Spieler', 'en': 'Players', 'fr': 'Joueurs', 'es': 'Jugadores', 'pl': 'Gracze', 'it': 'Giocatori', 'pt': 'Jogadores', 'nl': 'Spelers', 'tr': 'Oyuncular'},
  'boost': {'de': 'Boost', 'en': 'Boost', 'fr': 'Boost', 'es': 'Boost', 'pl': 'Boost', 'it': 'Boost', 'pt': 'Impulso', 'nl': 'Boost', 'tr': 'Artırma'},
  'onesync': {'de': 'OneSync', 'en': 'OneSync', 'fr': 'OneSync', 'es': 'OneSync', 'pl': 'OneSync', 'it': 'OneSync', 'pt': 'OneSync', 'nl': 'OneSync', 'tr': 'OneSync'},
  'active': {'de': 'Aktiv', 'en': 'Active', 'fr': 'Actif', 'es': 'Activo', 'pl': 'Aktywny', 'it': 'Attivo', 'pt': 'Ativo', 'nl': 'Actief', 'tr': 'Aktif'},
  'inactive': {'de': 'Inaktiv', 'en': 'Inactive', 'fr': 'Inactif', 'es': 'Inactivo', 'pl': 'Nieaktywny', 'it': 'Inattivo', 'pt': 'Inativo', 'nl': 'Inactief', 'tr': 'Pasif'},
  'build': {'de': 'Build', 'en': 'Build', 'fr': 'Build', 'es': 'Build', 'pl': 'Build', 'it': 'Build', 'pt': 'Build', 'nl': 'Build', 'tr': 'Sürüm'},
  'language': {'de': 'Sprache', 'en': 'Language', 'fr': 'Langue', 'es': 'Idioma', 'pl': 'Język', 'it': 'Lingua', 'pt': 'Idioma', 'nl': 'Taal', 'tr': 'Dil'},
  'tags': {'de': 'Tags', 'en': 'Tags', 'fr': 'Tags', 'es': 'Etiquetas', 'pl': 'Tagi', 'it': 'Tag', 'pt': 'Tags', 'nl': 'Tags', 'tr': 'Etiketler'},
  'onboardingWelcome': {'de': 'Willkommen', 'en': 'Welcome', 'fr': 'Bienvenue', 'es': 'Bienvenido', 'pl': 'Witamy', 'it': 'Benvenuto', 'pt': 'Bem-vindo', 'nl': 'Welkom', 'tr': 'Hoş geldin'},
  'onboardingLanguage': {'de': 'Wähle deine Sprache', 'en': 'Choose your language', 'fr': 'Choisissez votre langue', 'es': 'Elige tu idioma', 'pl': 'Wybierz swój język', 'it': 'Scegli la tua lingua', 'pt': 'Escolha seu idioma', 'nl': 'Kies je taal', 'tr': 'Dilini seç'},
  'onboardingTheme': {'de': 'Wähle dein Farbschema', 'en': 'Choose your color scheme', 'fr': 'Choisissez votre thème de couleur', 'es': 'Elige tu esquema de color', 'pl': 'Wybierz swój schemat kolorów', 'it': 'Scegli il tuo tema colore', 'pt': 'Escolha seu esquema de cores', 'nl': 'Kies je kleurenschema', 'tr': 'Renk düzenini seç'},
  'continueLabel': {'de': 'Weiter', 'en': 'Continue', 'fr': 'Continuer', 'es': 'Continuar', 'pl': 'Dalej', 'it': 'Continua', 'pt': 'Continuar', 'nl': 'Doorgaan', 'tr': 'Devam et'},
  'getStarted': {'de': 'Los geht\'s', 'en': 'Get started', 'fr': 'Commencer', 'es': 'Comenzar', 'pl': 'Zaczynajmy', 'it': 'Inizia', 'pt': 'Começar', 'nl': 'Aan de slag', 'tr': 'Başla'},
  'appLanguage': {'de': 'App-Sprache', 'en': 'App language', 'fr': "Langue de l'app", 'es': 'Idioma de la app', 'pl': 'Język aplikacji', 'it': "Lingua dell'app", 'pt': 'Idioma do aplicativo', 'nl': 'Apptaal', 'tr': 'Uygulama dili'},
  'colorScheme': {'de': 'Farbschema', 'en': 'Color scheme', 'fr': 'Thème de couleur', 'es': 'Esquema de color', 'pl': 'Schemat kolorów', 'it': 'Tema colore', 'pt': 'Esquema de cores', 'nl': 'Kleurenschema', 'tr': 'Renk düzeni'},
  'notifications': {'de': 'Benachrichtigungen', 'en': 'Notifications', 'fr': 'Notifications', 'es': 'Notificaciones', 'pl': 'Powiadomienia', 'it': 'Notifiche', 'pt': 'Notificações', 'nl': 'Meldingen', 'tr': 'Bildirimler'},
  'notificationsDesc': {'de': 'Benachrichtigung senden, wenn ein favorisierter Server genug Spieler hat', 'en': 'Notify me when a favorite server has enough players', 'fr': "M'avertir quand un serveur favori a assez de joueurs", 'es': 'Avisarme cuando un servidor favorito tenga suficientes jugadores', 'pl': 'Powiadom mnie, gdy ulubiony serwer ma wystarczająco graczy', 'it': 'Avvisami quando un server preferito ha abbastanza giocatori', 'pt': 'Avise-me quando um servidor favorito tiver jogadores suficientes', 'nl': 'Waarschuw me als een favoriete server genoeg spelers heeft', 'tr': 'Favori bir sunucuda yeterince oyuncu olduğunda bana bildir'},
  'notificationThreshold': {'de': 'Ab wie vielen Spielern benachrichtigen', 'en': 'Notify from this many players', 'fr': 'Notifier à partir de ce nombre de joueurs', 'es': 'Notificar a partir de esta cantidad de jugadores', 'pl': 'Powiadamiaj od tylu graczy', 'it': 'Avvisa a partire da questo numero di giocatori', 'pt': 'Notificar a partir desta quantidade de jogadores', 'nl': 'Waarschuw vanaf dit aantal spelers', 'tr': 'Bu kadar oyuncudan itibaren bildir'},
  'favoriteThreshold': {'de': 'Schwelle für diesen Server', 'en': 'Threshold for this server', 'fr': 'Seuil pour ce serveur', 'es': 'Umbral para este servidor', 'pl': 'Próg dla tego serwera', 'it': 'Soglia per questo server', 'pt': 'Limite para este servidor', 'nl': 'Drempel voor deze server', 'tr': 'Bu sunucu için eşik'},
  'favoriteNotifyEnable': {'de': 'Benachrichtigungen für diesen Server', 'en': 'Notifications for this server', 'fr': 'Notifications pour ce serveur', 'es': 'Notificaciones para este servidor', 'pl': 'Powiadomienia dla tego serwera', 'it': 'Notifiche per questo server', 'pt': 'Notificações para este servidor', 'nl': 'Meldingen voor deze server', 'tr': 'Bu sunucu için bildirimler'},
  'favoriteNotifyThresholdLabel': {'de': 'Ab so vielen Spielern', 'en': 'From this many players', 'fr': 'À partir de ce nombre de joueurs', 'es': 'A partir de esta cantidad de jugadores', 'pl': 'Od tylu graczy', 'it': 'A partire da questo numero di giocatori', 'pt': 'A partir desta quantidade de jogadores', 'nl': 'Vanaf dit aantal spelers', 'tr': 'Bu kadar oyuncudan itibaren'},
  'clearCache': {'de': 'App-Cache leeren', 'en': 'Clear app cache', 'fr': "Vider le cache de l'app", 'es': 'Borrar caché de la app', 'pl': 'Wyczyść pamięć podręczną aplikacji', 'it': "Svuota la cache dell'app", 'pt': 'Limpar cache do aplicativo', 'nl': 'App-cache wissen', 'tr': 'Uygulama önbelleğini temizle'},
  'cacheCleared': {'de': 'Cache geleert', 'en': 'Cache cleared', 'fr': 'Cache vidé', 'es': 'Caché borrada', 'pl': 'Pamięć podręczna wyczyszczona', 'it': 'Cache svuotata', 'pt': 'Cache limpo', 'nl': 'Cache gewist', 'tr': 'Önbellek temizlendi'},
  'useDefaultThreshold': {'de': 'Standard verwenden', 'en': 'Use default', 'fr': 'Utiliser la valeur par défaut', 'es': 'Usar valor predeterminado', 'pl': 'Użyj domyślnej', 'it': 'Usa predefinito', 'pt': 'Usar padrão', 'nl': 'Standaard gebruiken', 'tr': 'Varsayılanı kullan'},
  'notificationSound': {'de': 'Benachrichtigungston', 'en': 'Notification sound', 'fr': 'Son de notification', 'es': 'Sonido de notificación', 'pl': 'Dźwięk powiadomienia', 'it': 'Suono di notifica', 'pt': 'Som de notificação', 'nl': 'Meldingsgeluid', 'tr': 'Bildirim sesi'},
  'soundDefault': {'de': 'Standard', 'en': 'Default', 'fr': 'Par défaut', 'es': 'Predeterminado', 'pl': 'Domyślny', 'it': 'Predefinito', 'pt': 'Padrão', 'nl': 'Standaard', 'tr': 'Varsayılan'},
  'soundChime': {'de': 'Glockenspiel', 'en': 'Chime', 'fr': 'Carillon', 'es': 'Campanilla', 'pl': 'Dzwonek', 'it': 'Carillon', 'pt': 'Sininho', 'nl': 'Belletje', 'tr': 'Çan sesi'},
  'soundBell': {'de': 'Glocke', 'en': 'Bell', 'fr': 'Cloche', 'es': 'Campana', 'pl': 'Dzwon', 'it': 'Campana', 'pt': 'Sino', 'nl': 'Bel', 'tr': 'Zil'},
  'tutorialServerListTitle': {'de': 'Serverliste', 'en': 'Server list', 'fr': 'Liste des serveurs', 'es': 'Lista de servidores', 'pl': 'Lista serwerów', 'it': 'Lista server', 'pt': 'Lista de servidores', 'nl': 'Serverlijst', 'tr': 'Sunucu listesi'},
  'tutorialServerListDesc': {'de': 'Hier findest du alle FiveM-Server, kannst filtern, sortieren und suchen.', 'en': 'Browse every FiveM server here, with filtering, sorting and search.', 'fr': 'Parcourez ici tous les serveurs FiveM, avec filtres, tri et recherche.', 'es': 'Explora aquí todos los servidores FiveM, con filtros, orden y búsqueda.', 'pl': 'Tutaj znajdziesz wszystkie serwery FiveM z filtrowaniem, sortowaniem i wyszukiwaniem.', 'it': 'Sfoglia qui tutti i server FiveM, con filtri, ordinamento e ricerca.', 'pt': 'Explore aqui todos os servidores FiveM, com filtros, ordenação e busca.', 'nl': 'Blader hier door alle FiveM-servers, met filters, sorteren en zoeken.', 'tr': 'Tüm FiveM sunucularına burada göz at; filtreleme, sıralama ve arama ile.'},
  'tutorialFavoritesTitle': {'de': 'Favoriten', 'en': 'Favorites', 'fr': 'Favoris', 'es': 'Favoritos', 'pl': 'Ulubione', 'it': 'Preferiti', 'pt': 'Favoritos', 'nl': 'Favorieten', 'tr': 'Favoriler'},
  'tutorialFavoritesDesc': {'de': 'Markiere Server als Favorit, um Benachrichtigungen zu erhalten, wenn sie online gehen oder genug Spieler haben.', 'en': 'Star a server as favorite to get notified when it comes online or reaches enough players.', 'fr': 'Marquez un serveur comme favori pour être averti quand il est en ligne ou atteint assez de joueurs.', 'es': 'Marca un servidor como favorito para recibir avisos cuando esté en línea o tenga suficientes jugadores.', 'pl': 'Oznacz serwer jako ulubiony, aby otrzymać powiadomienie, gdy będzie online lub ma wystarczająco graczy.', 'it': 'Aggiungi un server ai preferiti per essere avvisato quando torna online o raggiunge abbastanza giocatori.', 'pt': 'Marque um servidor como favorito para ser avisado quando ele ficar online ou tiver jogadores suficientes.', 'nl': 'Markeer een server als favoriet om een melding te krijgen als deze online komt of genoeg spelers heeft.', 'tr': 'Çevrimiçi olduğunda veya yeterince oyuncuya ulaştığında bildirim almak için bir sunucuyu favori olarak işaretle.'},
  'tutorialSettingsTitle': {'de': 'Einstellungen', 'en': 'Settings', 'fr': 'Paramètres', 'es': 'Ajustes', 'pl': 'Ustawienia', 'it': 'Impostazioni', 'pt': 'Configurações', 'nl': 'Instellingen', 'tr': 'Ayarlar'},
  'tutorialSettingsDesc': {'de': 'Sprache, Design, Textgröße, Sounds und Benachrichtigungen kannst du hier anpassen.', 'en': 'Adjust language, theme, text size, sounds and notifications here.', 'fr': "Ajustez ici la langue, le thème, la taille du texte, les sons et les notifications.", 'es': 'Ajusta aquí el idioma, el tema, el tamaño del texto, los sonidos y las notificaciones.', 'pl': 'Dostosuj tutaj język, motyw, rozmiar tekstu, dźwięki i powiadomienia.', 'it': 'Qui puoi regolare lingua, tema, dimensione del testo, suoni e notifiche.', 'pt': 'Ajuste aqui idioma, tema, tamanho do texto, sons e notificações.', 'nl': 'Pas hier taal, thema, tekstgrootte, geluiden en meldingen aan.', 'tr': 'Dil, tema, yazı boyutu, sesler ve bildirimleri buradan ayarla.'},
  'tutorialNext': {'de': 'Weiter', 'en': 'Next', 'fr': 'Suivant', 'es': 'Siguiente', 'pl': 'Dalej', 'it': 'Avanti', 'pt': 'Próximo', 'nl': 'Volgende', 'tr': 'İleri'},
  'tutorialDone': {'de': 'Fertig', 'en': 'Done', 'fr': 'Terminé', 'es': 'Listo', 'pl': 'Gotowe', 'it': 'Fatto', 'pt': 'Concluído', 'nl': 'Klaar', 'tr': 'Bitti'},
  'tutorialSkip': {'de': 'Überspringen', 'en': 'Skip', 'fr': 'Passer', 'es': 'Omitir', 'pl': 'Pomiń', 'it': 'Salta', 'pt': 'Pular', 'nl': 'Overslaan', 'tr': 'Atla'},
  'autoRefresh': {'de': 'Auto-Aktualisierung', 'en': 'Auto-refresh', 'fr': 'Actualisation automatique', 'es': 'Actualización automática', 'pl': 'Automatyczne odświeżanie', 'it': 'Aggiornamento automatico', 'pt': 'Atualização automática', 'nl': 'Automatisch vernieuwen', 'tr': 'Otomatik yenileme'},
  'autoRefreshDesc': {'de': 'Wie oft sich die Serverliste im Hintergrund selbst aktualisiert', 'en': 'How often the server list refreshes itself automatically', 'fr': 'À quelle fréquence la liste des serveurs se rafraîchit automatiquement', 'es': 'Con qué frecuencia se actualiza automáticamente la lista de servidores', 'pl': 'Jak często lista serwerów odświeża się automatycznie', 'it': 'Ogni quanto la lista dei server si aggiorna automaticamente', 'pt': 'Com que frequência a lista de servidores se atualiza automaticamente', 'nl': 'Hoe vaak de serverlijst zichzelf automatisch vernieuwt', 'tr': 'Sunucu listesinin kendini otomatik olarak ne sıklıkla yenileyeceği'},
  'uiSounds': {'de': 'Sound', 'en': 'Sound', 'fr': 'Son', 'es': 'Sonido', 'pl': 'Dźwięk', 'it': 'Suono', 'pt': 'Som', 'nl': 'Geluid', 'tr': 'Ses'},
  'uiSoundsDesc': {'de': 'Sound-Effekte bei Berührungen und beim App-Start abspielen', 'en': 'Play sound effects on taps and at app startup', 'fr': 'Jouer des effets sonores lors des interactions et au démarrage', 'es': 'Reproducir efectos de sonido al tocar y al iniciar la app', 'pl': 'Odtwarzaj dźwięki przy dotknięciach i przy starcie aplikacji', 'it': "Riproduci effetti sonori ai tocchi e all'avvio dell'app", 'pt': 'Reproduzir efeitos sonoros ao tocar e ao iniciar o aplicativo', 'nl': 'Speel geluidseffecten af bij tikken en bij het opstarten van de app', 'tr': 'Dokunuşlarda ve uygulama açılışında ses efektleri çal'},
  'haptics': {'de': 'Vibration bei Berührung', 'en': 'Haptic feedback', 'fr': 'Retour haptique', 'es': 'Retroalimentación háptica', 'pl': 'Wibracje dotykowe', 'it': 'Feedback tattile', 'pt': 'Feedback tátil', 'nl': 'Haptische feedback', 'tr': 'Dokunsal geri bildirim'},
  'hapticsDesc': {'de': 'Kurz vibrieren bei Berührungen in der App', 'en': 'Brief vibration on taps within the app', 'fr': 'Légère vibration lors des interactions dans l\'app', 'es': 'Vibración breve al tocar dentro de la app', 'pl': 'Krótka wibracja przy dotknięciach w aplikacji', 'it': "Breve vibrazione ai tocchi nell'app", 'pt': 'Vibração breve ao tocar dentro do aplicativo', 'nl': 'Korte trilling bij tikken in de app', 'tr': 'Uygulama içindeki dokunuşlarda kısa titreşim'},
  'textSize': {'de': 'Schriftgröße', 'en': 'Text size', 'fr': 'Taille du texte', 'es': 'Tamaño del texto', 'pl': 'Rozmiar tekstu', 'it': 'Dimensione testo', 'pt': 'Tamanho do texto', 'nl': 'Tekstgrootte', 'tr': 'Yazı boyutu'},
  'textSizeSmall': {'de': 'Klein', 'en': 'Small', 'fr': 'Petit', 'es': 'Pequeño', 'pl': 'Mały', 'it': 'Piccolo', 'pt': 'Pequeno', 'nl': 'Klein', 'tr': 'Küçük'},
  'textSizeNormal': {'de': 'Normal', 'en': 'Normal', 'fr': 'Normal', 'es': 'Normal', 'pl': 'Normalny', 'it': 'Normale', 'pt': 'Normal', 'nl': 'Normaal', 'tr': 'Normal'},
  'textSizeLarge': {'de': 'Groß', 'en': 'Large', 'fr': 'Grand', 'es': 'Grande', 'pl': 'Duży', 'it': 'Grande', 'pt': 'Grande', 'nl': 'Groot', 'tr': 'Büyük'},
  'highContrast': {'de': 'Hoher Kontrast', 'en': 'High contrast', 'fr': 'Contraste élevé', 'es': 'Alto contraste', 'pl': 'Wysoki kontrast', 'it': 'Alto contrasto', 'pt': 'Alto contraste', 'nl': 'Hoog contrast', 'tr': 'Yüksek kontrast'},
  'highContrastDesc': {'de': 'Kräftigere Farben und besserer Textkontrast für schwächeres Sehen', 'en': 'Bolder colors and stronger text contrast for low vision', 'fr': 'Couleurs plus marquées et meilleur contraste de texte', 'es': 'Colores más fuertes y mejor contraste de texto', 'pl': 'Mocniejsze kolory i lepszy kontrast tekstu', 'it': 'Colori più marcati e maggiore contrasto del testo per la bassa visione', 'pt': 'Cores mais fortes e maior contraste de texto para baixa visão', 'nl': 'Krachtigere kleuren en sterker tekstcontrast voor slechtzienden', 'tr': 'Az görme için daha belirgin renkler ve daha güçlü metin kontrastı'},
  'favoriteOfflineTitle': {'de': 'Server offline', 'en': 'Server offline', 'fr': 'Serveur hors ligne', 'es': 'Servidor fuera de línea', 'pl': 'Serwer offline', 'it': 'Server offline', 'pt': 'Servidor offline', 'nl': 'Server offline', 'tr': 'Sunucu çevrimdışı'},
  'favoriteOfflineBody': {'de': '{name} ist nicht mehr erreichbar', 'en': '{name} is no longer reachable', 'fr': '{name} n\'est plus accessible', 'es': '{name} ya no está disponible', 'pl': '{name} jest niedostępny', 'it': '{name} non è più raggiungibile', 'pt': '{name} não está mais acessível', 'nl': '{name} is niet meer bereikbaar', 'tr': '{name} artık ulaşılamıyor'},
  'favoriteOnlineTitle': {'de': 'Server wieder online', 'en': 'Server back online', 'fr': 'Serveur de nouveau en ligne', 'es': 'Servidor de nuevo en línea', 'pl': 'Serwer znowu online', 'it': 'Server di nuovo online', 'pt': 'Servidor online novamente', 'nl': 'Server weer online', 'tr': 'Sunucu tekrar çevrimiçi'},
  'favoriteOnlineBody': {'de': '{name} ist wieder erreichbar', 'en': '{name} is reachable again', 'fr': '{name} est de nouveau accessible', 'es': '{name} está disponible de nuevo', 'pl': '{name} jest znowu dostępny', 'it': '{name} è di nuovo raggiungibile', 'pt': '{name} está acessível novamente', 'nl': '{name} is weer bereikbaar', 'tr': '{name} tekrar ulaşılabilir durumda'},
  'favoriteThresholdBody': {'de': 'hat gerade {clients} Spieler', 'en': 'has {clients} players right now', 'fr': 'a {clients} joueurs en ce moment', 'es': 'tiene {clients} jugadores ahora', 'pl': 'ma teraz {clients} graczy', 'it': 'ha {clients} giocatori in questo momento', 'pt': 'tem {clients} jogadores agora', 'nl': 'heeft nu {clients} spelers', 'tr': 'şu anda {clients} oyuncuya sahip'},
  'newBadge': {'de': 'NEU', 'en': 'NEW', 'fr': 'NOUVEAU', 'es': 'NUEVO', 'pl': 'NOWY', 'it': 'NUOVO', 'pt': 'NOVO', 'nl': 'NIEUW', 'tr': 'YENİ'},
  'back': {'de': 'Zurück', 'en': 'Back', 'fr': 'Retour', 'es': 'Atrás', 'pl': 'Wstecz', 'it': 'Indietro', 'pt': 'Voltar', 'nl': 'Terug', 'tr': 'Geri'},
  'unreachable': {'de': 'Live-Details nicht erreichbar', 'en': 'Live details unreachable', 'fr': 'Détails en direct indisponibles', 'es': 'Detalles en vivo no disponibles', 'pl': 'Brak dostępu do szczegółów na żywo', 'it': 'Dettagli live non disponibili', 'pt': 'Detalhes em tempo real indisponíveis', 'nl': 'Live-details niet beschikbaar', 'tr': 'Canlı bilgilere ulaşılamıyor'},
  'topServersNearYou': {'de': 'Top 3 in deiner Region', 'en': 'Top 3 in your region', 'fr': 'Top 3 dans ta région', 'es': 'Top 3 en tu región', 'pl': 'Top 3 w Twoim regionie', 'it': 'Top 3 nella tua regione', 'pt': 'Top 3 na sua região', 'nl': 'Top 3 in jouw regio', 'tr': 'Bölgende ilk 3'},
  'searchHistoryTitle': {'de': 'Suchverlauf', 'en': 'Search history', 'fr': 'Historique de recherche', 'es': 'Historial de búsqueda', 'pl': 'Historia wyszukiwania', 'it': 'Cronologia ricerche', 'pt': 'Histórico de pesquisa', 'nl': 'Zoekgeschiedenis', 'tr': 'Arama geçmişi'},
  'searchHistorySubtitle': {'de': 'Deine letzten Suchanfragen', 'en': 'Your recent searches', 'fr': 'Vos recherches récentes', 'es': 'Tus búsquedas recientes', 'pl': 'Twoje ostatnie wyszukiwania', 'it': 'Le tue ricerche recenti', 'pt': 'Suas pesquisas recentes', 'nl': 'Je recente zoekopdrachten', 'tr': 'Son aramaların'},
  'noSearchHistory': {'de': 'Noch keine Suchanfragen.', 'en': 'No searches yet.', 'fr': 'Aucune recherche pour le moment.', 'es': 'Aún no hay búsquedas.', 'pl': 'Brak wyszukiwań.', 'it': 'Nessuna ricerca ancora.', 'pt': 'Ainda sem pesquisas.', 'nl': 'Nog geen zoekopdrachten.', 'tr': 'Henüz arama yok.'},
  'clearHistory': {'de': 'Verlauf leeren', 'en': 'Clear history', 'fr': "Effacer l'historique", 'es': 'Borrar historial', 'pl': 'Wyczyść historię', 'it': 'Svuota cronologia', 'pt': 'Limpar histórico', 'nl': 'Geschiedenis wissen', 'tr': 'Geçmişi temizle'},
  'topRegionTitle': {'de': 'Top 10 in deiner Region', 'en': 'Top 10 in your region', 'fr': 'Top 10 dans ta région', 'es': 'Top 10 en tu región', 'pl': 'Top 10 w Twoim regionie', 'it': 'Top 10 nella tua regione', 'pt': 'Top 10 na sua região', 'nl': 'Top 10 in jouw regio', 'tr': 'Bölgende ilk 10'},
  'topRegionSubtitle': {'de': 'Beste Server nach Boost', 'en': 'Best servers by boost', 'fr': 'Meilleurs serveurs par boost', 'es': 'Mejores servidores por impulso', 'pl': 'Najlepsze serwery według boostu', 'it': 'Migliori server per boost', 'pt': 'Melhores servidores por impulso', 'nl': 'Beste servers op boost', 'tr': 'Artırmaya göre en iyi sunucular'},
  'tutorialSearchHistoryDesc': {'de': 'Hier siehst du deine letzten 50 Suchanfragen und kannst sie mit der Mülltonne löschen.', 'en': 'See your last 50 searches here and clear them with the trash icon.', 'fr': "Retrouvez ici vos 50 dernières recherches et effacez-les avec l'icône de corbeille.", 'es': 'Aquí ves tus últimas 50 búsquedas y puedes borrarlas con el icono de papelera.', 'pl': 'Tutaj zobaczysz swoje ostatnie 50 wyszukiwań i możesz je wyczyścić ikoną kosza.', 'it': 'Qui trovi le tue ultime 50 ricerche e puoi eliminarle con l\'icona del cestino.', 'pt': 'Aqui você vê suas últimas 50 pesquisas e pode limpá-las com o ícone de lixeira.', 'nl': 'Hier zie je je laatste 50 zoekopdrachten en kun je ze wissen met het prullenbakicoon.', 'tr': 'Son 50 aramanı burada görebilir ve çöp kutusu simgesiyle temizleyebilirsin.'},
  'tutorialTopRegionDesc': {'de': 'Die 10 beliebtesten Server in deiner Region, sortiert nach Boost.', 'en': 'The 10 most popular servers in your region, sorted by boost.', 'fr': 'Les 10 serveurs les plus populaires de ta région, triés par boost.', 'es': 'Los 10 servidores más populares de tu región, ordenados por impulso.', 'pl': '10 najpopularniejszych serwerów w Twoim regionie, sortowane według boostu.', 'it': 'I 10 server più popolari della tua regione, ordinati per boost.', 'pt': 'Os 10 servidores mais populares da sua região, ordenados por impulso.', 'nl': 'De 10 populairste servers in jouw regio, gesorteerd op boost.', 'tr': 'Bölgendeki en popüler 10 sunucu, artırmaya göre sıralanmış.'},
  'themeLight': {'de': 'Hell', 'en': 'Light', 'fr': 'Clair', 'es': 'Claro', 'pl': 'Jasny', 'it': 'Chiaro', 'pt': 'Claro', 'nl': 'Licht', 'tr': 'Açık'},
  'themeDark': {'de': 'Dunkel', 'en': 'Dark', 'fr': 'Sombre', 'es': 'Oscuro', 'pl': 'Ciemny', 'it': 'Scuro', 'pt': 'Escuro', 'nl': 'Donker', 'tr': 'Koyu'},
  'themeAuto': {'de': 'Automatisch', 'en': 'Automatic', 'fr': 'Automatique', 'es': 'Automático', 'pl': 'Automatyczny', 'it': 'Automatico', 'pt': 'Automático', 'nl': 'Automatisch', 'tr': 'Otomatik'},
  'sortBy': {'de': 'Sortierung', 'en': 'Sort by', 'fr': 'Trier par', 'es': 'Ordenar por', 'pl': 'Sortowanie', 'it': 'Ordina per', 'pt': 'Ordenar por', 'nl': 'Sorteren op', 'tr': 'Sıralama'},
  'sortDefault': {'de': 'Standard', 'en': 'Default', 'fr': 'Par défaut', 'es': 'Predeterminado', 'pl': 'Domyślne', 'it': 'Predefinito', 'pt': 'Padrão', 'nl': 'Standaard', 'tr': 'Varsayılan'},
  'sortMostPlayers': {'de': 'Meiste Spieler', 'en': 'Most players', 'fr': 'Plus de joueurs', 'es': 'Más jugadores', 'pl': 'Najwięcej graczy', 'it': 'Più giocatori', 'pt': 'Mais jogadores', 'nl': 'Meeste spelers', 'tr': 'En çok oyuncu'},
  'sortMostBoost': {'de': 'Höchster Boost', 'en': 'Highest boost', 'fr': 'Boost le plus élevé', 'es': 'Más boost', 'pl': 'Najwyższy boost', 'it': 'Boost più alto', 'pt': 'Maior impulso', 'nl': 'Hoogste boost', 'tr': 'En yüksek artırma'},
  'playerRange': {'de': 'Spieleranzahl', 'en': 'Player count', 'fr': 'Nombre de joueurs', 'es': 'Número de jugadores', 'pl': 'Liczba graczy', 'it': 'Numero di giocatori', 'pt': 'Número de jogadores', 'nl': 'Aantal spelers', 'tr': 'Oyuncu sayısı'},
  'share': {'de': 'Teilen', 'en': 'Share', 'fr': 'Partager', 'es': 'Compartir', 'pl': 'Udostępnij', 'it': 'Condividi', 'pt': 'Compartilhar', 'nl': 'Delen', 'tr': 'Paylaş'},
  'vibration': {'de': 'Vibration', 'en': 'Vibration', 'fr': 'Vibration', 'es': 'Vibración', 'pl': 'Wibracje', 'it': 'Vibrazione', 'pt': 'Vibração', 'nl': 'Trilling', 'tr': 'Titreşim'},
  'vibrationDesc': {'de': 'Bei Benachrichtigung vibrieren', 'en': 'Vibrate on notification', 'fr': 'Vibrer lors d\'une notification', 'es': 'Vibrar con la notificación', 'pl': 'Wibruj przy powiadomieniu', 'it': 'Vibra alla notifica', 'pt': 'Vibrar na notificação', 'nl': 'Trillen bij melding', 'tr': 'Bildirimde titret'},
  'about': {'de': 'Über die App', 'en': 'About', 'fr': 'À propos', 'es': 'Acerca de', 'pl': 'O aplikacji', 'it': 'Informazioni', 'pt': 'Sobre', 'nl': 'Over', 'tr': 'Hakkında'},
  'aboutVersion': {'de': 'Version', 'en': 'Version', 'fr': 'Version', 'es': 'Versión', 'pl': 'Wersja', 'it': 'Versione', 'pt': 'Versão', 'nl': 'Versie', 'tr': 'Sürüm'},
  'aboutCredits': {'de': 'Entwickelt für die FiveM-Community.', 'en': 'Built for the FiveM community.', 'fr': 'Conçu pour la communauté FiveM.', 'es': 'Creado para la comunidad de FiveM.', 'pl': 'Stworzone dla społeczności FiveM.', 'it': 'Creato per la community di FiveM.', 'pt': 'Criado para a comunidade FiveM.', 'nl': 'Gemaakt voor de FiveM-community.', 'tr': 'FiveM topluluğu için geliştirildi.'},
  'aboutContact': {'de': 'Fehler gefunden? Melde dich gerne beim Entwickler.', 'en': 'Found a bug? Feel free to reach out to the developer.', 'fr': "Un bug ? N'hésitez pas à contacter le développeur.", 'es': '¿Encontraste un error? No dudes en contactar al desarrollador.', 'pl': 'Znalazłeś błąd? Skontaktuj się z deweloperem.', 'it': 'Hai trovato un bug? Contatta pure lo sviluppatore.', 'pt': 'Encontrou um bug? Sinta-se à vontade para contatar o desenvolvedor.', 'nl': 'Bug gevonden? Neem gerust contact op met de ontwikkelaar.', 'tr': 'Bir hata mı buldun? Geliştiriciyle iletişime geçmekten çekinme.'},
};

const Map<String, String> kLanguageNames = {
  'de': 'Deutsch',
  'en': 'English',
  'fr': 'Français',
  'es': 'Español',
  'pl': 'Polski',
  'it': 'Italiano',
  'pt': 'Português',
  'nl': 'Nederlands',
  'tr': 'Türkçe',
};

const Map<String, String> kLanguageFlags = {
  'de': '🇩🇪',
  'en': '🇬🇧',
  'fr': '🇫🇷',
  'es': '🇪🇸',
  'pl': '🇵🇱',
  'it': '🇮🇹',
  'pt': '🇵🇹',
  'nl': '🇳🇱',
  'tr': '🇹🇷',
};

String tr(String key) {
  final lang = AppState.I.language;
  return _strings[key]?[lang] ?? _strings[key]?['en'] ?? _strings[key]?['de'] ?? key;
}

// ---------------------------------------------------------------------------
// App state & persistence
// ---------------------------------------------------------------------------

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  String language = 'de';
  String themeMode = 'dark';
  bool notificationVibration = true;
  // Presence of a code in this map means notifications are enabled for
  // that favorite; the value is its player-count threshold (1-2000).
  Map<String, int> favoriteThresholds = {};
  String notificationSound = 'default';
  int refreshIntervalMinutes = 5;
  bool uiSoundsEnabled = true;
  bool hapticsEnabled = true;
  double textScale = 1.0;
  bool highContrast = false;
  Set<String> favorites = {};
  List<String> searchHistory = [];
  bool onboardingDone = false;
  bool tutorialSeen = false;

  bool get isDark {
    if (themeMode == 'auto') {
      return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
    return themeMode == 'dark';
  }

  // Only used to pick a sensible default before the user has explicitly
  // chosen a language (i.e. on first launch, before onboarding).
  static String _detectDeviceLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return kLanguageNames.containsKey(code) ? code : 'de';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('language') ?? _detectDeviceLanguage();
    themeMode = _migrateThemeMode(prefs.getString('themeMode') ?? prefs.getString('themeKey') ?? 'dark');
    notificationVibration = prefs.getBool('notificationVibration') ?? true;
    favoriteThresholds = {
      for (final entry in prefs.getStringList('favoriteThresholds') ?? const [])
        if (entry.contains(':')) entry.split(':').first: int.tryParse(entry.split(':').last) ?? 10,
    };
    notificationSound = prefs.getString('notificationSound') ?? 'default';
    refreshIntervalMinutes = prefs.getInt('refreshIntervalMinutes') ?? 5;
    uiSoundsEnabled = prefs.getBool('uiSoundsEnabled') ?? true;
    hapticsEnabled = prefs.getBool('hapticsEnabled') ?? true;
    textScale = prefs.getDouble('textScale') ?? 1.0;
    highContrast = prefs.getBool('highContrast') ?? false;
    favorites = (prefs.getStringList('favorites') ?? const []).toSet();
    searchHistory = prefs.getStringList('searchHistory') ?? [];
    onboardingDone = prefs.getBool('onboardingDone') ?? false;
    tutorialSeen = prefs.getBool('tutorialSeen') ?? false;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
    await prefs.setString('themeMode', themeMode);
    await prefs.setBool('notificationVibration', notificationVibration);
    await prefs.setStringList('favoriteThresholds', [for (final e in favoriteThresholds.entries) '${e.key}:${e.value}']);
    await prefs.setString('notificationSound', notificationSound);
    await prefs.setInt('refreshIntervalMinutes', refreshIntervalMinutes);
    await prefs.setBool('uiSoundsEnabled', uiSoundsEnabled);
    await prefs.setBool('hapticsEnabled', hapticsEnabled);
    await prefs.setDouble('textScale', textScale);
    await prefs.setBool('highContrast', highContrast);
    await prefs.setStringList('favorites', favorites.toList());
    await prefs.setStringList('searchHistory', searchHistory);
    await prefs.setBool('onboardingDone', onboardingDone);
    await prefs.setBool('tutorialSeen', tutorialSeen);
  }

  Future<void> addSearchTerm(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    searchHistory.removeWhere((t) => t.toLowerCase() == trimmed.toLowerCase());
    searchHistory.insert(0, trimmed);
    if (searchHistory.length > 50) searchHistory = searchHistory.sublist(0, 50);
    notifyListeners();
    await _persist();
  }

  Future<void> clearSearchHistory() async {
    searchHistory = [];
    notifyListeners();
    await _persist();
  }

  Future<void> setLanguage(String lang) async {
    language = lang;
    notifyListeners();
    await _persist();
  }

  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setNotificationSound(String value) async {
    notificationSound = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setRefreshIntervalMinutes(int value) async {
    refreshIntervalMinutes = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setUiSoundsEnabled(bool value) async {
    uiSoundsEnabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setHapticsEnabled(bool value) async {
    hapticsEnabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTextScale(double value) async {
    textScale = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setHighContrast(bool value) async {
    highContrast = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setNotificationVibration(bool value) async {
    notificationVibration = value;
    notifyListeners();
    await _persist();
  }

  Future<void> completeOnboarding() async {
    onboardingDone = true;
    notifyListeners();
    await _persist();
  }

  Future<void> completeTutorial() async {
    tutorialSeen = true;
    notifyListeners();
    await _persist();
  }

  bool isFavorite(String code) => favorites.contains(code);

  bool isFavoriteNotifyEnabled(String code) => favoriteThresholds.containsKey(code);

  int favoriteNotifyThreshold(String code) => favoriteThresholds[code] ?? 10;

  Future<void> setFavoriteNotifyEnabled(String code, bool enabled) async {
    if (enabled) {
      favoriteThresholds[code] = favoriteThresholds[code] ?? 10;
    } else {
      favoriteThresholds.remove(code);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setFavoriteNotifyThreshold(String code, int value) async {
    if (!favoriteThresholds.containsKey(code)) return;
    favoriteThresholds[code] = value;
    notifyListeners();
    await _persist();
  }

  Future<void> toggleFavorite(String code) async {
    if (!favorites.add(code)) {
      favorites.remove(code);
      favoriteThresholds.remove(code);
    }
    notifyListeners();
    await _persist();
  }
}

// ---------------------------------------------------------------------------
// UI sound effects (synthesized, bundled as assets/sounds/*.wav)
// ---------------------------------------------------------------------------

class SoundService {
  static final AudioPlayer _tapPlayer = AudioPlayer();
  static final AudioPlayer _splashPlayer = AudioPlayer();

  static Future<void> playSplash() async {
    if (!AppState.I.uiSoundsEnabled) return;
    try {
      await _splashPlayer.play(AssetSource('sounds/splash.wav'), volume: 0.8);
    } catch (_) {
      // Best-effort only - a missing/failed sound should never break the UI.
    }
  }

  static Future<void> tap() async {
    if (!AppState.I.uiSoundsEnabled) return;
    try {
      await _tapPlayer.play(AssetSource('sounds/tap.wav'), volume: 0.55);
    } catch (_) {
      // Best-effort only.
    }
  }

  static final AudioPlayer _previewPlayer = AudioPlayer();

  // Explicit user-triggered preview of a notification tone choice in
  // Settings - always plays regardless of the UI-sounds toggle, since the
  // user tapped a "preview" control specifically to hear it.
  static Future<void> previewNotificationSound(String sound) async {
    if (sound == 'default') return;
    try {
      await _previewPlayer.play(AssetSource('sounds/notif_$sound.wav'), volume: 0.8);
    } catch (_) {
      // Best-effort only.
    }
  }
}

// ---------------------------------------------------------------------------
// Home screen widget (Android) - shows up to 4 favorite servers with their
// player counts. Native side lives in android_widget/ (copied into the
// CI-generated android/ project) since it can't be Dart/Flutter code.
// ---------------------------------------------------------------------------

class WidgetService {
  static const _providerName = 'FavoritesWidgetProvider';

  static Future<void> pushFavorites(List<GameServer> favoriteServers) async {
    try {
      final entries = favoriteServers.take(4).map((s) => {
            'name': s.hostname,
            'players': '${fmtNum(s.clients)}/${fmtNum(s.svMaxclients)}',
          }).toList();
      await HomeWidget.saveWidgetData<String>('favoritesJson', jsonEncode(entries));
      await HomeWidget.updateWidget(name: _providerName);
    } catch (_) {
      // Best-effort only - a missing widget/host device shouldn't crash anything.
    }
  }
}

// Drop-in replacement for InkWell that also plays a short UI tap sound
// (best-effort, silently does nothing if sounds are off or fail to load).
// Every InkWell in this file was mechanically switched to this widget so
// taps make a sound app-wide; it forwards the same handful of named
// parameters actually used across the codebase (onTap, onLongPress,
// borderRadius, child).
class SoundInkWell extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Widget child;

  const SoundInkWell({
    super.key,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    required this.child,
  });

  static void _feedback() {
    SoundService.tap();
    if (AppState.I.hapticsEnabled) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              _feedback();
              onTap!();
            },
      onLongPress: onLongPress == null
          ? null
          : () {
              _feedback();
              onLongPress!();
            },
      borderRadius: borderRadius,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Background favorite-player-count check + local notifications
// ---------------------------------------------------------------------------

Future<void> _showNotification(
  FlutterLocalNotificationsPlugin plugin,
  int id,
  String title,
  String body, {
  bool vibration = true,
  String sound = 'default',
}) async {
  // Android locks a channel's sound once created, so each sound choice
  // gets its own channel id - switching the setting just routes future
  // notifications to a different (lazily created) channel.
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      'favorite_server_channel_$sound',
      'Favoriten-Benachrichtigungen',
      channelDescription: 'Benachrichtigungen für favorisierte Server',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: vibration,
      sound: sound == 'default' ? null : RawResourceAndroidNotificationSound('notif_$sound'),
    ),
  );
  await plugin.show(id, title, body, details);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? const [];
      if (favorites.isEmpty) return true;
      // Presence in favoriteThresholds means notifications are enabled for
      // that favorite; there's no global on/off switch anymore.
      final favoriteThresholds = <String, int>{
        for (final entry in prefs.getStringList('favoriteThresholds') ?? const [])
          if (entry.contains(':')) entry.split(':').first: int.tryParse(entry.split(':').last) ?? 10,
      };
      final vibration = prefs.getBool('notificationVibration') ?? true;
      final sound = prefs.getString('notificationSound') ?? 'default';
      final lang = prefs.getString('language') ?? 'de';
      String t(String key) => _strings[key]?[lang] ?? _strings[key]?['en'] ?? _strings[key]?['de'] ?? key;

      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(const InitializationSettings(android: androidInit));

      final servers = await ApiService.fetchTopServers();
      final byCode = {for (final s in servers) s.code: s};
      var notificationId = 5000;

      // Track each favorite's online/offline status across background runs
      // (first observation of a given favorite only establishes a
      // baseline - it never fires a notification by itself).
      final trackedCodes = (prefs.getStringList('favoritesTracked') ?? const []).toSet();
      final onlineCodes = (prefs.getStringList('favoritesOnlineSnapshot') ?? const []).toSet();
      final knownNames = <String, String>{
        for (final entry in prefs.getStringList('favoritesHostnames') ?? const [])
          if (entry.contains('::')) entry.split('::').first: entry.split('::').skip(1).join('::'),
      };

      final newTracked = <String>{};
      final newOnline = <String>{};
      final newNames = <String, String>{};
      final onlineFavoriteServers = <GameServer>[];

      for (final code in favorites) {
        final server = byCode[code];
        final isOnline = server != null;
        newTracked.add(code);
        final displayName = server?.hostname ?? knownNames[code] ?? code;
        newNames[code] = displayName;
        if (isOnline) {
          newOnline.add(code);
          onlineFavoriteServers.add(server);
        }

        final notifyEnabled = favoriteThresholds.containsKey(code);
        if (notifyEnabled && trackedCodes.contains(code)) {
          final wasOnline = onlineCodes.contains(code);
          if (wasOnline && !isOnline) {
            await _showNotification(
              plugin,
              notificationId++,
              t('favoriteOfflineTitle'),
              t('favoriteOfflineBody').replaceAll('{name}', displayName),
              vibration: vibration,
              sound: sound,
            );
          } else if (!wasOnline && isOnline) {
            await _showNotification(
              plugin,
              notificationId++,
              t('favoriteOnlineTitle'),
              t('favoriteOnlineBody').replaceAll('{name}', displayName),
              vibration: vibration,
              sound: sound,
            );
          }
        }

        final effectiveThreshold = favoriteThresholds[code];
        if (notifyEnabled && isOnline && server.clients >= (effectiveThreshold ?? 10)) {
          await _showNotification(
            plugin,
            notificationId++,
            displayName,
            t('favoriteThresholdBody').replaceAll('{clients}', '${server.clients}'),
            vibration: vibration,
            sound: sound,
          );
        }
      }

      await prefs.setStringList('favoritesTracked', newTracked.toList());
      await prefs.setStringList('favoritesOnlineSnapshot', newOnline.toList());
      await prefs.setStringList('favoritesHostnames', [for (final e in newNames.entries) '${e.key}::${e.value}']);

      onlineFavoriteServers.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
      await WidgetService.pushFavorites(onlineFavoriteServers);
    } catch (_) {
      // Best-effort background task - failures shouldn't crash anything.
    }
    return true;
  });
}

Future<void> _initNotifications() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await AppState.I.load();
    } catch (_) {
      // Fall back to in-memory defaults if persisted prefs can't be read.
    }
    try {
      await _initNotifications();
    } catch (_) {
      // Notifications are best-effort; the app still works without them.
    }
    try {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        kFavoriteCheckTask,
        kFavoriteCheckTask,
        frequency: const Duration(minutes: 15),
      );
    } catch (_) {
      // Background scheduling is best-effort; the app still works without it.
    }
    runApp(const FivemBrowserApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class FivemBrowserApp extends StatefulWidget {
  const FivemBrowserApp({super.key});

  @override
  State<FivemBrowserApp> createState() => _FivemBrowserAppState();
}

class _FivemBrowserAppState extends State<FivemBrowserApp> with WidgetsBindingObserver {
  final QuickActions _quickActions = QuickActions();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initQuickActions();
  }

  void _initQuickActions() {
    _quickActions.initialize((shortcutType) {
      final nav = appNavigatorKey.currentState;
      if (nav == null) return;
      if (shortcutType == 'serverlist') {
        nav.push(MaterialPageRoute(builder: (_) => const ServerListPage()));
      } else if (shortcutType == 'favorites') {
        nav.push(MaterialPageRoute(builder: (_) => const FavoritesPage()));
      }
    });
    _quickActions.setShortcutItems([
      ShortcutItem(type: 'serverlist', localizedTitle: tr('serverList'), icon: 'ic_shortcut'),
      ShortcutItem(type: 'favorites', localizedTitle: tr('favorites'), icon: 'ic_shortcut'),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Only matters in 'auto' mode, but a harmless rebuild otherwise -
    // AppState itself doesn't change, so ListenableBuilder alone
    // wouldn't pick up a system-level brightness flip.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final isDark = AppState.I.isDark;
        final base = isDark
            ? ThemeData.dark(useMaterial3: true)
            : ThemeData.light(useMaterial3: true);
        SystemChrome.setSystemUIOverlayStyle(
          isDark
              ? const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark,
                )
              : const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.dark,
                  statusBarBrightness: Brightness.light,
                ),
        );
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Fserver',
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            scaffoldBackgroundColor: kBg,
            colorScheme: base.colorScheme.copyWith(
              brightness: isDark ? Brightness.dark : Brightness.light,
              primary: kAccent,
              secondary: kAccent,
              surface: kSurface,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              // Always white: this only styles the ServerDetailPage's back
              // button, which sits on top of the server banner image, not
              // the app's own theme-dependent background.
              foregroundColor: Colors.white,
            ),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            textTheme: base.textTheme.apply(
              bodyColor: kFgAlpha(0.92),
              displayColor: kFg,
              fontSizeFactor: 0.93,
            ),
            dividerColor: kFgAlpha(0.08),
            useMaterial3: true,
          ),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(AppState.I.textScale)),
              child: child!,
            );
          },
          home: const SplashPage(),
        );
      },
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    SoundService.playSplash();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppState.I.onboardingDone ? const MainMenuPage() : const OnboardingPage(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Icon(Icons.dns, size: 64, color: kAccent),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

String stripColorCodes(String input) {
  return input.replaceAll(RegExp(r'\^[0-9]'), '');
}

// Thousand separators for large player counts (e.g. big FiveM servers
// with 1024+ slots) - "." per common German/European convention.
String fmtNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return false;
}

List<String> _asStringList(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

List<PlayerInfo> _asPlayerList(dynamic v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((m) => PlayerInfo.fromMap(m.cast<String, dynamic>()))
        .toList();
  }
  return const [];
}

class PlayerInfo {
  final int id;
  final String name;
  final int ping;

  const PlayerInfo({required this.id, required this.name, required this.ping});

  factory PlayerInfo.fromMap(Map<String, dynamic> m) {
    return PlayerInfo(
      id: _asInt(m['id']),
      name: stripColorCodes((m['name'] ?? '?').toString()),
      ping: _asInt(m['ping']),
    );
  }
}

// vars keys already surfaced through a dedicated field elsewhere in the
// UI, or internal FXServer convars not interesting to show to a player.
const Set<String> _knownVarsKeys = {
  'sv_projectname',
  'sv_projectdesc',
  'locale',
  'tags',
  'banner_detail',
  'banner_connecting',
  'onesync_enabled',
  'sv_enforcegamebuild',
  'sv_maxclients',
  'sv_scripthookallowed',
  'sv_appearallowlisted',
  'premium',
  'sv_enhancedhostsupport',
  'activitypubfeed',
  'sv_licensekeytoken',
  'sv_lan',
};

class ServerVars {
  final String? projectName;
  final String? projectDesc;
  final String? locale;
  final List<String> tags;
  final String? bannerDetail;
  final bool onesyncEnabled;
  final String? enforceGameBuild;
  // Server-operator-defined custom vars (e.g. "Website", "Discord",
  // "Fahrzeuge") that aren't part of the fixed field set above.
  final Map<String, String> extra;

  const ServerVars({
    this.projectName,
    this.projectDesc,
    this.locale,
    this.tags = const [],
    this.bannerDetail,
    this.onesyncEnabled = false,
    this.enforceGameBuild,
    this.extra = const {},
  });

  factory ServerVars.fromMap(Map<String, dynamic> m) {
    final rawTags = (m['tags'] ?? '').toString();
    final tags = rawTags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    String? nullIfEmpty(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final projectName = nullIfEmpty(m['sv_projectName']);
    final projectDesc = nullIfEmpty(m['sv_projectDesc']);

    final extra = <String, String>{};
    for (final key in m.keys) {
      if (_knownVarsKeys.contains(key.toLowerCase())) continue;
      final value = nullIfEmpty(m[key]);
      if (value == null) continue;
      extra[key.replaceAll(':', '').trim()] = stripColorCodes(value);
    }

    return ServerVars(
      projectName: projectName != null ? stripColorCodes(projectName) : null,
      projectDesc: projectDesc != null ? stripColorCodes(projectDesc) : null,
      locale: nullIfEmpty(m['locale']),
      tags: tags,
      bannerDetail: nullIfEmpty(m['banner_detail']),
      onesyncEnabled: _asBool(m['onesync_enabled']),
      enforceGameBuild: nullIfEmpty(m['sv_enforceGameBuild']),
      extra: extra,
    );
  }
}

class GameServer {
  final String endPoint;
  final String code;
  final String hostnameRaw;
  final String hostname;
  final int clients;
  final int svMaxclients;
  final String gametype;
  final String mapname;
  final String iconVersion;
  final int upvotePower;
  final List<String> resources;
  final List<PlayerInfo> players;
  final ServerVars vars;

  const GameServer({
    required this.endPoint,
    required this.code,
    required this.hostnameRaw,
    required this.hostname,
    required this.clients,
    required this.svMaxclients,
    required this.gametype,
    required this.mapname,
    required this.iconVersion,
    required this.upvotePower,
    required this.resources,
    required this.players,
    required this.vars,
  });

  factory GameServer.fromEntry(Map<String, dynamic> entry) {
    final endPoint = (entry['EndPoint'] ?? '').toString();
    final data = (entry['Data'] is Map)
        ? (entry['Data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final varsMap =
        (data['vars'] is Map) ? (data['vars'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final rawHostname = (data['hostname'] ?? endPoint).toString();

    return GameServer(
      endPoint: endPoint,
      code: _extractCode(endPoint),
      hostnameRaw: rawHostname,
      hostname: stripColorCodes(rawHostname),
      clients: _asInt(data['clients']),
      svMaxclients: _asInt(data['svMaxclients']),
      gametype: stripColorCodes((data['gametype'] ?? '').toString()),
      mapname: stripColorCodes((data['mapname'] ?? '').toString()),
      iconVersion: (data['iconVersion'] ?? '0').toString(),
      upvotePower: _asInt(data['upvotePower']),
      resources: _asStringList(data['resources']),
      players: _asPlayerList(data['players']),
      vars: ServerVars.fromMap(varsMap),
    );
  }

  static String _extractCode(String endPoint) {
    final match =
        RegExp(r'^([a-zA-Z0-9]+)\.users\.cfx\.re(?::\d+)?$').firstMatch(endPoint);
    if (match != null) return match.group(1)!;
    return endPoint;
  }

  // `vars.locale` is free text set by each server operator (not a
  // validated ISO code), so raw values are wildly inconsistent ("DE",
  // "GER", "D", "USA", "EUA", ...). Only a handful of countries are
  // curated into flags; everything else shows no country badge.
  static const Map<String, Set<String>> _countryAliasGroups = {
    'DE': {'DE', 'GER', 'GERMANY', 'DEUTSCHLAND', 'D', 'DA'},
    'IT': {'IT', 'ITA', 'ITALY', 'ITALIA'},
    'US': {'US', 'USA', 'EUA', 'AMERICA', 'UNITEDSTATES'},
    'FR': {'FR', 'FRA', 'FRANCE', 'FRANCAIS', 'FRANÇAIS'},
    'ES': {'ES', 'ESP', 'SPAIN', 'ESPANA', 'ESPAÑA', 'LATAM', 'LATINOAMERICA', 'LATINOAMÉRICA', 'MX', 'MEXICO', 'MÉXICO', 'AR', 'ARGENTINA'},
    'PL': {'PL', 'POL', 'POLAND', 'POLSKA'},
    'NL': {'NL', 'NLD', 'NETHERLANDS', 'HOLLAND', 'NEDERLAND'},
    'PT': {'PT', 'PRT', 'PORTUGAL', 'BR', 'BRA', 'BRAZIL', 'BRASIL'},
    'TR': {'TR', 'TUR', 'TURKEY', 'TURKIYE', 'TÜRKİYE'},
  };

  String? get countryGroup {
    final locale = vars.locale;
    if (locale == null || locale.isEmpty) return null;
    final normalized = locale.toUpperCase().trim();
    final parts =
        normalized.split(RegExp(r'[-_\s]+')).where((p) => p.isNotEmpty);
    final candidates = <String>{normalized, ...parts};
    for (final entry in _countryAliasGroups.entries) {
      if (candidates.any(entry.value.contains)) return entry.key;
    }
    return null;
  }

  Set<String> get tagsLower => vars.tags.map((t) => t.toLowerCase()).toSet();

  String get iconUrl =>
      'https://frontend.cfx-services.net/api/servers/icon/$code/$iconVersion.png';

  String get joinUrl => 'cfx.re/join/$code';
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

// Minimal protobuf wire-format reader: enough to walk an unknown message's
// fields (varint / length-delimited / 32-bit / 64-bit) without needing a
// full .proto-generated schema or an extra dependency.
class _ProtoReader {
  final Uint8List bytes;
  int _offset = 0;

  _ProtoReader(this.bytes);

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = bytes[_offset++];
      result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  Uint8List _readBytes(int length) {
    final chunk = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return chunk;
  }

  /// Field number -> list of raw values (int for varint/fixed, Uint8List
  /// for length-delimited), in encounter order, since fields may repeat.
  Map<int, List<Object>> readFields() {
    final fields = <int, List<Object>>{};
    while (_offset < bytes.length) {
      final tag = _readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;
      Object value;
      switch (wireType) {
        case 0:
          value = _readVarint();
          break;
        case 1:
          value = _readBytes(8);
          break;
        case 2:
          final len = _readVarint();
          value = _readBytes(len);
          break;
        case 5:
          value = _readBytes(4);
          break;
        default:
          return fields;
      }
      fields.putIfAbsent(fieldNumber, () => []).add(value);
    }
    return fields;
  }
}

class ApiService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
    'Origin': 'https://servers.fivem.net',
    'Referer': 'https://servers.fivem.net/',
  };

  // The site doesn't have a server-side "top N by country" route: it
  // downloads the full server dump via a redirect-based stream endpoint
  // and filters/sorts it client-side, so we do the same.
  static const List<String> _topUrls = [
    'https://frontend.cfx-services.net/api/servers/streamRedir/',
    'https://servers-frontend.fivem.net/api/servers/streamRedir/',
  ];

  static const List<String> _singleUrls = [
    'https://frontend.cfx-services.net/api/servers/single/',
    'https://servers-frontend.fivem.net/api/servers/single/',
  ];

  static Future<List<GameServer>> fetchTopServers() async {
    final attemptErrors = <String>[];
    for (final url in _topUrls) {
      try {
        final res = await _getWithDohFallback(
          Uri.parse(url),
          timeout: const Duration(seconds: 60),
        );
        if (res.statusCode == 200) {
          final bytes = Uint8List.fromList(_gunzipIfNeeded(res.bodyBytes));
          final servers = await compute(_parseList, bytes);
          if (servers.isNotEmpty) return servers;
          attemptErrors.add('$url: leere Antwort');
        } else {
          attemptErrors.add('$url: HTTP ${res.statusCode}');
        }
      } catch (e) {
        attemptErrors.add('$url: $e');
      }
    }
    throw ApiException(
        'Serverliste konnte nicht geladen werden.\n${attemptErrors.join('\n')}');
  }

  // The stream feed is NOT JSON: it's a sequence of length-prefixed
  // protobuf messages (confirmed against the open-source "cfx-api"
  // reference implementation). Each record is:
  //   [4-byte little-endian uint32 length][that many bytes: a `Server`
  //   protobuf message with field 1 = EndPoint (string), field 2 = Data
  //   (nested message)].
  // Runs in a background isolate via compute() since the full dump can be
  // several megabytes and tens of thousands of entries.
  static List<GameServer> _parseList(Uint8List bytes) {
    final result = <GameServer>[];
    var offset = 0;
    while (offset + 4 <= bytes.length) {
      final len = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      offset += 4;
      if (len < 0 || offset + len > bytes.length) break;
      final record = Uint8List.sublistView(bytes, offset, offset + len);
      offset += len;
      try {
        final entry = _decodeServerEntry(record);
        if (entry != null) {
          result.add(GameServer.fromEntry(entry));
        }
      } catch (_) {
        // skip malformed entries
      }
    }
    return result;
  }

  static Map<String, dynamic>? _decodeServerEntry(Uint8List bytes) {
    final fields = _ProtoReader(bytes).readFields();
    final endpointRaw = fields[1]?.first;
    final dataRaw = fields[2]?.first;
    if (endpointRaw is! Uint8List || dataRaw is! Uint8List) return null;
    return {
      'EndPoint': utf8.decode(endpointRaw, allowMalformed: true),
      'Data': _decodeServerData(dataRaw),
    };
  }

  static Map<String, dynamic> _decodeServerData(Uint8List bytes) {
    final fields = _ProtoReader(bytes).readFields();

    String? stringField(int number) {
      final v = fields[number]?.first;
      return v is Uint8List ? utf8.decode(v, allowMalformed: true) : null;
    }

    int intField(int number) {
      final v = fields[number]?.first;
      return v is int ? v : 0;
    }

    List<String> repeatedString(int number) {
      return (fields[number] ?? const [])
          .whereType<Uint8List>()
          .map((b) => utf8.decode(b, allowMalformed: true))
          .toList();
    }

    final vars = <String, dynamic>{};
    for (final entryBytes in fields[12] ?? const []) {
      if (entryBytes is! Uint8List) continue;
      final entryFields = _ProtoReader(entryBytes).readFields();
      final keyRaw = entryFields[1]?.first;
      final valueRaw = entryFields[2]?.first;
      if (keyRaw is Uint8List && valueRaw is Uint8List) {
        vars[utf8.decode(keyRaw, allowMalformed: true)] =
            utf8.decode(valueRaw, allowMalformed: true);
      }
    }

    final players = <Map<String, dynamic>>[];
    for (final playerBytes in fields[10] ?? const []) {
      if (playerBytes is! Uint8List) continue;
      final p = _ProtoReader(playerBytes).readFields();
      final nameRaw = p[1]?.first;
      players.add({
        'name': nameRaw is Uint8List ? utf8.decode(nameRaw, allowMalformed: true) : '',
        'ping': (p[4]?.first is int) ? p[4]!.first as int : 0,
        'id': (p[5]?.first is int) ? p[5]!.first as int : 0,
      });
    }

    return {
      'svMaxclients': intField(1),
      'clients': intField(2),
      'hostname': stringField(4) ?? '',
      'gametype': stringField(5) ?? '',
      'mapname': stringField(6) ?? '',
      'resources': repeatedString(8),
      'iconVersion': intField(11),
      'vars': vars,
      'upvotePower': intField(17),
      'players': players,
    };
  }

  static Future<GameServer> fetchServerDetail(String code) async {
    final attemptErrors = <String>[];
    for (final base in _singleUrls) {
      final url = '$base$code';
      try {
        final res = await _getWithDohFallback(
          Uri.parse(url),
          timeout: const Duration(seconds: 20),
        );
        if (res.statusCode != 200) {
          attemptErrors.add('$url: HTTP ${res.statusCode}');
          continue;
        }
        final decoded = jsonDecode(_bodyText(res));
        // fromEntry expects the *whole* {EndPoint, Data} wrapper (it does
        // its own entry['Data'] lookup) - passing decoded['Data'] here
        // directly was the long-standing bug that left every field empty.
        if (decoded is Map &&
            (decoded['Data'] is Map || decoded['EndPoint'] != null)) {
          return GameServer.fromEntry(decoded.cast<String, dynamic>());
        }
        attemptErrors.add('$url: unerwartetes Antwortformat');
      } catch (e) {
        attemptErrors.add('$url: $e');
      }
    }
    throw ApiException(
        'Serverdetails konnten nicht geladen werden.\n${attemptErrors.join('\n')}');
  }

  // The stream endpoint's response isn't always transparently
  // gzip-decompressed depending on the connection path taken, so decode
  // defensively: unzip if the bytes still look gzip-compressed, then
  // decode as UTF-8, falling back to Latin-1 so a stray invalid byte
  // somewhere in a server's user-supplied fields can't crash parsing.
  static String _bodyText(http.Response res) {
    final bytes = _gunzipIfNeeded(res.bodyBytes);
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static List<int> _gunzipIfNeeded(List<int> bytes) {
    if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      try {
        return gzip.decode(bytes);
      } catch (_) {
        return bytes;
      }
    }
    return bytes;
  }

  static final Map<String, InternetAddress> _dohIpCache = {};

  // Some networks filter the plain system DNS resolver (e.g. carrier
  // "youth protection" filters or a local ad-blocking VPN) while leaving
  // browsers unaffected because they use encrypted DNS-over-HTTPS. If the
  // normal request fails with a DNS lookup error, fall back to resolving
  // the host via Cloudflare's DoH endpoint and connecting to that IP
  // directly, mirroring what the browser does under the hood.
  static Future<http.Response> _getWithDohFallback(
    Uri uri, {
    required Duration timeout,
  }) async {
    try {
      return await http.get(uri, headers: _headers).timeout(timeout);
    } catch (e) {
      if (!_looksLikeDnsFailure(e)) rethrow;
      return _getViaDoh(uri, timeout: timeout);
    }
  }

  static bool _looksLikeDnsFailure(Object e) {
    final msg = e.toString();
    return msg.contains('Failed host lookup') ||
        msg.contains('No address associated with hostname');
  }

  // Two independent public DoH resolvers, tried in order, in case a
  // network specifically blocks one well-known resolver IP.
  static const List<String> _dohProviders = [
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/resolve',
  ];

  static Future<InternetAddress> _resolveViaDoh(String host) async {
    final cached = _dohIpCache[host];
    if (cached != null) return cached;
    final errors = <String>[];
    for (final base in _dohProviders) {
      try {
        final res = await http.get(
          Uri.parse('$base?name=$host&type=A'),
          headers: const {'Accept': 'application/dns-json'},
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) {
          errors.add('$base: HTTP ${res.statusCode}');
          continue;
        }
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['Answer'] is List) {
          for (final answer in decoded['Answer'] as List) {
            if (answer is Map &&
                answer['type'] == 1 &&
                answer['data'] is String) {
              final ip = InternetAddress.tryParse(answer['data'] as String);
              if (ip != null) {
                _dohIpCache[host] = ip;
                return ip;
              }
            }
          }
        }
        errors.add('$base: keine A-Record-Antwort');
      } catch (e) {
        errors.add('$base: $e');
      }
    }
    throw ApiException(
        'DoH-Auflösung fehlgeschlagen für $host (${errors.join(' | ')})');
  }

  static Future<http.Response> _getViaDoh(
    Uri uri, {
    required Duration timeout,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      final ip = await _resolveViaDoh(url.host);
      final socket = await Socket.connect(ip, url.port, timeout: timeout);
      return ConnectionTask.fromSocket(
        Future.value(socket),
        () => socket.destroy(),
      );
    };
    try {
      final request = await client.getUrl(uri);
      _headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return http.Response.bytes(bytes, response.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared glass widgets
// ---------------------------------------------------------------------------

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;
  final double borderOpacity;
  final BorderRadius borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.blur = 22,
    this.opacity = 0.05,
    this.borderOpacity = 0.10,
    this.borderRadius = const BorderRadius.all(Radius.circular(kRadius)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: kFgAlpha(borderOpacity),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kFgAlpha(opacity + 0.03),
                kFgAlpha(opacity * 0.3),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback? onTap;
  final Color? tintColor;
  final Widget? leading;

  const Pill({
    super.key,
    required this.text,
    this.active = false,
    this.onTap,
    this.tintColor,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final color = tintColor ?? kAccent;
    return SoundInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadius),
          color: active ? color.withValues(alpha: 0.18) : kFgAlpha(0.05),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.65) : kFgAlpha(0.12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 5)],
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1,
                color: active ? kFg : kFgAlpha(0.75),
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Small custom-painted flag chips for the curated country list - plain
// color blocks (no images, no emoji), since national flag designs are
// public symbols with no copyright concern (unlike e.g. game map art).
// Simplified on purpose (no coats of arms / crescent details) to stay
// legible at chip size.
class CountryFlag extends StatelessWidget {
  final String code;
  final double width;
  const CountryFlag({super.key, required this.code, this.width = 18});

  double get _height => width * 2 / 3;

  static Widget _stripesH(List<Color> colors) {
    return Column(children: colors.map((c) => Expanded(child: Container(color: c))).toList());
  }

  static Widget _stripesV(List<Color> colors) {
    return Row(children: colors.map((c) => Expanded(child: Container(color: c))).toList());
  }

  Widget _flagFor(String code) {
    switch (code) {
      case 'DE':
        return _stripesH([Colors.black, const Color(0xFFDD0000), const Color(0xFFFFCE00)]);
      case 'IT':
        return _stripesV([const Color(0xFF009246), Colors.white, const Color(0xFFCE2B37)]);
      case 'FR':
        return _stripesV([const Color(0xFF0055A4), Colors.white, const Color(0xFFEF4135)]);
      case 'ES':
        return _stripesH([const Color(0xFFAA151B), const Color(0xFFF1BF00), const Color(0xFFAA151B)]);
      case 'PL':
        return _stripesH([Colors.white, const Color(0xFFDC143C)]);
      case 'NL':
        return _stripesH([const Color(0xFFAE1C28), Colors.white, const Color(0xFF21468B)]);
      case 'PT':
        return Row(
          children: [
            Expanded(flex: 2, child: Container(color: const Color(0xFF006600))),
            Expanded(flex: 3, child: Container(color: const Color(0xFFFF0000))),
          ],
        );
      case 'TR':
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFFE30A17)),
            Center(
              child: Container(
                width: _height * 0.45,
                height: _height * 0.45,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ],
        );
      case 'US':
        return Stack(
          fit: StackFit.expand,
          children: [
            _stripesH(List.generate(5, (i) => i.isEven ? const Color(0xFFB22234) : Colors.white)),
            Align(
              alignment: Alignment.topLeft,
              child: Container(width: width * 0.4, height: _height * 0.55, color: const Color(0xFF3C3B6E)),
            ),
          ],
        );
      default:
        return Container(color: Colors.grey.shade600);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(width: width, height: _height, child: _flagFor(code)),
    );
  }
}

// ---------------------------------------------------------------------------
// Server list page
// ---------------------------------------------------------------------------

enum TagState { neutral, include, exclude }

class ServerListPage extends StatefulWidget {
  final String? initialSearch;
  const ServerListPage({super.key, this.initialSearch});

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

enum SortMode { defaultOrder, mostPlayers, mostBoost }

// Upper bound of the player-count range filter; the slider's top handle
// means "no upper limit" rather than a hard cap at this value.
const double kPlayerRangeMax = 256;

class _ServerListPageState extends State<ServerListPage> {
  List<GameServer> _servers = [];
  List<String> _topTags = [];
  bool _loading = true;
  String? _error;

  bool _filtersOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _hideEmpty = false;
  bool _hideFull = false;
  String? _selectedCountry;
  final Map<String, TagState> _tagStates = {};
  SortMode _sortMode = SortMode.defaultOrder;
  RangeValues _playerRange = const RangeValues(0, kPlayerRangeMax);
  Timer? _countdownTimer;
  int _secondsUntilRefresh = 0;
  // In-memory only (not persisted - the full feed has 30k+ codes, far too
  // many to store in SharedPreferences). Servers that weren't present in
  // the previous in-session load get a "NEU" badge; the very first load
  // has nothing to compare against, so nothing is flagged new yet.
  Set<String>? _previousCodes;
  Set<String> _newCodes = {};

  int get _autoRefreshSeconds => AppState.I.refreshIntervalMinutes * 60;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialSearch != null) _searchCtrl.text = widget.initialSearch!;
    _searchCtrl.addListener(() => setState(() {}));
    _secondsUntilRefresh = _autoRefreshSeconds;
    // A single 1s ticker both drives the countdown display and triggers
    // the refresh itself (instead of a separate 60s Timer.periodic), so
    // changing the interval in Settings takes effect on the very next
    // tick without needing to tear down/recreate a periodic timer.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsUntilRefresh > 0) {
          _secondsUntilRefresh--;
        } else {
          _secondsUntilRefresh = _autoRefreshSeconds;
          if (!_loading) _load();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _secondsUntilRefresh = _autoRefreshSeconds;
    });
    try {
      final servers = await ApiService.fetchTopServers();
      servers.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
      final codes = servers.map((s) => s.code).toSet();
      final newCodes = _previousCodes == null ? <String>{} : codes.difference(_previousCodes!);
      setState(() {
        _servers = servers;
        _topTags = _computeTopTags(servers);
        _newCodes = newCodes;
        _previousCodes = codes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Curated, fixed set rather than derived from data - `vars.locale` is
  // free text and produces dozens of near-duplicate junk values.
  static const List<String> _availableCountries = ['DE', 'IT', 'US', 'FR', 'ES', 'PL', 'NL', 'PT', 'TR'];

  // Computed once when the list loads (not on every rebuild - with 30k+
  // servers this was the main source of the filter panel's lag), and
  // capped to the most common tags so the chip list stays small.
  static List<String> _computeTopTags(List<GameServer> servers) {
    final counts = <String, int>{};
    for (final s in servers) {
      for (final tag in s.tagsLower) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted.take(24).toList();
  }

  List<GameServer> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();
    final activeTagFilters =
        _tagStates.entries.where((e) => e.value != TagState.neutral).toList();
    final noUpperPlayerBound = _playerRange.end >= kPlayerRangeMax;

    final result = _servers.where((s) {
      if (query.isNotEmpty && !s.hostname.toLowerCase().contains(query)) {
        return false;
      }
      if (_hideEmpty && s.clients == 0) return false;
      if (_hideFull && s.svMaxclients > 0 && s.clients >= s.svMaxclients) {
        return false;
      }
      if (_selectedCountry != null && s.countryGroup != _selectedCountry) {
        return false;
      }
      if (s.clients < _playerRange.start) return false;
      if (!noUpperPlayerBound && s.clients > _playerRange.end) return false;
      for (final entry in activeTagFilters) {
        final has = s.tagsLower.contains(entry.key);
        if (entry.value == TagState.include && !has) return false;
        if (entry.value == TagState.exclude && has) return false;
      }
      return true;
    }).toList();

    switch (_sortMode) {
      case SortMode.defaultOrder:
        break;
      case SortMode.mostPlayers:
        result.sort((a, b) => b.clients.compareTo(a.clients));
        break;
      case SortMode.mostBoost:
        result.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
        break;
    }
    return result;
  }

  void _cycleTag(String tag) {
    setState(() {
      final current = _tagStates[tag] ?? TagState.neutral;
      switch (current) {
        case TagState.neutral:
          _tagStates[tag] = TagState.include;
          break;
        case TagState.include:
          _tagStates[tag] = TagState.exclude;
          break;
        case TagState.exclude:
          _tagStates[tag] = TagState.neutral;
          break;
      }
    });
  }

  static String _formatCountdown(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(filtered.length),
            if (_filtersOpen) _buildFilterPanel(),
            Expanded(child: _buildBody(filtered)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
              Text(
                tr('serverList'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  color: kFgAlpha(0.45),
                ),
              ),
              const Spacer(),
              if (!_loading)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _formatCountdown(_secondsUntilRefresh),
                    style: TextStyle(fontSize: 11, color: kFgAlpha(0.3)),
                  ),
                ),
              _iconButton(
                icon: _filtersOpen ? Icons.tune : Icons.tune_outlined,
                active: _filtersOpen,
                onTap: () => setState(() => _filtersOpen = !_filtersOpen),
              ),
              const SizedBox(width: 8),
              _iconButton(
                icon: Icons.refresh,
                onTap: _loading ? null : _load,
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: kFgAlpha(0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) => AppState.I.addSearchTerm(v),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: tr('search'),
                    ),
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  SoundInkWell(
                    onTap: () => _searchCtrl.clear(),
                    child: Icon(Icons.close, size: 16, color: kFgAlpha(0.5)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({required IconData icon, VoidCallback? onTap, bool active = false}) {
    return GlassPanel(
      padding: const EdgeInsets.all(8),
      opacity: active ? 0.14 : 0.05,
      child: SoundInkWell(
        onTap: onTap,
        child: Icon(icon, size: 18, color: active ? kAccent : kFgAlpha(0.8)),
      ),
    );
  }

  Widget _buildFilterPanel() {
    final countries = _availableCountries;
    final tags = _topTags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Pill(
                    text: tr('hideEmpty'),
                    active: _hideEmpty,
                    onTap: () => setState(() => _hideEmpty = !_hideEmpty),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Pill(
                    text: tr('hideFull'),
                    active: _hideFull,
                    onTap: () => setState(() => _hideFull = !_hideFull),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionLabel(tr('sortBy')),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill(
                  text: tr('sortDefault'),
                  active: _sortMode == SortMode.defaultOrder,
                  onTap: () => setState(() => _sortMode = SortMode.defaultOrder),
                ),
                Pill(
                  text: tr('sortMostPlayers'),
                  active: _sortMode == SortMode.mostPlayers,
                  onTap: () => setState(() => _sortMode = SortMode.mostPlayers),
                ),
                Pill(
                  text: tr('sortMostBoost'),
                  active: _sortMode == SortMode.mostBoost,
                  onTap: () => setState(() => _sortMode = SortMode.mostBoost),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _sectionLabel(tr('playerRange'))),
                Text(
                  _playerRange.end >= kPlayerRangeMax
                      ? '${_playerRange.start.round()}+'
                      : '${_playerRange.start.round()}-${_playerRange.end.round()}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kAccent),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: RangeSlider(
                values: _playerRange,
                min: 0,
                max: kPlayerRangeMax,
                divisions: 32,
                activeColor: kAccent,
                inactiveColor: kFgAlpha(0.12),
                onChanged: (v) => setState(() => _playerRange = v),
              ),
            ),
            if (countries.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionLabel(tr('country')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: countries.map((c) {
                  final active = _selectedCountry == c;
                  return Pill(
                    text: c,
                    leading: CountryFlag(code: c, width: 16),
                    active: active,
                    onTap: () => setState(() {
                      _selectedCountry = active ? null : c;
                    }),
                  );
                }).toList(),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionLabel(tr('tagsHint')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags.map((t) {
                  final state = _tagStates[t] ?? TagState.neutral;
                  return Pill(
                    text: t,
                    active: state != TagState.neutral,
                    tintColor: state == TagState.exclude ? Colors.redAccent : kAccent,
                    onTap: () => _cycleTag(t),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: kFgAlpha(0.4),
      ),
    );
  }

  Widget _buildBody(List<GameServer> filtered) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kAccent, strokeWidth: 2.4),
            const SizedBox(height: 14),
            Text(
              'Lade komplette Serverliste…\ndas kann bis zu 30 Sekunden dauern',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.45)),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: kFgAlpha(0.35), size: 36),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: kFgAlpha(0.6), fontSize: 13),
              ),
              const SizedBox(height: 14),
              GlassPanel(
                opacity: 0.10,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: SoundInkWell(
                  onTap: _load,
                  child: Text(tr('retry'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          tr('noServersFound'),
          style: TextStyle(color: kFgAlpha(0.4), fontSize: 13),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kAccent,
      backgroundColor: kSurface,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final s = filtered[index];
          return ServerTile(server: s, isNew: _newCodes.contains(s.code));
        },
      ),
    );
  }
}

class ServerTile extends StatelessWidget {
  final GameServer server;
  final bool selectionMode;
  final bool selected;
  final bool isNew;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectTap;

  const ServerTile({
    super.key,
    required this.server,
    this.selectionMode = false,
    this.selected = false,
    this.isNew = false,
    this.onLongPress,
    this.onSelectTap,
  });

  @override
  Widget build(BuildContext context) {
    return SoundInkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: selectionMode
          ? onSelectTap
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ServerDetailPage(server: server)),
              );
            },
      onLongPress: onLongPress,
      child: GlassPanel(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectionMode) ...[
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? kAccent : kFgAlpha(0.3),
              ),
              const SizedBox(width: 10),
            ],
            _ServerIcon(server: server, size: 52),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.hostname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(kRadius),
                            color: kAccent.withValues(alpha: 0.16),
                          ),
                          child: Text(
                            tr('newBadge'),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kAccent, letterSpacing: 0.3),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (server.vars.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: server.vars.tags.take(3).map((t) {
                        return Text(
                          t,
                          style: TextStyle(fontSize: 10.5, color: kFgAlpha(0.4)),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (server.countryGroup != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountryFlag(code: server.countryGroup!, width: 14),
                      const SizedBox(width: 4),
                      Text(
                        server.countryGroup!,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: kFgAlpha(0.45), letterSpacing: 0.4),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  '${fmtNum(server.clients)}/${fmtNum(server.svMaxclients)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                _BoostBadge(power: server.upvotePower),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BoostBadge extends StatelessWidget {
  final int power;
  const _BoostBadge({required this.power});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        color: kAccent.withValues(alpha: 0.08),
        border: Border.all(color: kAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard_arrow_up, size: 15, color: kAccent),
          Text(
            '$power',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kAccent),
          ),
        ],
      ),
    );
  }
}

class _ServerIcon extends StatelessWidget {
  final GameServer server;
  final double size;
  const _ServerIcon({required this.server, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadius),
      child: Image.network(
        server.iconUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback();
        },
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        color: kFgAlpha(0.05),
      ),
      child: Icon(Icons.dns_outlined, size: size * 0.5, color: kFgAlpha(0.3)),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail page
// ---------------------------------------------------------------------------

class ServerDetailPage extends StatefulWidget {
  final GameServer server;
  const ServerDetailPage({super.key, required this.server});

  @override
  State<ServerDetailPage> createState() => _ServerDetailPageState();
}

class _ServerDetailPageState extends State<ServerDetailPage> with SingleTickerProviderStateMixin {
  // The bulk list feed omits resources and most custom vars (623
  // resources per server would balloon the ~20MB dump massively), so
  // those are fetched separately here. Never lets a bad/partial response
  // regress good data - it can only add resources/extra vars, never
  // remove the reliable list-derived fields.
  late final GameServer _server = widget.server;
  late final TabController _tabController;
  final TextEditingController _scriptCtrl = TextEditingController();
  List<String>? _fetchedResources;
  Map<String, String>? _fetchedExtraVars;
  bool _unreachable = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scriptCtrl.addListener(() => setState(() {}));
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final detail = await ApiService.fetchServerDetail(_server.code);
      if (!mounted) return;
      setState(() {
        if (detail.resources.isNotEmpty) _fetchedResources = detail.resources;
        if (detail.vars.extra.isNotEmpty) _fetchedExtraVars = detail.vars.extra;
      });
    } catch (_) {
      // Best-effort only - the page already shows the list-derived data,
      // but flag it so the user knows the live details couldn't refresh.
      if (mounted) setState(() => _unreachable = true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scriptCtrl.dispose();
    super.dispose();
  }

  void _copyJoin() {
    Clipboard.setData(ClipboardData(text: _server.joinUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        content: Text('${tr('copied')}: ${_server.joinUrl}', style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  void _shareJoin() {
    Share.share('${_server.hostname}\n${_server.joinUrl}');
  }

  void _copyAllInfo() {
    final s = _server;
    final lines = [
      s.hostname,
      s.joinUrl,
      '${tr('players')}: ${fmtNum(s.clients)}/${fmtNum(s.svMaxclients)}',
      if (s.gametype.isNotEmpty) '${tr('gametype')}: ${s.gametype}',
      if (s.mapname.isNotEmpty) '${tr('map')}: ${s.mapname}',
      if (s.vars.tags.isNotEmpty) '${tr('tags')}: ${s.vars.tags.join(', ')}',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        content: Text(tr('copied'), style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    return Scaffold(
      backgroundColor: kBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              backgroundColor: kBg,
              leading: const BackButton(),
              actions: [
                IconButton(
                  onPressed: () async {
                    await AppState.I.toggleFavorite(s.code);
                    if (mounted) setState(() {});
                  },
                  icon: Icon(
                    AppState.I.isFavorite(s.code) ? Icons.star : Icons.star_border,
                    // Always gold/white (not theme-dependent): this icon
                    // sits on top of the server banner image.
                    color: AppState.I.isFavorite(s.code) ? const Color(0xFFE0B45A) : Colors.white,
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _Banner(server: s),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ServerIcon(server: s, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.hostname,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                              if (s.vars.projectName != null && s.vars.projectName != s.hostname) ...[
                                const SizedBox(height: 2),
                                Text(
                                  s.vars.projectName!,
                                  style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.5)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_unreachable) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.error_outline, size: 13, color: Colors.orangeAccent.withValues(alpha: 0.9)),
                          const SizedBox(width: 5),
                          Text(
                            tr('unreachable'),
                            style: TextStyle(fontSize: 11.5, color: Colors.orangeAccent.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SoundInkWell(
                            borderRadius: BorderRadius.circular(kRadius),
                            onTap: _copyJoin,
                            child: GlassPanel(
                              opacity: 0.14,
                              borderOpacity: 0.4,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.content_copy, size: 15, color: kAccent),
                                    const SizedBox(width: 6),
                                    Text(tr('join'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kAccent)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassPanel(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${fmtNum(s.clients)}/${fmtNum(s.svMaxclients)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SoundInkWell(
                          borderRadius: BorderRadius.circular(kRadius),
                          onTap: _shareJoin,
                          child: GlassPanel(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.share_outlined, size: 17, color: kFgAlpha(0.85)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SoundInkWell(
                          borderRadius: BorderRadius.circular(kRadius),
                          onTap: _copyAllInfo,
                          child: GlassPanel(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.content_copy_outlined, size: 17, color: kFgAlpha(0.85)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: kAccent,
                  indicatorWeight: 2,
                  labelColor: kFg,
                  unselectedLabelColor: kFgAlpha(0.4),
                  labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: tr('overview')),
                    Tab(text: tr('scripts')),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _OverviewTab(
              server: s,
              extraVars: {...s.vars.extra, ...?_fetchedExtraVars},
            ),
            _ScriptsTab(
              resources: _fetchedResources ?? s.resources,
              controller: _scriptCtrl,
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final GameServer server;
  const _Banner({required this.server});

  @override
  Widget build(BuildContext context) {
    final banner = server.vars.bannerDetail;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (banner != null)
          Image.network(
            banner,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(color: kSurface),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kSurface, kBg],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kBg.withValues(alpha: 0.10), kBg.withValues(alpha: 0.85)],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: kBg.withValues(alpha: 0.85),
          child: tabBar,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

class _OverviewTab extends StatelessWidget {
  final GameServer server;
  final Map<String, String> extraVars;
  const _OverviewTab({required this.server, required this.extraVars});

  @override
  Widget build(BuildContext context) {
    final s = server;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (s.vars.projectDesc != null) ...[
          GlassPanel(
            child: Text(
              s.vars.projectDesc!,
              style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75), height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
        ],
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statRow(tr('gametype'), s.gametype.isEmpty ? '—' : s.gametype),
              _divider(),
              _statRow(tr('map'), s.mapname.isEmpty ? '—' : s.mapname),
              _divider(),
              _statRow(tr('players'), '${fmtNum(s.clients)} / ${fmtNum(s.svMaxclients)}'),
              _divider(),
              _statRow(tr('boost'), '${s.upvotePower}'),
              _divider(),
              _statRow(tr('onesync'), s.vars.onesyncEnabled ? tr('active') : tr('inactive')),
              if (s.vars.enforceGameBuild != null) ...[
                _divider(),
                _statRow(tr('build'), s.vars.enforceGameBuild!),
              ],
              if (s.vars.locale != null) ...[
                _divider(),
                _statRow(tr('language'), s.vars.locale!),
              ],
            ],
          ),
        ),
        if (s.vars.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('tags').toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: kFgAlpha(0.4))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: s.vars.tags.map((t) => Pill(text: t)).toList(),
                ),
              ],
            ),
          ),
        ],
        if (extraVars.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in extraVars.entries) ...[
                  if (entry.key != extraVars.entries.first.key) _divider(),
                  _infoRow(entry.key, entry.value),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.5))),
          ),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // Custom operator-set fields (e.g. "Website", "Discord") can be
  // arbitrarily long, so label and value stack instead of sharing a row.
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: kFgAlpha(0.45))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: kFgAlpha(0.06));
}

class _ScriptsTab extends StatelessWidget {
  final List<String> resources;
  final TextEditingController controller;
  const _ScriptsTab({required this.resources, required this.controller});

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim().toLowerCase();
    final filtered = resources
        .where((r) => query.isEmpty || r.toLowerCase().contains(query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search, size: 16, color: kFgAlpha(0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: tr('filterScripts'),
                    ),
                  ),
                ),
                Text('${filtered.length}/${resources.length}', style: TextStyle(fontSize: 11, color: kFgAlpha(0.4))),
              ],
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(tr('noScriptsFound'), style: TextStyle(color: kFgAlpha(0.4), fontSize: 13)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    return GlassPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          Icon(Icons.extension_outlined, size: 15, color: kFgAlpha(0.4)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(filtered[index], style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding
// ---------------------------------------------------------------------------

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;

  void _selectLanguage(String lang) {
    AppState.I.setLanguage(lang);
    setState(() {});
  }

  void _selectTheme(String mode) {
    AppState.I.setThemeMode(mode);
    setState(() {});
  }

  void _onContinue() {
    if (_step == 0) {
      setState(() => _step = 1);
    } else {
      AppState.I.completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.dns, size: 46, color: kAccent),
              const SizedBox(height: 18),
              Text(
                tr('onboardingWelcome'),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _step == 0 ? tr('onboardingLanguage') : tr('onboardingTheme'),
                style: TextStyle(fontSize: 14, color: kFgAlpha(0.55)),
              ),
              const SizedBox(height: 28),
              if (_step == 0) _buildLanguageStep() else _buildThemeStep(),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: SoundInkWell(
                  borderRadius: BorderRadius.circular(kRadius),
                  onTap: _onContinue,
                  child: GlassPanel(
                    opacity: 0.14,
                    borderOpacity: 0.4,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        _step == 0 ? tr('continueLabel') : tr('getStarted'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageStep() {
    final codes = kLanguageNames.keys.toList();
    return Column(
      children: [
        for (var i = 0; i < codes.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _optionTile('${kLanguageFlags[codes[i]]} ${kLanguageNames[codes[i]]}', AppState.I.language == codes[i], () => _selectLanguage(codes[i])),
        ],
      ],
    );
  }

  Widget _buildThemeStep() {
    return Column(
      children: kThemeModes.map((mode) {
        final label = tr(themeModeLabelKey(mode));
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _optionTile(
            label,
            AppState.I.themeMode == mode,
            () => _selectTheme(mode),
            icon: themeModeIcon(mode),
          ),
        );
      }).toList(),
    );
  }

  Widget _optionTile(String label, bool active, VoidCallback onTap, {IconData? icon}) {
    return SoundInkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: GlassPanel(
        opacity: active ? 0.14 : 0.05,
        borderOpacity: active ? 0.5 : 0.10,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: kFgAlpha(0.85)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            if (active) Icon(Icons.check_circle, size: 18, color: kAccent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main menu
// ---------------------------------------------------------------------------

// Best-effort mapping from the app's UI language to a server region code
// (matching GameServer.countryGroup) for the "top servers near you"
// section. English has no single unambiguous country, so it falls back
// to a global top 3 instead of guessing wrong.
String? regionForLanguage(String lang) {
  switch (lang) {
    case 'de':
      return 'DE';
    case 'fr':
      return 'FR';
    case 'es':
      return 'ES';
    case 'pl':
      return 'PL';
    default:
      return null;
  }
}

class TutorialStep {
  final GlobalKey targetKey;
  final String titleKey;
  final String descKey;
  const TutorialStep({required this.targetKey, required this.titleKey, required this.descKey});
}

class _SpotlightPainter extends CustomPainter {
  final Rect? rect;
  const _SpotlightPainter({this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.72);
    if (rect == null) {
      canvas.drawPath(overlay, paint);
      return;
    }
    final hole = Path()..addRRect(RRect.fromRectAndRadius(rect!.inflate(6), const Radius.circular(16)));
    canvas.drawPath(Path.combine(PathOperation.difference, overlay, hole), paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.rect != rect;
}

// First-run coach-mark overlay: sequentially spotlights the given target
// widgets (via their GlobalKeys) with a caption + Next/Skip controls. No
// external tutorial package - just Overlay + CustomPaint, since the app
// only needs 3 fixed steps on the main menu.
class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onFinished;
  const TutorialOverlay({super.key, required this.steps, required this.onFinished});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _index = 0;

  Rect? _targetRect() {
    final ctx = widget.steps[_index].targetKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final pos = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(pos.dx, pos.dy, box.size.width, box.size.height);
  }

  void _advance() {
    SoundService.tap();
    if (_index >= widget.steps.length - 1) {
      widget.onFinished();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _targetRect();
    final step = widget.steps[_index];
    final screen = MediaQuery.of(context).size;
    final captionTop = rect == null
        ? screen.height * 0.4
        : (rect.bottom + 150 < screen.height ? rect.bottom + 16 : (rect.top - 140).clamp(16.0, screen.height - 160));

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _advance,
              child: CustomPaint(painter: _SpotlightPainter(rect: rect), child: const SizedBox.expand()),
            ),
          ),
          if (rect != null)
            Positioned(
              left: rect.left - 6,
              top: rect.top - 6,
              child: IgnorePointer(
                child: Container(
                  width: rect.width + 12,
                  height: rect.height + 12,
                  decoration: BoxDecoration(
                    border: Border.all(color: kAccent, width: 2),
                    borderRadius: BorderRadius.circular(kRadius + 4),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            top: captionTop,
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(step.titleKey), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(tr(step.descKey), style: TextStyle(fontSize: 13, color: kFgAlpha(0.75))),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SoundInkWell(
                        borderRadius: BorderRadius.circular(kRadius),
                        onTap: widget.onFinished,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Text(tr('tutorialSkip'), style: TextStyle(fontSize: 13, color: kFgAlpha(0.5))),
                        ),
                      ),
                      const Spacer(),
                      Text('${_index + 1}/${widget.steps.length}', style: TextStyle(fontSize: 12, color: kFgAlpha(0.4))),
                      const SizedBox(width: 12),
                      SoundInkWell(
                        borderRadius: BorderRadius.circular(kRadius),
                        onTap: _advance,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(kRadius)),
                          child: Text(
                            _index >= widget.steps.length - 1 ? tr('tutorialDone') : tr('tutorialNext'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  final _serverListKey = GlobalKey();
  final _favoritesKey = GlobalKey();
  final _historyKey = GlobalKey();
  final _topRegionKey = GlobalKey();
  final _settingsKey = GlobalKey();
  OverlayEntry? _tutorialEntry;

  @override
  void initState() {
    super.initState();
    if (!AppState.I.tutorialSeen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showTutorial());
    }
  }

  void _showTutorial() {
    if (!mounted || _tutorialEntry != null) return;
    final steps = [
      TutorialStep(targetKey: _serverListKey, titleKey: 'tutorialServerListTitle', descKey: 'tutorialServerListDesc'),
      TutorialStep(targetKey: _favoritesKey, titleKey: 'tutorialFavoritesTitle', descKey: 'tutorialFavoritesDesc'),
      TutorialStep(targetKey: _historyKey, titleKey: 'searchHistoryTitle', descKey: 'tutorialSearchHistoryDesc'),
      TutorialStep(targetKey: _topRegionKey, titleKey: 'topRegionTitle', descKey: 'tutorialTopRegionDesc'),
      TutorialStep(targetKey: _settingsKey, titleKey: 'tutorialSettingsTitle', descKey: 'tutorialSettingsDesc'),
    ];
    _tutorialEntry = OverlayEntry(
      builder: (_) => TutorialOverlay(steps: steps, onFinished: _dismissTutorial),
    );
    Overlay.of(context).insert(_tutorialEntry!);
  }

  void _dismissTutorial() {
    _tutorialEntry?.remove();
    _tutorialEntry = null;
    AppState.I.completeTutorial();
  }

  @override
  void dispose() {
    _tutorialEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: kBg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('appName'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(
                            key: _serverListKey,
                            child: _MenuCard(
                              icon: Icons.dns,
                              title: tr('serverList'),
                              subtitle: tr('serverListSubtitle'),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ServerListPage()),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          KeyedSubtree(
                            key: _favoritesKey,
                            child: _MenuCard(
                              icon: Icons.star,
                              title: tr('favorites'),
                              subtitle: tr('favoritesSubtitle'),
                              badge: AppState.I.favorites.isEmpty ? null : '${AppState.I.favorites.length}',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const FavoritesPage()),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          KeyedSubtree(
                            key: _historyKey,
                            child: _MenuCard(
                              icon: Icons.history,
                              title: tr('searchHistoryTitle'),
                              subtitle: tr('searchHistorySubtitle'),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SearchHistoryPage()),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          KeyedSubtree(
                            key: _topRegionKey,
                            child: _MenuCard(
                              icon: Icons.public,
                              title: tr('topRegionTitle'),
                              subtitle: tr('topRegionSubtitle'),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const TopRegionServersPage()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: KeyedSubtree(
                      key: _settingsKey,
                      child: SoundInkWell(
                        borderRadius: BorderRadius.circular(kRadius),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsPage()),
                        ),
                        child: GlassPanel(
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.settings_outlined, size: 22, color: kFgAlpha(0.85)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SearchHistoryPage extends StatefulWidget {
  const SearchHistoryPage({super.key});

  @override
  State<SearchHistoryPage> createState() => _SearchHistoryPageState();
}

class _SearchHistoryPageState extends State<SearchHistoryPage> {
  Future<void> _clear() async {
    await AppState.I.clearSearchHistory();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final history = AppState.I.searchHistory;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: kFg),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('searchHistoryTitle'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                    ),
                  ),
                  if (history.isNotEmpty)
                    SoundInkWell(
                      borderRadius: BorderRadius.circular(kRadius),
                      onTap: _clear,
                      child: GlassPanel(
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Text(tr('noSearchHistory'), style: TextStyle(color: kFgAlpha(0.4), fontSize: 13)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final term = history[index];
                        return SoundInkWell(
                          borderRadius: BorderRadius.circular(kRadius),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ServerListPage(initialSearch: term)),
                          ),
                          child: GlassPanel(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.history, size: 16, color: kFgAlpha(0.5)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(term, style: const TextStyle(fontSize: 13.5))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopRegionServersPage extends StatefulWidget {
  const TopRegionServersPage({super.key});

  @override
  State<TopRegionServersPage> createState() => _TopRegionServersPageState();
}

class _TopRegionServersPageState extends State<TopRegionServersPage> {
  bool _loading = true;
  String? _error;
  List<GameServer> _servers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await ApiService.fetchTopServers();
      final region = regionForLanguage(AppState.I.language);
      final regional = region == null ? servers : servers.where((s) => s.countryGroup == region).toList();
      final pool = regional.isEmpty ? servers : regional;
      pool.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
      if (!mounted) return;
      setState(() {
        _servers = pool.take(10).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: kFg),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('topRegionTitle'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.4));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: kFgAlpha(0.35), size: 32),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: kFgAlpha(0.6), fontSize: 13)),
              const SizedBox(height: 14),
              SoundInkWell(
                onTap: _load,
                child: GlassPanel(
                  opacity: 0.10,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Text(tr('retry'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kAccent,
      backgroundColor: kSurface,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
        itemCount: _servers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => ServerTile(server: _servers[index]),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return SoundInkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: GlassPanel(
        blur: 24,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadius),
                color: kAccent.withValues(alpha: 0.12),
                border: Border.all(color: kAccent.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, size: 26, color: kAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.5))),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius),
                  color: kAccent.withValues(alpha: 0.14),
                ),
                child: Text(badge!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kAccent)),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, color: kFgAlpha(0.35)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  String? _error;
  List<GameServer> _favoriteServers = [];
  final Set<String> _selectedCodes = {};
  // Holds the in-progress dragged slider value per server code, so the UI
  // updates instantly without writing to prefs on every drag frame; only
  // committed to AppState (and thus persisted) on drag end.
  final Map<String, int> _draftThreshold = {};

  int _thresholdFor(String code) => _draftThreshold[code] ?? AppState.I.favoriteNotifyThreshold(code);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toggleSelect(String code) {
    setState(() {
      if (!_selectedCodes.add(code)) _selectedCodes.remove(code);
    });
  }

  Future<void> _deleteSelected() async {
    final codes = _selectedCodes.toList();
    for (final code in codes) {
      await AppState.I.toggleFavorite(code);
    }
    setState(() {
      _favoriteServers.removeWhere((s) => codes.contains(s.code));
      _selectedCodes.clear();
    });
    WidgetService.pushFavorites(_favoriteServers);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await ApiService.fetchTopServers();
      final favorites = AppState.I.favorites;
      final matched = servers.where((s) => favorites.contains(s.code)).toList();
      matched.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
      if (!mounted) return;
      setState(() {
        _favoriteServers = matched;
        _loading = false;
      });
      WidgetService.pushFavorites(_favoriteServers);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: _selectedCodes.isNotEmpty
                        ? () => setState(() => _selectedCodes.clear())
                        : () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: Icon(_selectedCodes.isNotEmpty ? Icons.close : Icons.arrow_back, size: 18, color: kFg),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedCodes.isNotEmpty ? '${_selectedCodes.length}' : tr('favorites'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                    ),
                  ),
                  if (_selectedCodes.isNotEmpty)
                    SoundInkWell(
                      borderRadius: BorderRadius.circular(kRadius),
                      onTap: _deleteSelected,
                      child: GlassPanel(
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (AppState.I.favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            tr('noFavoritesYet'),
            textAlign: TextAlign.center,
            style: TextStyle(color: kFgAlpha(0.4), fontSize: 13),
          ),
        ),
      );
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.4));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: kFgAlpha(0.35), size: 32),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: kFgAlpha(0.6), fontSize: 13)),
              const SizedBox(height: 14),
              SoundInkWell(
                onTap: _load,
                child: GlassPanel(
                  opacity: 0.10,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Text(tr('retry'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_favoriteServers.isEmpty) {
      return Center(
        child: Text(tr('noFavoritesYet'), textAlign: TextAlign.center, style: TextStyle(color: kFgAlpha(0.4), fontSize: 13)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kAccent,
      backgroundColor: kSurface,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
        itemCount: _favoriteServers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final s = _favoriteServers[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ServerTile(
                server: s,
                selectionMode: _selectedCodes.isNotEmpty,
                selected: _selectedCodes.contains(s.code),
                onLongPress: () => _toggleSelect(s.code),
                onSelectTap: () => _toggleSelect(s.code),
              ),
              if (_selectedCodes.isEmpty) _buildNotifyControl(s.code),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotifyControl(String code) {
    final enabled = AppState.I.isFavoriteNotifyEnabled(code);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GlassPanel(
        opacity: 0.06,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_outlined, size: 15, color: kFgAlpha(0.6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('favoriteNotifyEnable'), style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75))),
                ),
                Switch(
                  value: enabled,
                  activeColor: kAccent,
                  onChanged: (v) async {
                    SoundService.tap();
                    await AppState.I.setFavoriteNotifyEnabled(code, v);
                    setState(() => _draftThreshold.remove(code));
                  },
                ),
              ],
            ),
            if (enabled) ...[
              const SizedBox(height: 2),
              Text(tr('favoriteNotifyThresholdLabel'), style: TextStyle(fontSize: 11.5, color: kFgAlpha(0.5))),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: kAccent,
                        inactiveTrackColor: kFgAlpha(0.15),
                        thumbColor: kAccent,
                        overlayColor: kAccent.withValues(alpha: 0.15),
                      ),
                      child: Slider(
                        value: _thresholdFor(code).toDouble().clamp(1, 2000),
                        min: 1,
                        max: 2000,
                        onChanged: (v) => setState(() => _draftThreshold[code] = v.round()),
                        onChangeEnd: (v) async {
                          await AppState.I.setFavoriteNotifyThreshold(code, v.round());
                          setState(() => _draftThreshold.remove(code));
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_thresholdFor(code)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.arrow_back, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('settings'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _sectionLabel(tr('appLanguage')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kLanguageNames.entries.map((entry) {
                        return Pill(
                          text: '${kLanguageFlags[entry.key]} ${entry.value}',
                          active: AppState.I.language == entry.key,
                          onTap: () {
                            AppState.I.setLanguage(entry.key);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('colorScheme')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Column(
                      children: kThemeModes.map((mode) {
                        final label = tr(themeModeLabelKey(mode));
                        final active = AppState.I.themeMode == mode;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: SoundInkWell(
                            onTap: () {
                              AppState.I.setThemeMode(mode);
                              setState(() {});
                            },
                            child: Row(
                              children: [
                                Icon(themeModeIcon(mode), size: 19, color: kFgAlpha(0.85)),
                                const SizedBox(width: 12),
                                Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
                                if (active) Icon(Icons.check_circle, size: 17, color: kAccent),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('textSize')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Row(
                      children: [
                        Text('a', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kFgAlpha(0.5))),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: kAccent,
                              inactiveTrackColor: kFgAlpha(0.15),
                              thumbColor: kAccent,
                              overlayColor: kAccent.withValues(alpha: 0.15),
                            ),
                            child: Slider(
                              value: AppState.I.textScale,
                              min: 0.8,
                              max: 1.4,
                              onChanged: (v) {
                                AppState.I.setTextScale(v);
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                        Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kFgAlpha(0.8))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('highContrast')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(tr('highContrastDesc'), style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75))),
                        ),
                        Switch(
                          value: AppState.I.highContrast,
                          activeColor: kAccent,
                          onChanged: (v) {
                            AppState.I.setHighContrast(v);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('notificationSound')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            for (final sound in const ['default', 'chime', 'bell']) ...[
                              Expanded(
                                child: SoundInkWell(
                                  borderRadius: BorderRadius.circular(kRadius),
                                  onTap: () {
                                    AppState.I.setNotificationSound(sound);
                                    SoundService.previewNotificationSound(sound);
                                    setState(() {});
                                  },
                                  child: GlassPanel(
                                    opacity: AppState.I.notificationSound == sound ? 0.22 : 0.08,
                                    borderOpacity: AppState.I.notificationSound == sound ? 0.6 : 0.2,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Center(
                                      child: Text(
                                        tr('sound${sound[0].toUpperCase()}${sound.substring(1)}'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: AppState.I.notificationSound == sound ? FontWeight.w700 : FontWeight.w500,
                                          color: AppState.I.notificationSound == sound ? kAccent : kFgAlpha(0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (sound != 'bell') const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        Divider(height: 20, color: kFgAlpha(0.06)),
                        Row(
                          children: [
                            Expanded(
                              child: Text(tr('vibrationDesc'), style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75))),
                            ),
                            Switch(
                              value: AppState.I.notificationVibration,
                              activeColor: kAccent,
                              onChanged: (v) {
                                SoundService.tap();
                                AppState.I.setNotificationVibration(v);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('autoRefresh')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('autoRefreshDesc'), style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.5))),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stepperButton(Icons.remove, () {
                              final v = (AppState.I.refreshIntervalMinutes - 5).clamp(5, 30);
                              AppState.I.setRefreshIntervalMinutes(v);
                              setState(() {});
                            }),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '${AppState.I.refreshIntervalMinutes} min',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            _stepperButton(Icons.add, () {
                              final v = (AppState.I.refreshIntervalMinutes + 5).clamp(5, 30);
                              AppState.I.setRefreshIntervalMinutes(v);
                              setState(() {});
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('uiSounds')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(tr('uiSoundsDesc'), style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75))),
                        ),
                        Switch(
                          value: AppState.I.uiSoundsEnabled,
                          activeColor: kAccent,
                          onChanged: (v) {
                            AppState.I.setUiSoundsEnabled(v);
                            if (v) SoundService.tap(); // audible confirmation when turning sounds on
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('haptics')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(tr('hapticsDesc'), style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75))),
                        ),
                        Switch(
                          value: AppState.I.hapticsEnabled,
                          activeColor: kAccent,
                          onChanged: (v) {
                            AppState.I.setHapticsEnabled(v);
                            if (v) HapticFeedback.selectionClick();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: _clearCache,
                    child: GlassPanel(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(tr('clearCache'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          Icon(Icons.cleaning_services_outlined, color: kFgAlpha(0.5), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    ),
                    child: GlassPanel(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(tr('about'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          Icon(Icons.chevron_right, color: kFgAlpha(0.35)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearCache() {
    SoundService.tap();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        content: Text(tr('cacheCleared'), style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return SoundInkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: GlassPanel(
        opacity: 0.08,
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 18, color: kAccent),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: kFgAlpha(0.4),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  SoundInkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, size: 18, color: kFg),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('about'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                children: [
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.dns, size: 46, color: kAccent),
                        const SizedBox(height: 12),
                        Text(tr('appName'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${tr('aboutVersion')} $kAppVersion',
                          style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.5)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  GlassPanel(
                    child: Text(
                      tr('aboutCredits'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75), height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GlassPanel(
                    child: Text(
                      tr('aboutContact'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: kFgAlpha(0.75), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
