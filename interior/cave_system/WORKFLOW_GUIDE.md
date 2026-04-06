# Wie du eine Höhle baust — Schritt-für-Schritt Workflow

## Das Konzept in einem Satz

Du zeichnest die Höhlenform als **Polygon von oben** (wie einen Grundriss),
und das System generiert daraus automatisch Boden, Wände, Collision und Navigation.

---

## Schritt 1: Höhle planen (Papier/Skizze)

Bevor du Godot öffnest, skizziere kurz die Höhle von oben:

```
Beispiel Grundriss:

                    ┌─────────┐
                    │ Geheimer │
                    │  Raum    │
                    └────┬─────┘
                         │ (schmaler Gang)
    ┌────────────────────┴──────────┐
    │                               │
    │        HAUPTHALLE             │
    │     (Spotlight von oben)      │
    │                               │
    │   ~~~Bach~~~                  │
    │                               │
    ├──────┐               ┌────────┤
    │ Gang │               │  Gang  │
    └──┬───┘               └───┬────┘
       │                       │
   [Eingang]             [Weiter zu
    von der               Raum 2]
   Overworld
```

Notiere dir:
- Wo ist der Eingang?
- Wo sind Räume, wo Gänge?
- Wo fließt Wasser?
- Wo kommen Feinde hin?
- Was ist unerreichbar (Deko im Hintergrund)?

---

## Schritt 2: Szene erstellen

Erstelle `cave_01.tscn` mit dieser Struktur:

```
CaveSystem (Node3D) ← cave_system.gd
│
├── WorldEnvironment
│
├── CaveLightingRig (Node3D) ← cave_lighting_rig.gd
│
├── CaveRooms (Node3D)                          ← HIER BAUST DU DIE FORM
│   ├── MainHall (Node3D) ← cave_room_builder.gd
│   ├── SecretRoom (Node3D) ← cave_room_builder.gd
│   └── BackChamber (Node3D) ← cave_room_builder.gd
│
├── CaveCorridors (Node3D)                       ← GÄNGE ZWISCHEN RÄUMEN
│   ├── Corridor_Entrance (Node3D) ← cave_corridor_builder.gd
│   │   └── Path3D (Kurve zeichnen!)
│   ├── Corridor_ToSecret (Node3D) ← cave_corridor_builder.gd
│   │   └── Path3D
│   └── Corridor_ToBack (Node3D) ← cave_corridor_builder.gd
│       └── Path3D
│
├── CaveRockGeometry (Node3D) ← cave_rock_geometry.gd
├── CaveAutoRockPlacer (Node3D) ← cave_auto_rock_placer.gd
│
├── CaveWater (Node3D)
│   └── Stream_01 (Node3D) ← cave_stream.gd
│
├── CaveDecorations (Node3D)
├── CaveAtmosphere (Node3D) ← cave_atmosphere.gd
├── CaveLighting (Node3D) ← cave_lighting_manager.gd
├── CaveForeground (Node3D) ← cave_foreground.gd
│
├── SpawnPoints (Node3D)
│   └── entrance_main (Marker3D)
│
├── CaveExits (Node3D)
│   └── Exit_Main (Area3D) ← cave_exit.gd
│
└── Enemies (Node3D)
```

---

## Schritt 3: Räume formen (DAS ist der Kern)

### 3a. CaveRoomBuilder hinzufügen

1. Wähle `MainHall` (Node3D)
2. Hänge `cave_room_builder.gd` als Script an
3. Im Inspector siehst du jetzt `Room Polygon`

### 3b. Polygon bearbeiten

Das `Room Polygon` ist ein Array von Vector2-Punkten.
Jeder Punkt ist eine Ecke deines Raumes, gesehen von oben.

**X = Links/Rechts, Y = Vorne/Hinten (Z in 3D)**

Klicke auf `Room Polygon` → `PackedVector2Array` → Punkte hinzufügen:

```
Beispiel Haupthalle (unregelmäßiges Sechseck):

  room_polygon = [
      Vector2(-5, -4),     # Hinten links
      Vector2( 3, -4.5),   # Hinten rechts (leicht versetzt = organisch)
      Vector2( 5, -1),     # Rechte Seite oben
      Vector2( 4.5, 3),    # Rechte Seite unten
      Vector2(-1, 4),      # Vorne Mitte
      Vector2(-5, 2),      # Linke Seite unten
  ]
```

