// Sticky notes bar button + panel. Clicking the icon opens a panel holding
// every note as a colored card you can type into; notes never go on the desktop.
// Middle click: open with a new note. Shortcut: SUPER+M opens/closes.
// IPC: omarchy-shell stickynotes toggle | open | all | add
//
// Each bar (one per monitor) has its own copy of this widget. They share
// notes through ~/.local/share/omarchy-sticky-notes/notes.json and reload when
// another copy writes it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "io.github.tahsin005.sticky-notes"

  property bool popupOpen: false
  property bool showAll: false          // "View all" expanded panel
  readonly property int compactLimit: 6
  readonly property int boardCols: showAll ? 6 : 4
  property string searchQuery: ""
  readonly property string searchFilter: searchQuery.trim().toLowerCase()
  readonly property bool isSearching: searchFilter.length > 0
  readonly property int matchingCount: {
    store.rev
    if (!searchFilter) return notesModel.count
    var cnt = 0
    for (var i = 0; i < notesModel.count; i++) {
      var t = notesModel.get(i).text || ""
      if (t.toLowerCase().indexOf(searchFilter) >= 0) cnt++
    }
    return cnt
  }

  // Drag and drop state
  property string draggingNoteId: ""
  property int dropTargetIndex: -1

  function updateDropTarget(draggedCard) {
    if (isSearching) return
    var cx = draggedCard.x + draggedCard.width / 2
    var cy = draggedCard.y + draggedCard.height / 2
    var target = -1
    var pad = grid.gap / 2
    for (var i = 0; i < notesModel.count; i++) {
      if (i === draggedCard.index) continue
      var r = board.rects[i]
      if (!r) continue
      var rx = r.c * (grid.cell + grid.gap)
      var ry = r.r * (grid.rowH + grid.gap)
      var rw = r.w * grid.cell + (r.w - 1) * grid.gap
      var rh = r.h * grid.rowH + (r.h - 1) * grid.gap
      if (cx >= rx - pad && cx <= rx + rw + pad && cy >= ry - pad && cy <= ry + rh + pad) {
        target = i
        break
      }
    }
    dropTargetIndex = target
  }

  function finalizeDrop(fromIndex) {
    var target = dropTargetIndex
    draggingNoteId = ""
    dropTargetIndex = -1
    if (target >= 0 && target !== fromIndex) {
      store.moveNote(fromIndex, target)
    } else {
      store.rev++
    }
  }

  readonly property var board: computeBoard(store.rev, fitRev, boardCols, showAll, searchFilter)

  // Each card measures its text and reports the span it needs, by note id:
  // { w: columns, h: rows }. A span depends only on the text and the column
  // width, never on where the board puts the card, so there is no layout loop.
  property var fit: ({})
  property int fitRev: 0
  function setFit(id, w, h) {
    var f = fit[id]
    if (f && f.w === w && f.h === h) return
    fit[id] = { w: w, h: h }
    // One re-pack per event-loop pass, not one per card: when every card
    // re-measures at once (View all, a reload) that would be N full re-packs.
    Qt.callLater(bumpFit)
  }
  function bumpFit() { fitRev++ }

  // Bento packing: place each note (in order) at the first free spot that
  // fits its measured span. Returns a cell rect per note (null = not shown)
  // + row count.
  function computeBoard(_rev, _fit, cols, all, filter) {
    var occ = [], rects = [], rows = 0
    function free(r, c, w, h) {
      for (var y = r; y < r + h; y++)
        for (var x = c; x < c + w; x++) if (occ[y] && occ[y][x]) return false
      return true
    }
    for (var i = 0; i < notesModel.count; i++) {
      var n = notesModel.get(i)
      if (filter && (!n.text || n.text.toLowerCase().indexOf(filter) < 0)) {
        rects.push(null)
        continue
      }
      if (!filter && !all && i >= compactLimit) { rects.push(null); continue }
      var f = fit[n.noteId]
      var w = Math.min(f ? f.w : store.colsOf(store.sizeAt(i)), cols), h = f ? f.h : 1, done = false
      for (var r = 0; !done; r++) {
        for (var c = 0; c <= cols - w; c++) {
          if (!free(r, c, w, h)) continue
          for (var y = r; y < r + h; y++) { occ[y] = occ[y] || []; for (var x = c; x < c + w; x++) occ[y][x] = true }
          rects.push({ c: c, r: r, w: w, h: h })
          rows = Math.max(rows, r + h)
          done = true
          break
        }
      }
    }
    return { rects: rects, rows: rows }
  }
  onPopupOpenChanged: {
    if (!popupOpen) {
      showAll = false
      searchQuery = ""
    }
  }
  readonly property var svc: store
  readonly property int count: notesModel.count

  // Panel colors follow the theme (red/black).
  readonly property color fg: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color subtle: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color raised: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
  readonly property string uiFont: Style.font.family
  readonly property string noteFont: "sans-serif"

  function close() { popupOpen = false }
  function open() { popupOpen = true }
  function onFocusedScreen() {
    var w = root.QsWindow.window
    var m = Hyprland.focusedMonitor
    return !!(w && w.screen && m && w.screen.name === m.name)
  }
  // The copy of this widget on the focused monitor (falls back to this one).
  function focusedPeer() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].onFocusedScreen && items[i].onFocusedScreen()) return items[i]
    return root
  }
  function stamp(ms) {
    if (!ms) return ""
    var d = new Date(ms), now = new Date()
    if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
    var y = new Date(now); y.setDate(now.getDate() - 1)
    if (d.toDateString() === y.toDateString()) return "Yesterday"
    return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
  }

  // Only one copy's handler is active; it forwards to the focused monitor's copy.
  IpcHandler {
    target: "stickynotes"
    function toggle(): void { var p = root.focusedPeer(); p.popupOpen = !p.popupOpen }
    function open(): void { root.focusedPeer().open() }
    function all(): void { var p = root.focusedPeer(); p.open(); p.showAll = true }
    function add(): void { var p = root.focusedPeer(); p.svc.addNote(); p.open() }
  }

  ListModel { id: notesModel }

  // ── Notes store ────────────────────────────────────────────────────
  QtObject {
    id: store

    // The common sticky-note colors (Post-it / Windows Sticky Notes).
    readonly property var palette: [
      { key: "yellow",   name: "Yellow",   color: "#fff176" },
      { key: "pink",     name: "Pink",     color: "#ffa6c9" },
      { key: "blue",     name: "Blue",     color: "#a5d8ff" },
      { key: "green",    name: "Green",    color: "#b9f2a8" },
      { key: "orange",   name: "Orange",   color: "#ffc285" },
      { key: "purple",   name: "Purple",   color: "#d8bfff" },
      { key: "gray",     name: "Gray",     color: "#e4e4e4" },
      { key: "charcoal", name: "Charcoal", color: "#3b3b3b" }
    ]
    readonly property var notes: notesModel
    readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-sticky-notes"
    property bool loaded: false
    // Set once the setup check below has made the notes folder and file safe to use.
    // Until then nothing is read or written. If the check fails, storageError says why
    // and the panel shows it instead of notes.
    property bool storageReady: false
    property string storageError: ""
    property string lastAddedId: ""
    property string lastColor: "yellow"
    property string lastWritten: ""
    property int rev: 0          // bumps on every change; drives the bento layout

    // Resize picks a note's starting width: narrow (1 column) or wide (2).
    // Height always fits the text, and a long note widens further on its own.
    // Older "t"/"l" sizes still load, as narrow and wide.
    readonly property var sizeCycle: ["s", "w"]
    function colsOf(sz) { return sz === "w" || sz === "l" ? 2 : 1 }
    // A note's size: the one picked with the resize button, else from its text.
    function sizeAt(i) {
      var n = notesModel.get(i)
      if (!n) return "s"   // delegate of a note that was just removed
      if (n.size) return n.size
      var t = n.text || "", lines = t.split("\n").length
      if (t.length > 140 || lines >= 9) return "l"
      if (lines >= 5) return "t"
      if (t.length > 70) return "w"
      return "s"
    }
    function cycleSize(id) {
      var i = indexOf(id)
      if (i < 0) return
      notesModel.setProperty(i, "size", colsOf(sizeAt(i)) === 2 ? "s" : "w")
      rev++
      save()
    }
    function setColor(id, key) {
      var i = indexOf(id)
      if (i < 0) return
      notesModel.setProperty(i, "colorKey", key)
      lastColor = key
      rev++
      save()
    }

    function colorFor(key) {
      for (var i = 0; i < palette.length; i++) if (palette[i].key === key) return palette[i].color
      return palette[0].color
    }
    function isDark(key) { return key === "charcoal" }
    function indexOf(id) {
      for (var i = 0; i < notesModel.count; i++) if (notesModel.get(i).noteId === id) return i
      return -1
    }
    function addNote(colorKey) {   // newest first
      if (storageError !== "") return ""   // could never be saved
      var id = String(Date.now()) + Math.floor(Math.random() * 1000)
      lastAddedId = id   // set first: the new card checks it as it is created, then takes the cursor
      notesModel.insert(pinnedCount(), { noteId: id, colorKey: lastColor, text: "", updated: Date.now(), pinned: false, size: "w" })   // new notes start wide
      rev++
      save()
      return id
    }
    function pinnedCount() {
      var n = 0
      for (var i = 0; i < notesModel.count; i++) if (notesModel.get(i).pinned) n++
      return n
    }
    // Pinned notes sit at the top; unpinning drops a note just below them.
    function togglePin(id) {
      var i = indexOf(id)
      if (i < 0) return
      var pin = !notesModel.get(i).pinned
      notesModel.setProperty(i, "pinned", pin)
      notesModel.move(i, pin ? 0 : pinnedCount(), 1)
      rev++
      save()
    }
    function moveNote(fromIndex, toIndex) {
      if (fromIndex < 0 || toIndex < 0 || fromIndex === toIndex || fromIndex >= notesModel.count || toIndex >= notesModel.count) return
      var pCount = pinnedCount()
      var willBePinned = toIndex < pCount
      if (fromIndex < pCount && toIndex >= pCount) willBePinned = false
      if (fromIndex >= pCount && toIndex < pCount) willBePinned = true
      notesModel.setProperty(fromIndex, "pinned", willBePinned)
      notesModel.move(fromIndex, toIndex, 1)
      rev++
      save()
    }
    function deleteNote(id) {
      var i = indexOf(id)
      if (i < 0) return
      notesModel.remove(i)
      rev++
      save()
    }
    function update(id, props) {
      var i = indexOf(id)
      if (i < 0) return
      for (var k in props) notesModel.setProperty(i, k, props[k])
      notesModel.setProperty(i, "updated", Date.now())
      rev++
      saveTimer.restart()
    }
    function serialize() {
      var list = []
      for (var i = 0; i < notesModel.count; i++) {
        var n = notesModel.get(i)
        list.push({ id: n.noteId, color: n.colorKey, text: n.text, updated: n.updated, pinned: n.pinned, size: n.size })
      }
      return JSON.stringify({ version: 2, lastColor: lastColor, notes: list }, null, 2) + "\n"
    }
    function save() {
      saveTimer.stop()
      if (!loaded) return
      lastWritten = serialize()
      dataFile.setText(lastWritten)
    }
    function load(raw) {
      if (raw === lastWritten) { loaded = true; return }   // our own write coming back
      // Check the whole file before touching the notes. A file caught half
      // written (another program saving it in place) or broken must not clear
      // them, or the next save would write that loss to disk. Keep the notes,
      // and don't start saving over a file we could not read.
      var data, list
      try {
        data = JSON.parse(raw)
        if (!data || typeof data !== "object" || Array.isArray(data)) throw "not a notes file"
        list = data.notes === undefined ? [] : data.notes
        if (!Array.isArray(list)) throw "notes is not a list"
        for (var j = 0; j < list.length; j++)
          if (!list[j] || typeof list[j] !== "object") throw "note " + j + " is not an object"
      } catch (e) {
        console.warn("sticky-notes: could not read notes.json, keeping the notes in memory: " + e)
        return
      }
      lastWritten = raw
      if (data.lastColor) lastColor = String(data.lastColor)
      notesModel.clear()
      for (var i = 0; i < list.length; i++)
        notesModel.append({
          noteId: String(list[i].id), colorKey: String(list[i].color || "yellow"),
          text: String(list[i].text || ""), updated: Number(list[i].updated) || 0,
          pinned: list[i].pinned === true,
          size: ["s", "w", "t", "l"].indexOf(list[i].size) >= 0 ? list[i].size : ""
        })
      loaded = true
      rev++
    }
  }

  Timer { id: saveTimer; interval: 400; onTriggered: store.save() }
  Component.onDestruction: if (saveTimer.running) store.save()

  // Notes are private: the folder is owner-only (0700) and notes.json is 0600,
  // whatever the umask. Folders and files left by older versions are tightened too.
  // The file is seeded empty with 0600 so the first save keeps that mode (atomic
  // writes keep the mode of the file they replace). The path goes in as $1, never
  // spliced into the script.
  //
  // Before anything is tightened or read, the folder and notes.json must belong to
  // you, and notes.json must be a regular file, not a symlink. An older install
  // could leave the folder writable by other accounts, and another account could
  // have put a notes.json symlink there that points at a file it owns. chmod can't
  // tighten that file, so the plugin would keep its notes in someone else's
  // readable file. Any failed check stops the plugin from using the folder at all.
  // The folder is made 0700 before notes.json is checked, so no other account can
  // swap the file once it has been checked.
  // Exit codes: 1 could not create or fix, 2 folder not yours, 3 notes.json not a
  // regular file or a symlink, 4 notes.json not yours.
  Process {
    running: true
    command: ["sh", "-c",
      'umask 077; d="$1"; f="$d/notes.json"; ' +
      'mkdir -p -- "$d" || exit 1; ' +
      '[ -d "$d" ] && [ -O "$d" ] || exit 2; ' +
      'chmod 700 -- "$d" || exit 1; ' +
      'if [ -L "$f" ]; then exit 3; fi; ' +
      'if [ -e "$f" ]; then ' +
        '[ -f "$f" ] || exit 3; [ -O "$f" ] || exit 4; chmod 600 -- "$f" || exit 1; ' +
      'else printf \'{ "version": 2, "notes": [] }\\n\' > "$f" || exit 1; fi',
      "sh", store.dataDir]
    onExited: function(exitCode) {
      if (exitCode === 0) { store.storageReady = true; return }
      var why = {
        2: "the folder is not owned by your account",
        3: "notes.json is a symlink or not a regular file",
        4: "notes.json is not owned by your account"
      }[exitCode] || "it could not be made private (owner-only)"
      store.storageError = "Notes not loaded: " + why + "."
      console.warn("sticky-notes: not using " + store.dataDir + ": " + why +
        ". Fix or remove it, then reload the shell.")
    }
  }

  FileView {
    id: dataFile
    path: store.storageReady ? store.dataDir + "/notes.json" : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: if (!saveTimer.running) store.load(text())
    onLoadFailed: if (store.storageReady) store.loaded = true
  }

  // ── Bar button ─────────────────────────────────────────────────────
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""   // nf-fa-sticky_note
    active: root.popupOpen
    tooltipText: root.count === 0 ? "Sticky notes (Super+M)"
      : root.count + (root.count === 1 ? " sticky note" : " sticky notes") + " (Super+M)"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { store.addNote(); root.open() }
      else root.popupOpen = !root.popupOpen
    }
  }

  // ── Panel ──────────────────────────────────────────────────────────
  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: panel.fittedContentWidth(root.showAll ? Style.space(980) : Style.space(640))
    contentHeight: panel.fittedContentHeight(
      header.height + notesArea.height + footer.height + layout.spacing * 2)

    Column {
      id: layout
      width: parent.width
      spacing: Style.space(14)

      // Panel keys (work wherever the focus is inside the panel)
      Shortcut {
        sequence: "Ctrl+N"
        context: Qt.WindowShortcut
        enabled: root.popupOpen
        onActivated: { store.addNote(); flick.contentY = 0 }
      }
      Shortcut {
        sequence: "Ctrl+F"
        context: Qt.WindowShortcut
        enabled: root.popupOpen
        onActivated: {
          searchInput.forceActiveFocus()
          searchInput.selectAll()
        }
      }
      Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.popupOpen
        onActivated: root.close()
      }

      // Title row
      Item {
        id: header
        width: parent.width
        height: Style.space(26)

        Row {
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          spacing: Style.space(10)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.accent
            font.family: root.uiFont
            font.pixelSize: Style.space(17)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Sticky notes"
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.space(15)
            font.weight: Font.DemiBold
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.count > 0
            height: Style.space(18)
            width: Math.max(height, countText.implicitWidth + Style.space(12))
            radius: height / 2
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            Text {
              id: countText
              anchors.centerIn: parent
              text: root.isSearching ? root.matchingCount + "/" + root.count : root.count
              color: root.accent
              font.family: root.uiFont
              font.pixelSize: Style.space(11)
              font.weight: Font.DemiBold
            }
          }
        }

        Rectangle {
          id: newBtn
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          height: Style.space(28)
          width: height
          radius: Style.space(7)
          color: newMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
          Text {
            anchors.centerIn: parent
            text: "+"
            color: "#ffffff"
            font.family: root.noteFont
            font.pixelSize: Style.space(20)
            font.weight: Font.Bold
          }
          MouseArea {
            id: newMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { store.addNote(); flick.contentY = 0 }
          }
        }

        Rectangle {
          id: searchBox
          anchors {
            right: (viewAll.visible ? viewAll.left : newBtn.left)
            rightMargin: Style.space(8)
            verticalCenter: parent.verticalCenter
          }
          height: Style.space(26)
          width: (searchInput.activeFocus || root.searchQuery) ? Style.space(190) : Style.space(140)
          radius: Style.space(6)
          color: searchInput.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : root.raised
          border.width: 1
          border.color: searchInput.activeFocus ? root.accent : root.hairline
          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

          Text {
            id: searchIcon
            anchors { left: parent.left; leftMargin: Style.space(8); verticalCenter: parent.verticalCenter }
            text: ""   // fa-search
            color: searchInput.activeFocus ? root.accent : root.subtle
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
          }

          TextInput {
            id: searchInput
            anchors {
              left: searchIcon.right
              leftMargin: Style.space(6)
              right: clearBtn.visible ? clearBtn.left : parent.right
              rightMargin: clearBtn.visible ? Style.space(4) : Style.space(8)
              verticalCenter: parent.verticalCenter
            }
            clip: true
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
            selectByMouse: true
            selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
            selectedTextColor: root.fg
            text: root.searchQuery
            onTextChanged: if (root.searchQuery !== text) root.searchQuery = text

            Text {
              visible: !searchInput.text && !searchInput.activeFocus
              anchors.verticalCenter: parent.verticalCenter
              text: "Search... (Ctrl+F)"
              color: root.subtle
              font: searchInput.font
            }

            Keys.onEscapePressed: function(event) {
              if (text !== "") {
                text = ""
                event.accepted = true
              } else {
                focus = false
                event.accepted = false
              }
            }
          }

          Text {
            id: clearBtn
            visible: searchInput.text !== ""
            anchors { right: parent.right; rightMargin: Style.space(6); verticalCenter: parent.verticalCenter }
            text: ""   // fa-times
            color: clearMouse.containsMouse ? root.fg : root.subtle
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
            MouseArea {
              id: clearMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
            }
          }
        }

        Rectangle {
          id: viewAll
          anchors { right: newBtn.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
          visible: root.count > root.compactLimit || root.showAll
          height: Style.space(26)
          width: viewAllText.implicitWidth + Style.space(20)
          radius: Style.space(6)
          color: viewAllMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : root.raised
          border.width: 1
          border.color: viewAllMouse.containsMouse ? root.accent : root.hairline
          Text {
            id: viewAllText
            anchors.centerIn: parent
            text: root.showAll ? "Show less" : "View all (" + root.count + ")"
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.space(12)
          }
          MouseArea {
            id: viewAllMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.showAll = !root.showAll; flick.contentY = 0 }
          }
        }
      }


      // Notes grid (scrolls after three rows)
      Item {
        id: notesArea
        width: parent.width
        // Grows with the board, then scrolls.
        height: root.count === 0 ? Style.space(150)
          : root.showAll ? Math.min(grid.implicitHeight, Style.space(780))
          : Math.min(grid.implicitHeight, Style.space(600))

        Column {
          visible: root.count === 0
          anchors.centerIn: parent
          spacing: Style.space(8)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: root.hairline
            font.family: root.uiFont
            font.pixelSize: Style.space(40)
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: store.storageError !== "" ? "Notes are turned off" : "No notes yet"
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.space(13)
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, notesArea.width - Style.space(32))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: store.storageError !== ""
              ? store.storageError + "\nCheck ~/.local/share/omarchy-sticky-notes, then reload the shell."
              : "Click + to start one"
            color: root.subtle
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
          }
        }

        Column {
          visible: root.count > 0 && root.matchingCount === 0
          anchors.centerIn: parent
          spacing: Style.space(8)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: root.hairline
            font.family: root.uiFont
            font.pixelSize: Style.space(36)
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No matching notes"
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.space(13)
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No notes contain \"" + root.searchQuery + "\""
            color: root.subtle
            font.family: root.uiFont
            font.pixelSize: Style.space(11)
          }
        }

        Flickable {
          id: flick
          anchors.fill: parent
          visible: root.matchingCount > 0
          contentWidth: width
          contentHeight: grid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          // Keep the caret in view when a tall board scrolls.
          function reveal(item, r) {
            var y = item.mapToItem(grid, r.x, r.y).y
            if (y < contentY) contentY = y
            else if (y + r.height > contentY + height) contentY = y + r.height - height
          }

          Item {
            id: grid
            width: flick.width
            readonly property real gap: Style.space(12)
            readonly property real cell: (width - gap * (root.boardCols - 1)) / root.boardCols
            // Fine rows, so a card is at most one small step taller than its text.
            readonly property real rowH: Style.space(8)
            // Tallest a card gets before it widens instead (an old "tall" note).
            readonly property real maxCardH: 2 * Math.round(cell * 0.82) + gap
            implicitHeight: root.board.rows > 0 ? root.board.rows * rowH + (root.board.rows - 1) * gap : 0
            height: implicitHeight

            Repeater {
              model: notesModel
              delegate: NoteCard {
                readonly property var rect: root.board.rects[index] || null
                visible: rect !== null
                targetX: rect ? rect.c * (grid.cell + grid.gap) : 0
                targetY: rect ? rect.r * (grid.rowH + grid.gap) : 0
                width: rect ? rect.w * grid.cell + (rect.w - 1) * grid.gap : 0
                height: rect ? rect.h * grid.rowH + (rect.h - 1) * grid.gap : 0
              }
            }
          }
        }
      }

      // Footer hint
      Text {
        id: footer
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: (root.isSearching
                ? root.matchingCount + (root.matchingCount === 1 ? " note found" : " notes found") + "  ·  Esc clears search"
                : (!root.showAll && root.count > root.compactLimit
                    ? (root.count - root.compactLimit) + " more in View all  ·  " : "")
                  + "Ctrl+N new  ·  Ctrl+F search  ·  Drag to reorder  ·  Esc to close")
        color: root.subtle
        opacity: 0.8
        font.family: root.uiFont
        font.pixelSize: Style.space(10)
      }
    }
  }

  // ── One note card ──────────────────────────────────────────────────
  component NoteCard: Item {
    id: card
    required property int index
    required property string noteId
    required property string colorKey
    required property string text
    required property real updated
    required property bool pinned

    property bool confirmDelete: false
    property bool showPalette: false
    readonly property bool dark: store.isDark(colorKey)
    readonly property color ink: dark ? "#f2f2f2" : "#262626"
    readonly property color inkSoft: Qt.rgba(ink.r, ink.g, ink.b, 0.5)
    readonly property color paper: store.colorFor(colorKey)
    property bool settled: false

    property real targetX: 0
    property real targetY: 0
    property real dragDeltaX: 0
    property real dragDeltaY: 0
    x: targetX + dragDeltaX
    y: targetY + dragDeltaY

    readonly property bool isDragging: root.draggingNoteId === noteId
    readonly property bool isDropTarget: root.dropTargetIndex === index && root.draggingNoteId !== "" && !isDragging
    z: isDragging ? 100 : (isDropTarget ? 10 : (card.hot ? 5 : 1))
    scale: isDragging ? 1.04 : 1.0
    Behavior on scale { NumberAnimation { duration: 120 } }

    Behavior on x { enabled: card.settled && !card.isDragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: card.settled && !card.isDragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: card.settled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: card.settled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    readonly property bool hot: cardHover.hovered || body.activeFocus
    readonly property int fold: Style.space(18)

    // Width: start at the picked width and widen (up to 4 columns) while the
    // text would make the card taller than maxCardH. Measured with hidden copies
    // of the text at each width, so it never depends on the card's own size.
    readonly property int prefCols: { store.rev; return Math.min(store.colsOf(store.sizeAt(index)), root.boardCols) }
    readonly property int maxCols: Math.max(prefCols, Math.min(4, root.boardCols))
    function bodyWFor(c) { return c * grid.cell + (c - 1) * grid.gap - Style.space(28) }
    readonly property var probeH: [probe1.contentHeight, probe2.contentHeight, probe3.contentHeight, probe4.contentHeight]
    readonly property int cols: {
      // Narrowest width that fits; else the shortest one (extra width that
      // doesn't shorten the note, e.g. many short lines, is not taken).
      var best = prefCols
      for (var c = prefCols; c <= maxCols; c++) {
        if (bodyTop + probeH[c - 1] + footH <= grid.maxCardH) return c
        if (probeH[c - 1] < probeH[best - 1] - 0.5) best = c
      }
      return best
    }
    // Text area: fixed to the final column width (not the animated card width),
    // so the measured height settles at once. Card height follows the text.
    readonly property real bodyW: bodyWFor(cols)
    readonly property real bodyTop: Style.space(34)
    readonly property real footH: Style.space(4) + Math.max(when.height, Style.space(14)) + Style.space(9)
    readonly property real needH: bodyTop + body.contentHeight + footH
    readonly property int fitRows: Math.max(1, Math.ceil((needH + grid.gap) / (grid.rowH + grid.gap) - 0.001))
    onColsChanged: root.setFit(noteId, cols, fitRows)
    onFitRowsChanged: root.setFit(noteId, cols, fitRows)

    Text { id: probe1; visible: false; width: card.bodyWFor(1); text: body.text; font: body.font; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    Text { id: probe2; visible: false; width: card.bodyWFor(2); text: body.text; font: body.font; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    Text { id: probe3; visible: false; width: card.bodyWFor(3); text: body.text; font: body.font; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    Text { id: probe4; visible: false; width: card.bodyWFor(4); text: body.text; font: body.font; wrapMode: Text.Wrap; textFormat: Text.PlainText }

    HoverHandler { id: cardHover }

    Component.onCompleted: {
      body.text = card.text
      root.setFit(noteId, cols, fitRows)
      Qt.callLater(function() { card.settled = true })
      if (store.lastAddedId === noteId) {
        store.lastAddedId = ""
        Qt.callLater(function() { body.forceActiveFocus() })
      }
    }

    // soft drop shadow
    Rectangle {
      anchors.fill: paperRect
      anchors.topMargin: card.isDragging ? Style.space(8) : Style.space(3)
      anchors.leftMargin: Style.space(1)
      anchors.rightMargin: -Style.space(1)
      anchors.bottomMargin: card.isDragging ? -Style.space(10) : -Style.space(4)
      radius: paperRect.radius
      color: "#000000"
      opacity: card.isDragging ? 0.75 : (body.activeFocus ? 0.6 : card.hot ? 0.45 : 0.3)
      Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Drop target highlight outline
    Rectangle {
      anchors.fill: parent
      radius: paperRect.radius
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
      border.width: card.isDropTarget ? 2 : 0
      border.color: root.accent
      visible: card.isDropTarget
      z: 20
    }

    // the paper, with its bottom-right corner folded over
    Canvas {
      id: paperRect
      anchors.fill: parent
      property real radius: Style.space(8)
      property color fill: card.paper
      onFillChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var c = getContext("2d"), w = width, h = height, r = radius, f = card.fold
        c.reset()
        c.beginPath()
        c.moveTo(r, 0); c.lineTo(w - r, 0); c.arcTo(w, 0, w, r, r)
        c.lineTo(w, h - f); c.lineTo(w - f, h)
        c.lineTo(r, h); c.arcTo(0, h, 0, h - r, r)
        c.lineTo(0, r); c.arcTo(0, 0, r, 0, r)
        c.closePath()
        c.fillStyle = fill
        c.fill()
        // the fold
        c.beginPath()
        c.moveTo(w, h - f); c.lineTo(w - f, h - f); c.lineTo(w - f, h); c.closePath()
        var k = card.dark ? 1.45 : 0.84
        c.fillStyle = Qt.rgba(Math.min(1, fill.r * k), Math.min(1, fill.g * k), Math.min(1, fill.b * k), 1)
        c.fill()
      }
    }

    // Top controls (show on hover / focus)
    Row {
      id: tools
      anchors { top: parent.top; right: parent.right; topMargin: Style.space(6); rightMargin: Style.space(6) }
      spacing: Style.space(2)
      opacity: card.hot || card.confirmDelete || card.showPalette || card.isDragging ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      CardButton {
        glyph: ""   // 4-way move/drag
        ink: card.ink
        cursorShape: card.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real startMouseGridX: 0
        property real startMouseGridY: 0

        onPressed: function(mouse) {
          var p = mapToItem(grid, mouse.x, mouse.y)
          startMouseGridX = p.x
          startMouseGridY = p.y
          card.dragDeltaX = 0
          card.dragDeltaY = 0
        }

        onPositionChanged: function(mouse) {
          if (mouse.buttons & Qt.LeftButton) {
            var p = mapToItem(grid, mouse.x, mouse.y)
            var dx = p.x - startMouseGridX
            var dy = p.y - startMouseGridY
            if (!card.isDragging) {
              if (Math.hypot(dx, dy) > 4) {
                root.draggingNoteId = card.noteId
                root.dropTargetIndex = -1
              }
            }
            if (card.isDragging) {
              card.dragDeltaX = dx
              card.dragDeltaY = dy
              root.updateDropTarget(card)
            }
          }
        }

        onReleased: function() {
          if (card.isDragging) {
            root.finalizeDrop(card.index)
          }
          card.dragDeltaX = 0
          card.dragDeltaY = 0
        }

        onCanceled: function() {
          if (card.isDragging) {
            root.draggingNoteId = ""
            root.dropTargetIndex = -1
          }
          card.dragDeltaX = 0
          card.dragDeltaY = 0
        }
      }
      CardButton {
        glyph: ""   // pin
        ink: card.ink
        active: card.pinned
        onClicked: store.togglePin(card.noteId)
      }
      CardButton {
        glyph: ""   // nf-fae-palette_color (palette icon)
        ink: card.ink
        active: card.showPalette
        onClicked: card.showPalette = !card.showPalette
      }
      CardButton {
        glyph: "\uf065"   // resize: narrow ↔ wide
        ink: card.ink
        onClicked: store.cycleSize(card.noteId)
      }
      CardButton {
        glyph: "\uf1f8"   // trash; turns red, click again to delete
        ink: card.confirmDelete ? "#e53935" : card.ink
        onClicked: {
          if (card.confirmDelete || body.text.trim() === "") store.deleteNote(card.noteId)
          else { card.confirmDelete = true; confirmTimer.restart() }
        }
      }
    }

    // Color palette picker
    Rectangle {
      id: colorPicker
      z: 10
      anchors { top: tools.bottom; right: parent.right; topMargin: Style.space(2); rightMargin: Style.space(4) }
      visible: card.showPalette
      width: paletteRow.width + Style.space(12)
      height: paletteRow.height + Style.space(10)
      radius: Style.space(6)
      color: Qt.rgba(card.paper.r, card.paper.g, card.paper.b, 0.95)
      border.width: 1
      border.color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.15)

      Row {
        id: paletteRow
        anchors.centerIn: parent
        spacing: Style.space(4)
        Repeater {
          model: store.palette
          delegate: Rectangle {
            required property var modelData
            width: Style.space(18)
            height: Style.space(18)
            radius: width / 2
            color: modelData.color
            border.width: modelData.key === card.colorKey ? 2 : (dotHover.containsMouse ? 1 : 0)
            border.color: store.isDark(modelData.key) ? "#aaaaaa" : "#444444"
            scale: dotHover.containsMouse ? 1.15 : 1.0
            Behavior on scale { NumberAnimation { duration: 80 } }

            Text {
              anchors.centerIn: parent
              visible: modelData.key === card.colorKey
              text: "\u2713"
              color: store.isDark(modelData.key) ? "#f2f2f2" : "#262626"
              font.pixelSize: Style.space(10)
              font.weight: Font.Bold
            }

            MouseArea {
              id: dotHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                store.setColor(card.noteId, modelData.key)
                card.showPalette = false
              }
            }
          }
        }
      }
    }

    Timer { id: confirmTimer; interval: 3000; onTriggered: card.confirmDelete = false }


    // Text (the card grows to fit it, so there is no inner scrolling)
    TextEdit {
      id: body
      x: Style.space(14)
      y: card.bodyTop
      width: card.bodyW
      height: Math.max(contentHeight, card.height - card.bodyTop - card.footH)
      wrapMode: TextEdit.Wrap
      textFormat: TextEdit.PlainText
      selectByMouse: true
      color: card.ink
      selectionColor: card.dark ? "#777777" : Qt.darker(card.paper, 1.3)
      selectedTextColor: card.ink
      font.family: root.noteFont
      font.pixelSize: Style.space(14)
      onTextChanged: if (text !== card.text) store.update(card.noteId, { text: text })
      onCursorRectangleChanged: if (activeFocus) flick.reveal(body, cursorRectangle)
      Keys.onEscapePressed: root.close()

      Text {
        visible: body.text === "" && !body.activeFocus
        text: "Write something…"
        color: card.inkSoft
        font: body.font
      }
    }

    // Pinned marker (always visible)
    Text {
      visible: card.pinned
      anchors { left: parent.left; top: parent.top; leftMargin: Style.space(12); topMargin: Style.space(9) }
      text: ""
      color: card.ink
      rotation: -30
      font.family: root.uiFont
      font.pixelSize: Style.space(13)
    }

    // Edited time
    Text {
      id: when
      anchors { left: parent.left; bottom: parent.bottom; leftMargin: Style.space(14); bottomMargin: Style.space(9) }
      text: root.stamp(card.updated)
      color: card.inkSoft
      font.family: root.noteFont
      font.pixelSize: Style.space(10)
    }
  }

  component CardButton: Rectangle {
    id: btn
    property string glyph: ""
    property color ink: "#262626"
    property bool danger: false
    property bool active: false
    property int cursorShape: Qt.PointingHandCursor
    signal clicked()
    signal pressed(var mouse)
    signal positionChanged(var mouse)
    signal released(var mouse)
    signal canceled()
    readonly property bool wide: glyph.length > 1
    height: Style.space(24)
    width: wide ? lbl.implicitWidth + Style.space(14) : height
    radius: Style.space(6)
    color: danger ? "#d32f2f"
         : (hover.containsMouse || active) ? Qt.rgba(ink.r, ink.g, ink.b, 0.14) : "transparent"
    Text {
      id: lbl
      anchors.centerIn: parent
      text: btn.glyph
      color: btn.ink
      font.family: btn.wide ? root.noteFont : root.uiFont
      font.pixelSize: btn.wide ? Style.space(11) : Style.space(13)
      font.weight: btn.wide ? Font.DemiBold : Font.Normal
    }
    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: btn.cursorShape
      onClicked: btn.clicked()
      onPressed: function(mouse) { btn.pressed(mouse) }
      onPositionChanged: function(mouse) { btn.positionChanged(mouse) }
      onReleased: function(mouse) { btn.released(mouse) }
      onCanceled: function() { btn.canceled() }
    }
  }
}
