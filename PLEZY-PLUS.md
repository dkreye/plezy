# Plezy+

Persönliche Variante von [Plezy](https://github.com/edde746/plezy) mit Erweiterungen für Editionen und Sammlungen. Sie wird neben dem originalen Plezy installiert.

| | |
|---|---|
| Basis | `edde746/plezy` Release `2.26.0`, Commit `671a0d7` (09.11.2026), Version 2.26.0+160 |
| Flutter | 3.47.1 (wie im offiziellen Build-Workflow) |
| Branch | `plezy-plus` |

## Änderungen

Der Branch besteht aus zwei Commits auf der Basis:

1. **Build und CI** – Workflow „Plezy+ APK“ und diese Doku
2. **Quellcode** – Editionen-, Sammlungs- und Crew-Reihen, Filmografie über alle Rollen, Versionsnamen, Beschriftungen in den Dateiinformationen, Reihenabstand im Raster, Edition und Bewertungen, eigene App-ID

### Detailseite: Editionen-Reihe
- Alle Editionen eines Films (gleiche guid in derselben Bibliothek), Standard zuerst als `<Standard>`, die übrigen mit ihrem Editionsnamen.
- Erscheint nur, wenn es mehr als eine Edition gibt.
- Auf TV direkt unter dem Kopfbereich, vor der Besetzung.

### Detailseite: eine Reihe je Sammlung
- Jede manuelle Sammlung des Eintrags bekommt eine eigene Reihe. Die kleinste kommt zuerst (nach geladener Größe), bei gleicher Größe der längere Name.
- Jeder Sammlung folgen die gleichnamigen Sammlungen aus anderen Bibliotheken, Überschrift `Titel <Bibliothek>`.
- Ausgeblendet wird eine Sammlung, die nur den Eintrag selbst oder genau die Editionen des Films enthält.
- Die Sammlungsreihen, die der Plex-Server selbst liefert, entfallen, sie wären doppelt.

### Detailseite: Crew
- Nach der Besetzung eine Reihe „Crew“ (TV, Handy, Desktop) mit Regie, Drehbuch und Produktion: Foto, Name und Aufgabe, je Person einmal mit allen Aufgaben („Regie, Drehbuch“). Auswählen öffnet die Filmografie.
- Die Info-Zeilen am Seitenende (Studio, Regie, Altersfreigabe) entfallen.

### Filmografie
- Die Filmografie einer Person (aus Besetzung oder Crew) zeigt alle ihre Einträge, egal in welcher Rolle: Darsteller, Regie, Drehbuch, Produktion. Plex führt je Rolle ein eigenes Tag; Plezy+ sucht die übrigen Tags derselben Person und führt deren Filme zusammen, jeden Film einmal. Sortiert wird immer nach Jahr, neueste zuerst, innerhalb eines Jahres alphabetisch (auch bei nur einer Rolle).
- Darsteller und Regie findet die Suche über die plex.tv-Personen-ID (`tagKey`), Drehbuch und Produktion die Listen `/library/sections/<id>/writer` bzw. `/producer` über gleichen Namen und gleiches Foto (diese Listen tragen keinen `tagKey`). Die Listen werden 30 Minuten zwischengespeichert.
- Schlägt das fehl, bleibt es bei den Einträgen der einen Rolle.

### Personen aus .nfo-Dateien
- Plex legt Personen aus lokalen .nfo-Dateien als eigene Tags ohne Foto und ohne plex.tv-ID an. Nur für diese Personen sucht Plezy+ ein Foto; von den Agenten erkannte Personen ohne Foto (mit plex.tv-ID) bleiben ohne. Die Suche beginnt erst, wenn die Reihen der Detailseite geladen sind, damit sie das Öffnen nicht bremst. Plezy+ übernimmt beides vom gleichnamigen, von den Metadaten-Agenten erkannten Tag: das Foto in Besetzung und Crew, die plex.tv-ID für die Biografie auf der Personenseite.
- Plex führt Personen je Bibliothek, und verschiedene Personen können denselben Namen tragen (z. B. zwei „Tom Holland“ mit verschiedener plex.tv-ID). Gewählt wird die plex.tv-ID, die unter den gleichnamigen Einträgen derselben Bibliothek eindeutig ist; sonst die einzige mit Foto; sonst die einzige überhaupt. Bleibt es mehrdeutig, bleibt das Foto leer.
- Auch Filmografie und Biografie einer .nfo-Person folgen dieser Zuordnung.
- Drehbuch- und Produktionslisten nur für Personen, die ausschließlich dort vorkommen. Die Fotos erscheinen schrittweise, sobald sie gefunden sind, und werden je Name für die Sitzung gemerkt.

### Raster
- In allen Medienrastern mit Beschriftung liegen 8 Punkte mehr Abstand zwischen den Reihen als zwischen den Spalten. So steht die Beschriftung sichtbar näher an ihrem eigenen Bild als an der nächsten Reihe. Raster ohne Beschriftung (Vollbild-Karten) bleiben unverändert.

### Edition
- In der Detailansicht ganz am Ende der Infozeile, nach den Bewertungen: in der TV-Detailzeile und im Detail-Kopf (Mobil/Desktop, dort vor dem Knopf für die eigene Bewertung). Bei Platzmangel wird sie zuletzt ausgeblendet.
- Zusätzlich in Home-Hero und Ordneransicht.

### Bewertungen
- Externe Bewertungen wie in den Plex-Apps nur aus dem `Rating[]`-Array des Eintrags, in Server-Reihenfolge. Das skalare `rating`/`audienceRating`-Paar kann von Tools wie Kometa überschrieben sein (fremder Wert unter dem Symbol der Originalquelle) und dient nur noch als Ersatz.
- Die eigene Bewertung steht in TV-Detailzeile und TV-Kurzinfo als eigener Eintrag vor den externen: gelber Stern, Zehner-Skala.
- Die TV-Kurzinfo (Startseite, Bibliotheken) lädt dafür nach kurzer Verweildauer den vollständigen Eintrag; die Ergebnisse werden je Eintrag zwischengespeichert.
- Auch sonst steht die eigene Bewertung überall auf der Zehner-Skala mit gelbem Stern (Bewertungs-Schaltfläche, Episodenkarten). Startseiten-Karussell, Kartenliste und Ordneransicht zeigen statt der namenlosen Listen-Bewertung die eigene; Katalogeinträge (Trakt usw.) behalten die ihrer Quelle.

### Versionen
- Die Versionsauswahl (Wiedergabe, Download, Watch Together) zeigt statt der technischen Angaben den Versionsnamen aus dem Dateinamen: den Teil nach dem letzten „ - “ ohne Endung („Buddy Buddy (1981) - 528p.mkv“ → „528p“, auch Sprachkürzel wie „en“).
- Nur bei mehreren Versionen und nur, wenn jede Version einen eigenen, unterschiedlichen Namen ergibt; sonst bleiben die technischen Angaben. Benutzer mit eingeschränktem Zugriff bekommen von Plex keine Dateipfade und sehen ebenfalls die Technik.

### Dateiinformationen
- Die Dateiinformationen zeigen über den Versionen die Beschriftungen des Eintrags (Plex-`Label`).

### Android
- App-ID `biz.kreye.plezy`, Name „Plezy+“. FileProvider- und Artwork-Provider-Authorities sind ebenfalls umbenannt, sonst scheitert die Installation neben dem Original.
- Fire TV Sticks laufen meist mit 32-Bit-System und brauchen die APK `armeabi-v7a`.

### Build
- Workflow `.github/workflows/plezy-plus.yml` baut die APKs `arm64-v8a` und `armeabi-v7a`.
- Der Build wird bei Download-Fehlern bis zu dreimal wiederholt, der Download der FFmpeg-Header (von GitHub) ebenfalls.

## APK bauen

Der Workflow startet bei jedem Push auf `plezy-plus`, oder von Hand unter *Actions → Plezy+ APK → Run workflow*. Nach etwa 25 Minuten liegt im Lauf das Artefakt `plezy-plus-apk` (ZIP mit beiden APKs).

Signiert wird mit diesen Repository-Secrets (*Settings → Secrets and variables → Actions*):

| Secret | Inhalt |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Keystore, Base64-kodiert in einer Zeile |
| `ANDROID_STORE_PASSWORD` | Keystore-Passwort |
| `ANDROID_KEY_PASSWORD` | Schlüssel-Passwort |
| `ANDROID_KEY_ALIAS` | `plezyplus` |

Ohne diese Secrets bricht der Build ab, denn eine unsignierte APK ließe sich nicht installieren. Den Keystore niemals ins Repository einchecken. Er gehört an einen sicheren Ort außerhalb davon, denn Updates müssen mit demselben Schlüssel signiert sein.

## Installation auf der Shield

Voraussetzung: *Entwickleroptionen → Netzwerk-Debugging* ist eingeschaltet.

```
adb connect <IP-der-Shield>:5555
adb shell getprop ro.product.cpu.abilist    # erste Angabe = passende APK
adb install plezy-plus-arm64-v8a.apk        # Erstinstallation
adb install -r plezy-plus-arm64-v8a.apk     # Update, Daten bleiben erhalten
```

## Auf eine neue Plezy-Version heben

```
git remote add upstream https://github.com/edde746/plezy.git   # einmalig
git fetch upstream
git checkout plezy-plus
git rebase upstream/main
git push --force-with-lease origin plezy-plus
```

Bei Konflikten betreffen sie fast immer `lib/services/plex_client.dart` (`fetchRelatedHubs`) oder `lib/screens/media_detail_screen.dart`. Nach dem Rebase die Basis-Angaben oben anpassen.