**TIPPS für organische Formen:**
- Keine rechten Winkel! Höhlen haben keine geraden Wände
- Versetze Punkte leicht (nicht -5/-5, sondern -5/-4.7)
- Mehr Punkte = mehr Detail an der Kontur
- 6-12 Punkte pro Raum reichen für natürliche Formen

### 3c. Was passiert automatisch

Wenn du die Punkte gesetzt hast und die Szene startest:

```
Room Polygon definiert        → CaveRoomBuilder generiert:
                                  ✓ Floor-Mesh (mit UV + Vertex Colors für Shader)
                                  ✓ Collision-Wände (unsichtbar, blockieren Spieler)
                                  ✓ Navigation-Mesh (für Feind-Pathfinding)

CaveAutoRockPlacer liest      → Platziert automatisch:
die Kanten des Polygons          ✓ 3D-Felsbrocken entlang aller Wände
                                  ✓ Gelegentliche Überhänge
                                  ✓ Deckenfelsen/Stalaktiten
                                  ✓ Geschichtete Gesteinsformationen
```

### 3d. Im Editor Vorschau

Da `CaveRoomBuilder` ein `@tool`-Script ist, siehst du im Editor
eine grüne Umriss-Linie deines Polygons. So kannst du die Form
visuell anpassen bevor du startest.

---

## Schritt 4: Gänge verbinden

### 4a. CaveCorridorBuilder hinzufügen

1. Erstelle unter `CaveCorridors` ein neues Node3D
2. Hänge `cave_corridor_builder.gd` an
3. Füge ein **Path3D** als Kind hinzu

### 4b. Pfad zeichnen

1. Wähle das Path3D
2. Im 3D-Viewport oben erscheint die **Path-Toolbar**
3. Klicke "Add Point" und setze Punkte:
   - Startpunkt: Am Rand von Raum A (wo der Gang beginnt)
   - Zwischenpunkte: Biegungen im Gang
   - Endpunkt: Am Rand von Raum B (wo der Gang endet)
4. Nutze die Tangenten-Handles für sanfte Kurven

```
Beispiel:

    Raum A                              Raum B
    ┌────┐                              ┌────┐
    │    ├── Punkt 1 ── Punkt 2 ── Punkt 3 ──┤    │
    │    │        (Path3D Kurve)        │    │
    └────┘                              └────┘
```

### 4c. Gang konfigurieren

Im Inspector des CaveCorridorBuilder:
- `corridor_width`: 2.0–3.0 (schmale Gänge = klaustrophobisch)
- `width_variation`: 0.2 (Gang wird stellenweise enger/weiter)
- `segments`: 15-20 (mehr = glattere Kurven)

### 4d. Wichtig: Überlappung

Die Gang-Enden müssen in die Raum-Polygone hineinragen (leicht überlappen).
Sonst gibt es eine Lücke im Boden zwischen Raum und Gang.

```
RICHTIG:                    FALSCH:

┌──────┐                    ┌──────┐
│ Raum ├═══Gang═══          │ Raum │  ═══Gang═══
│      ├═══════════         │      │  Lücke!
└──────┘                    └──────┘
  ↑ Gang ragt               ↑ Gang beginnt
    in den Raum                am Rand
    hinein
```

---

## Schritt 5: Felsen automatisch platzieren

### Der CaveAutoRockPlacer macht die Arbeit

1. Erstelle `CaveRockGeometry` (Node3D + cave_rock_geometry.gd)
2. Erstelle `CaveAutoRockPlacer` (Node3D + cave_auto_rock_placer.gd)
3. Im Inspector von CaveAutoRockPlacer:
   - `Rock Geometry`: Ziehe CaveRockGeometry hierher
   - `rocks_per_meter`: 3.0 (Dichte der Felsen)
   - `wall_depth`: 2.5 (Dicke der Felswand)
   - `enable_overhangs`: true
   - `enable_ceiling_rocks`: true

### Was passiert:

