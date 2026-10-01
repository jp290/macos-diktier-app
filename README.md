# macOS-Diktier-App

Eine native, lokale Diktier-App für Apple-Silicon-Macs mit macOS 14 oder neuer. Für ein MacBook Air mit 16 GB RAM vorgesehen. Deutsch und Englisch werden standardmäßig automatisch erkannt, einschließlich Sprachwechseln in derselben Aufnahme.

## Benutzen

1. `macOS-Diktier-App.zip` aus dem [aktuellen Release](https://github.com/jp290/macos-diktier-app/releases/latest) laden, entpacken, `macOS-Diktier-App.app` nach `Programme` kopieren und öffnen. Die App läuft nur in der Menüleiste (Wellenform-Symbol) und hat kein Dock-Symbol.
2. In **Einstellungen** das Modell **Qwen3-ASR 1.7B · Hohe Qualität** herunterladen. Der einmalige Download ist ungefähr 2,5 GB groß. Danach arbeitet die Erkennung offline.
3. **Mikrofon** und **Bedienungshilfen** freigeben. Die zweite Berechtigung ermöglicht das Einfügen am Cursor.
4. In einer anderen App den Cursor in ein Textfeld setzen.
5. **Command (⌘) zweimal kurz drücken**, sprechen und zum Stoppen wieder zweimal drücken. Auf einer Windows-Tastatur ist das normalerweise die **Windows-Taste**. Währenddessen zeigt eine kleine schwebende Anzeige den Aufnahmezustand.

### Signatur und Gatekeeper

Der aktuelle Download ist **ad hoc signiert** (ohne Apple-Developer-ID) und **nicht von Apple notarisiert**. Falls macOS den ersten Start blockiert, öffne **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen** für diese App. Apple beschreibt den Ablauf unter [Apps sicher auf dem Mac öffnen](https://support.apple.com/de-de/102445).

Weil eine Ad-hoc-Signatur an den genauen Code-Hash gebunden ist, betrachtet macOS jede neue Version als andere App. Nach einem Update ist die Freigabe für Bedienungshilfen deshalb in der Regel erneut nötig, auch wenn der Schalter noch eingeschaltet aussieht: App beenden, den bisherigen Eintrag unter **Datenschutz & Sicherheit → Bedienungshilfen** entfernen, die aktuelle App aus `Programme` wieder hinzufügen und einschalten. Danach die App neu starten.

Das Doppeltippen benötigt die Freigabe für Bedienungshilfen, damit es auch in anderen Apps funktioniert. Beide Tastendrücke müssen kurz sein und die Taste muss dazwischen losgelassen werden. Andere Tasten, zusätzliche Modifikatoren, Mausklicks und App-Wechsel unterbrechen die Folge; Kombinationen wie Command+C lösen kein Diktat aus. In den App-Einstellungen bleiben alternativ **⌥ ⌘ Leertaste**, **⌃ ⌘ Leertaste** und **⌥ ⌘ D** verfügbar. Bereits gespeicherte Kurzbefehl-Einstellungen bleiben erhalten.

Unter **Einstellungen → Diktieren → Mikrofon** lässt sich das Aufnahmegerät nur für diese App auswählen. **Systemstandard** folgt der macOS-Auswahl. Die Wahl wird gespeichert; angeschlossene USB- und Bluetooth-Mikrofone erscheinen automatisch. Ist ein ausdrücklich gewähltes Mikrofon getrennt, meldet die App das vor der Aufnahme.

Die schwebende Anzeige ist 200 × 40 Punkte groß und zeigt Pegel, Aufnahmedauer und Stoppen/Abbrechen. Während der Erkennung erscheint ein kurzer Status. Sie übernimmt keinen Tastaturfokus, auch wenn ihre Tasten angeklickt werden.

Ein Diktat kann bis zu zwei Minuten dauern. Nach dem Stoppen folgt die Transkription und anschließend standardmäßig das Einfügen. Während der Verarbeitung kann abgebrochen werden. Der Text liegt auch im lokalen Verlauf und lässt sich kopieren, falls eine App das Einfügen nicht unterstützt. Wenn währenddessen die App oder ein erkanntes fokussiertes Feld gewechselt wird, bleibt der Text zum manuellen Kopieren erhalten. Für Programme ohne zugängliches Textfeld erfolgt das Einfügen nur, wenn dieselbe App noch im Vordergrund ist. Die ursprüngliche Zwischenablage wird nach dem Einfügen wiederhergestellt, sofern sie inzwischen nicht verändert wurde.

Qwen wird beim Aufnahmestart vorgewärmt und für aufeinanderfolgende Diktate im Speicher gehalten. Nach zwei Minuten ohne Verwendung oder beim Abbrechen wird die Engine beendet und der Speicher freigegeben. Beim ersten Diktat bleibt die Ladezeit abhängig vom Mac; nachfolgende Diktate sparen das erneute Laden. Die Erkennungsparameter und das Modell bleiben unverändert.

## Modelle und Sprache

| Modell | Download | Einsatz |
| --- | ---: | --- |
| Qwen3-ASR 1.7B, 8 Bit | 2,5 GB | Standard für hohe Qualität bei Deutsch und Englisch |
| Whisper Large v3 Turbo, Q5 | 574 MB | Mehrsprachige Alternative mit weniger Speicherbedarf |
| Whisper Small, Q5 | 190 MB | Kompakte Alternative mit geringerer Genauigkeit |

**Automatisch erkennen** ist die Voreinstellung. Deutsch und Englisch können auch fest ausgewählt werden. Eigennamen und Fachbegriffe lassen sich als Erkennungshilfe hinterlegen. „Neue Zeile“ und „Neuer Absatz“ werden optional als Umbrüche geschrieben. Die App übernimmt ansonsten die erkannten Worte ohne eine zusätzliche sprachliche Überarbeitung durch ein Textmodell.

Die Modellwahl stützt sich auf die [Qwen-Modellbeschreibung](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), die [MLX-Swift-Implementierung](https://github.com/Blaizzy/mlx-audio-swift) und einen [veröffentlichten Mac-Vergleich von Qwen und Whisper](https://whispernotes.app/blog/qwen3-asr-vs-whisper). Der Vergleich stammt vom Entwickler einer anderen Diktier-App und verwendet vorgelesene FLEURS-Aufnahmen. Das ersetzt keine Prüfung mit der eigenen Stimme. [Aktuelle Community-Erfahrungen](https://www.reddit.com/r/MacWhisper/comments/1wkpr78/macwhisper_151_is_out_with_realtime_meetings_and/) berichten auch von unterschiedlicher Geschwindigkeit auf älteren M1-Geräten.

## Umstieg von „Whisper Flow“

Die App hieß bis zur Umbenennung in Version 0.1.4 „Whisper Flow“. Bundle-ID (`de.local.whisperflow`), gespeicherte Einstellungen und der Datenordner `~/Library/Application Support/WhisperFlow/` bleiben bewusst unverändert: Bereits geladene Modelle, Verlauf, Mikrofon- und Kurzbefehl-Auswahl werden ohne Migration übernommen. Nach dem Umstieg die alte `Whisper Flow.app` beenden und löschen, damit nicht zwei Apps mit derselben Bundle-ID installiert sind, und die Bedienungshilfen-Freigabe wie oben beschrieben neu setzen.

## Lokale Daten

Modelle liegen in `~/Library/Application Support/WhisperFlow/Models/`. Der optionale Verlauf speichert höchstens 50 Diktate in `~/Library/Application Support/WhisperFlow/history.json`. Er kann in der App gelöscht oder ausgeschaltet werden. Erfolgreiche und abgebrochene Aufnahmen werden gelöscht. Bei einem Erkennungsfehler bleibt die aktuelle Aufnahme vorübergehend für einen erneuten Versuch erhalten und wird beim Verwerfen oder Beenden gelöscht.

Audio und Transkripte werden nicht hochgeladen. Netzwerkzugriffe dienen ausschließlich dem vom Nutzer gestarteten Modelldownload. Jeder Modellbestandteil wird anhand von Größe und SHA-256 geprüft.

Beim Modelldownload zeigt die App den laufenden Fortschritt in Prozent und geladenen MB/GB. Die anschließende Dateiprüfung bekommt eine eigene Aktivitätsanzeige; vollständig geladen bedeutet noch nicht einsatzbereit.

## Entwickeln

Benötigt werden ein Apple-Silicon-Mac, Xcode mit Swift 6.2 oder neuer und Metal-Toolchain, Python 3, ripgrep (`rg`) sowie CMake oder `uv`. Die erste Kompilierung der MLX-Abhängigkeiten kann auf einem M1 mehrere Minuten dauern.

```sh
swift test -j 4
scripts/build.sh
scripts/install.sh
```

Das Ergebnis liegt in `dist/macOS-Diktier-App.app` und `dist/macOS-Diktier-App.zip`. Die ZIP enthält die App und ihre Engines; die Sprachmodelle werden separat in der App heruntergeladen. Der lokale Build ist ad hoc signiert.

Für die Audiointegrationstests muss das Qwen-Modell verfügbar sein:

```sh
FLOW_MODEL_DIR="$HOME/Library/Application Support/WhisperFlow/Models/Qwen3-ASR-1.7B-8bit" scripts/verify.sh
```

Die Prüfung umfasst Unit-Tests, die App-Signatur sowie synthetische deutsche, englische und gemischte Audioaufnahmen in beiden Sprachrichtungen. Sie prüft auch die vollständige Konvertierungs- und Transkriptionspipeline und zwei aufeinanderfolgende Diktate mit derselben geladenen Engine. Die Ergebnisse in `.build/verification/` messen diese konkreten Beispiele, keine allgemeine Erkennungsqualität. Der Live-Mikrofonbetrieb, externe Geräte und das Einfügen in Fremdprogramme benötigen zusätzlich die macOS-Freigaben und einen manuellen Funktionstest auf dem Ziel-Mac.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE). Die verwendeten Komponenten haben eigene Lizenzen (MIT bzw. Apache 2.0), siehe [`Resources/THIRD_PARTY.md`](Resources/THIRD_PARTY.md); die vollständigen Lizenztexte liegen im App-Bundle unter `Contents/Resources/Licenses/`. Die Sprachmodelle werden von Hugging Face geladen und unterliegen den Lizenzen ihrer Anbieter.

Unabhängiges Projekt, ohne Verbindung zu Wispr Flow oder OpenAI.
