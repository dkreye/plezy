# Plezy+

Persönliche Variante von [Plezy](https://github.com/edde746/plezy) mit Erweiterungen für Editionen und Sammlungen. Sie wird neben dem originalen Plezy installiert.

| | |
|---|---|
| Basis | `edde746/plezy` `main`, Commit `80c562f` (04.11.2026), Version 2.25.0+159 |
| Flutter | 3.47.1 (wie im offiziellen Build-Workflow) |
| Branch | `plezy-plus` |

## Änderungen

Der Branch besteht aus zwei Commits auf der Basis:

1. **Quellcode** – Editionen- und Sammlungsreihen, Edition überall, eigene App-ID
2. **Build und CI** – Workflow „Plezy+ APK“ und diese Doku

### Detailseite: Editionen-Reihe
- Alle Editionen eines Films (gleiche guid in derselben Bibliothek), Standard zuerst als `<Standard>`, die übrigen mit ihrem Editionsnamen.
- Erscheint nur, wenn es mehr als eine Edition gibt.
- Auf TV direkt unter dem Kopfbereich, vor der Besetzung.

### Detailseite: eine Reihe je Sammlung
- Jede manuelle Sammlung des Eintrags bekommt eine eigene Reihe. Die kleinste kommt zuerst (nach geladener Größe), bei gleicher Größe der längere Name.
- Jeder Sammlung folgen die gleichnamigen Sammlungen aus anderen Bibliotheken, Überschrift `Titel <Bibliothek>`.
- Ausgeblendet wird eine Sammlung, die nur den Eintrag selbst oder genau die Editionen des Films enthält.
- Die Sammlungsreihen, die der Plex-Server selbst liefert, entfallen, sie wären doppelt.

### Edition
- In der Detailansicht ganz am Ende der Infozeile, nach den Bewertungen: in der TV-Detailzeile und im Detail-Kopf (Mobil/Desktop, dort vor dem Knopf für die eigene Bewertung). Bei Platzmangel wird sie zuletzt ausgeblendet.
- Zusätzlich in Home-Hero und Ordneransicht.

### Android
- App-ID `biz.kreye.plezy`, Name „Plezy+“. FileProvider- und Artwork-Provider-Authorities sind ebenfalls umbenannt, sonst scheitert die Installation neben dem Original.
- Fire TV Sticks laufen meist mit 32-Bit-System und brauchen die APK `armeabi-v7a`.

### Build
- Workflow `.github/workflows/plezy-plus.yml` baut die APKs `arm64-v8a` und `armeabi-v7a`.
- Der Build wird bei Download-Fehlern bis zu dreimal wiederholt, der Download der FFmpeg-Header (ffmpeg.org) ebenfalls.

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