```
CaveRoomBuilder Raum-Polygon
         │
         ▼
   get_edges() → Kanten-Daten (Position, Richtung, Normale)
         │
         ▼
CaveAutoRockPlacer liest die Kanten
         │
         ▼
   Platziert Felsen entlang jeder Kante:
   • Basis-Felsen: In Richtung "Normal" (weg vom Raum) gestreut
   • Überhänge: Felsen die nach innen über den Raum hängen
   • Strata: Horizontale Gesteinsschichten an langen Wänden
   • Deckenfelsen: Über dem Raum hängend
```

### Ergebnis:

```
Vorher (nur Polygon):          Nachher (mit Auto-Rocks):

    ┌──────────┐                   �ite⿕▓▓▓▓▓▓▓▓⿕░
    │          │                  ▓░░          ░░▓
    │  Raum    │        →        ▓   Raum      ░▓
    │          │                  ▓░░          ▓▓
    └──────────┘                   ░▓▓▓▓▓▓▓▓▓▓░

                              (▓ = 3D-Felsen, ░ = Boden)
```

---

## Schritt 6: Wasser, Deko, Licht

Jetzt wo die Form steht, dekorierst du:

### Wasser
- CaveStream an gewünschter Position platzieren
- `flow_direction` passend zum Höhlenverlauf setzen

### Kristalle
- CaveCrystal Nodes platzieren
- Farbe und Licht konfigurieren

### Stalaktiten
- CaveStalactite über dem Spielerbereich
- `height` höher als Spieler-Y setzen

### Beleuchtung
- CaveLightingRig: Spotlight-Position über dem Hauptraum
- CaveLightingManager: Einzelne Fackeln und Kristall-Lichter

### Atmosphäre
- CaveAtmosphere: Staub, Nebel, Tropfen
- CaveForeground: Dunkle Felsen am Bildrand

---

## Schritt 7: Unerreichbare Bereiche (Background-Deko)

Das sind Flächen die der Spieler SEHEN aber nicht BETRETEN kann:

1. Erstelle einen weiteren CaveRoomBuilder
2. Setze `generate_collision = false` (kein Collision!)
3. Setze `generate_navigation = false`
4. Definiere das Polygon für den Hintergrund-Bereich
5. Platziere ihn mit Abstand (Schlucht/Kluft dazwischen)
6. Füge ein CaveStream mit Audio hinzu (hörbar aber unerreichbar)
7. Dimme die Beleuchtung dort (wenig/kein Licht = wirkt entfernt)

---

## Zusammenfassung: Was macht was?

```
DU machst:                           DAS SYSTEM generiert:

1. Polygon-Punkte setzen             → Boden-Mesh
   (Room Shape definieren)           → Collision-Wände
                                     → Navigation-Mesh
                                     → Vertex Colors für Shader

2. Path3D für Gänge zeichnen         → Gang-Boden-Mesh
                                     → Gang-Collision
                                     → Gang-Navigation

3. CaveAutoRockPlacer                → 3D-Felsbrocken überall
   konfigurieren                     → Überhänge
                                     → Deckenfelsen
                                     → Gesteinsschichten

4. Spotlight positionieren           → Dramatische Beleuchtung
                                     → Schatten
                                     → Vignette + Post-Processing

5. Deko platzieren                   → Wasser mit Caustics
   (Streams, Kristalle,              → Leuchtende Kristalle
    Stalaktiten)                     → Stimmungsvolle Partikel

6. Foreground-Felsen setzen          → Depth-Effekt
                                     → Automatisches Fading
```

---

## Typischer Zeitaufwand pro Raum

| Aufgabe | Zeit |
|---------|------|
| Polygon definieren (6-12 Punkte) | 2-5 Min |
| Gang-Pfade zeichnen | 2-3 Min pro Gang |
| Auto-Rock-Placer tunen | 5 Min einmalig |
| Licht positionieren | 3-5 Min |
| Wasser + Deko platzieren | 10-15 Min |
| Foreground-Felsen | 5 Min |
| **Gesamt pro Raum** | **~30 Min** |

---

## Fortgeschritten: Mehrere Ebenen

Für Höhlen mit mehreren Stockwerken:
- Nutze verschiedene `floor_y` Werte
- Raum oben: `floor_y = 0`, Raum unten: `floor_y = -3`
- Verbinde mit einem schrägen Corridor (Path3D mit Y-Änderung)
- Treppen als Deko-Sprites dazwischen
