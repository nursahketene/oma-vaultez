pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "VaultezModel.js" as Model

Panel {
  id: root
  moduleName: "app.vaultez"
  ipcTarget: "app.vaultez"
  manageIpc: false

  // "idle" | "loading" | "not-installed" | "not-authenticated" | "error" | "ready"
  property string phase: "idle"
  property string errorText: ""
  property string pendingLevel: ""
  // Once the CLI is confirmed present, skip re-running the "command -v"
  // preflight check on every subsequent open — it's a full extra subprocess
  // round-trip in front of the real fetch for a result that's stable for
  // the rest of the session. Stays false (so preflight keeps re-checking)
  // until a check actually succeeds.
  property bool cliVerified: false

  // "companies" | "projects" | "secrets"
  property string viewLevel: "companies"
  property var companies: []
  property var projects: []
  property var secrets: []               // full {name, value} objects for activeProject
  property var activeCompany: null
  property var activeProject: null
  property var navStack: []              // frames captured by pushFrame(), for instant back-nav
  property var revealedNames: ({})       // name -> bool, client-side only

  readonly property string home: Quickshell.env("HOME")
  readonly property string vaultezPath: expandPath(root.setting("vaultezPath", "vaultez"))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string summary: phase === "not-installed" ? "Not installed"
    : phase === "not-authenticated" ? "Not logged in"
    : phase === "error" ? "Error"
    : phase === "loading" ? "Loading…"
    : "Ready"

  readonly property var currentRows: viewLevel === "companies" ? companies
    : (viewLevel === "projects" ? projects : secrets)
  readonly property var displayRows: Model.filterRows(currentRows, filterField ? filterField.text : "", "name")

  readonly property string breadcrumb: viewLevel === "companies" ? "Companies"
    : viewLevel === "projects" ? (activeCompany ? activeCompany.name + " › Projects" : "Projects")
    : (activeCompany && activeProject ? activeCompany.name + " › " + activeProject.name + " › Secrets" : "Secrets")

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value === "") return ""
    if (value === "~") return home
    if (value.indexOf("~/") === 0) return home + value.substring(1)
    return value
  }

  function pushFrame() {
    return {
      level: root.viewLevel,
      companies: root.companies,
      projects: root.projects,
      secrets: root.secrets,
      activeCompany: root.activeCompany,
      activeProject: root.activeProject
    }
  }

  function resetNavigation() {
    root.viewLevel = "companies"
    root.navStack = []
    root.activeCompany = null
    root.activeProject = null
    root.revealedNames = ({})
    if (filterField) filterField.text = ""
  }

  // Re-fetch whatever the panel was last showing (companies/projects/secrets)
  // instead of always resetting to the companies list — so closing and
  // reopening the panel lands back where the user left off.
  function refetchCurrentLevel() {
    if (root.viewLevel === "projects" && root.activeCompany) {
      startFetch("projects", ["--company=" + root.activeCompany.name, "--projects"])
    } else if (root.viewLevel === "secrets" && root.activeCompany && root.activeProject) {
      startFetch("secrets", ["--company=" + root.activeCompany.name, "--project=" + root.activeProject.name])
    } else {
      root.viewLevel = "companies"
      startFetch("companies", ["--companies"])
    }
  }

  function startFetch(level, extraArgs) {
    // Defense-in-depth: enterCompany/enterProject/goBack already refuse to
    // run while phase is "loading", so in practice this only guards
    // refetchCurrentLevel() (fired on every panel open) against overlapping
    // a fetch that's still in flight from before the panel was closed.
    //
    // This checks fetchProcess.running, NOT root.phase — phase is set to
    // "loading" eagerly by onOpenedChanged before the real fetch even
    // starts (preflight runs first, asynchronously), so by the time this
    // function's own legitimate call actually arrives, phase is already
    // "loading" from that same open sequence. Checking phase here would
    // make startFetch() block its own first call on every open.
    if (fetchProcess.running) return
    root.phase = "loading"
    root.errorText = ""
    root.pendingLevel = level
    fetchProcess.command = [root.vaultezPath, "fetch"].concat(extraArgs, ["--json"])
    fetchProcess.running = true
  }

  function handleFetchExit(code, stdoutText, stderrText) {
    if (code === 0) {
      try {
        var parsed = JSON.parse(stdoutText)
        var rows = Array.isArray(parsed) ? parsed : []
        if (root.pendingLevel === "companies") root.companies = rows
        else if (root.pendingLevel === "projects") root.projects = rows
        else if (root.pendingLevel === "secrets") root.secrets = rows
        root.phase = "ready"
        root.errorText = ""
      } catch (error) {
        root.phase = "error"
        root.errorText = "Unexpected response from vaultez CLI"
      }
      return
    }
    var kind = Model.classifyError(stderrText)
    if (kind === "not-authenticated") {
      root.phase = "not-authenticated"
    } else {
      root.phase = "error"
      root.errorText = String(stderrText || ("vaultez exited with code " + code)).trim()
    }
  }

  function enterCompany(company) {
    // fetchProcess is a single shared Process; starting a new fetch while one
    // is already in flight is a no-op (Quickshell won't restart a running
    // Process), so the in-flight response would land under whatever
    // company/project is current by the time it exits. Block navigation
    // during "loading" so there's never more than one fetch outstanding.
    if (root.phase === "loading") return
    root.navStack = root.navStack.concat([pushFrame()])
    root.activeCompany = company
    root.activeProject = null
    root.viewLevel = "projects"
    root.projects = []
    if (filterField) filterField.text = ""
    startFetch("projects", ["--company=" + company.name, "--projects"])
  }

  function enterProject(project) {
    if (root.phase === "loading") return
    root.navStack = root.navStack.concat([pushFrame()])
    root.activeProject = project
    root.viewLevel = "secrets"
    root.secrets = []
    root.revealedNames = ({})
    if (filterField) filterField.text = ""
    startFetch("secrets", ["--company=" + root.activeCompany.name, "--project=" + project.name])
  }

  function goBack() {
    // Also guarded against "loading" — without this, back-then-forward while
    // a fetch is still in flight is exactly how two overlapping fetches can
    // happen in the first place (see enterCompany's comment).
    if (root.phase === "loading") return
    if (root.navStack.length === 0) return
    var frame = root.navStack[root.navStack.length - 1]
    root.navStack = root.navStack.slice(0, -1)
    root.viewLevel = frame.level
    root.companies = frame.companies
    root.projects = frame.projects
    root.secrets = frame.secrets
    root.activeCompany = frame.activeCompany
    root.activeProject = frame.activeProject
    if (filterField) filterField.text = ""
    root.phase = "ready"
    root.errorText = ""
  }

  function toggleReveal(name) {
    var next = Object.assign({}, root.revealedNames)
    next[name] = !next[name]
    root.revealedNames = next
  }

  property string clipboardHash: ""

  function copySecret(value) {
    // --sensitive marks the clipboard offer so Omarchy's own clipboard-history
    // watcher (capture.sh) skips recording it. Also auto-clear the live
    // clipboard shortly after, same as a password manager would — but only
    // if the clipboard still holds what we put there, so we never clobber
    // something the user copied afterward. We keep a hash rather than the
    // plaintext around so the secret itself doesn't linger in memory any
    // longer than the copy itself requires.
    //
    // The secret goes over stdin to both wl-copy and sha256sum, never as a
    // command-line argument — argv is visible to any process on this account
    // via /proc/<pid>/cmdline for as long as the child lives, stdin isn't.
    var text = String(value || "")
    // stdinEnabled is set false in onStarted once the write is flushed, to
    // close the channel so the child sees EOF (see the Process below) — it
    // has to be re-enabled here before every restart, since the declarative
    // "stdinEnabled: true" on the component only applies once, at creation.
    copyProcess.stdinEnabled = true
    copyProcess.pendingText = text
    copyProcess.running = true
    clipboardHashProcess.stdinEnabled = true
    clipboardHashProcess.pendingText = text
    clipboardHashProcess.running = true
  }

  function handleEscape() {
    if (filterField && filterField.text !== "") { filterField.text = ""; return }
    if (root.viewLevel !== "companies") { root.goBack(); return }
    root.close()
  }

  function openInstallTerminal() {
    // Pinned to the exact version this submission was reviewed against.
    // The plugin immediately hands this CLI the saved session and returned
    // secrets, so an open-ended constraint like ">= 0.3.0" would let a
    // future, unreviewed release install itself with no re-audit - a
    // reviewed plugin commit must bind to a single reviewed CLI version.
    // Bump this (and the README) deliberately when adopting a newer,
    // separately-reviewed vaultez-cli release.
    var command = "gem install vaultez-cli --version '0.3.0'; exec \"${SHELL:-/bin/bash}\""
    Quickshell.execDetached(["xdg-terminal-exec", "bash", "-lc", command])
    root.close()
  }

  function openLoginTerminal() {
    var command = Util.shellQuote(root.vaultezPath) + " login; exec \"${SHELL:-/bin/bash}\""
    Quickshell.execDetached(["xdg-terminal-exec", "bash", "-lc", command])
    root.close()
  }

  function openSignup() {
    Quickshell.execDetached(["omarchy-launch-browser", "https://vaultez.app/signup"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (root.opened) {
    // Deliberately NOT resetNavigation() — that would wipe viewLevel/
    // activeCompany/activeProject, throwing away where the user was. Just
    // re-mask secrets and clear the filter; refetchCurrentLevel() (below)
    // reloads whatever level was last showing.
    root.revealedNames = ({})
    if (filterField) filterField.text = ""
    root.phase = "loading"
    root.errorText = ""
    if (root.cliVerified) {
      root.refetchCurrentLevel()
    } else if (!preflightProcess.running) {
      preflightProcess.running = true
    }
    Qt.callLater(function() { filterField.forceActiveFocus() })
  }

  Process {
    id: preflightProcess
    command: ["bash", "-c", "command -v " + Util.shellQuote(root.vaultezPath) + " >/dev/null 2>&1 && printf ready || printf missing"]
    stdout: StdioCollector {
      id: preflightStdout
      waitForEnd: true
      onStreamFinished: {
        if (String(preflightStdout.text).trim() === "ready") {
          root.cliVerified = true
          root.refetchCurrentLevel()
        } else {
          root.phase = "not-installed"
        }
      }
    }
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector { id: fetchStdout; waitForEnd: true }
    stderr: StdioCollector { id: fetchStderr; waitForEnd: true }
    onExited: function(code) { root.handleFetchExit(code, fetchStdout.text, fetchStderr.text) }
  }

  Process {
    id: copyProcess
    command: ["wl-copy", "--sensitive"]
    stdinEnabled: true
    property string pendingText: ""
    onStarted: {
      write(pendingText)
      pendingText = ""
      // Without this, stdin never sees EOF: wl-copy blocks waiting for more
      // input instead of forking to serve the clipboard, and since a Process
      // that hasn't exited can't be restarted, every copy after the first
      // one in a session silently does nothing.
      stdinEnabled = false
    }
  }

  Process {
    id: clipboardHashProcess
    command: ["sha256sum"]
    stdinEnabled: true
    property string pendingText: ""
    onStarted: {
      write(pendingText)
      pendingText = ""
      // Same reasoning as copyProcess — sha256sum reads until EOF before
      // printing anything; without closing stdin it hangs forever and the
      // clipboard auto-clear timer never fires.
      stdinEnabled = false
    }
    stdout: StdioCollector {
      id: clipboardHashStdout
      waitForEnd: true
      onStreamFinished: {
        // "sha256sum" reading from stdin (no filename) prints "<hash>  -".
        root.clipboardHash = String(clipboardHashStdout.text).trim().split(/\s+/)[0] || ""
        clipboardClearTimer.restart()
      }
    }
  }

  Timer {
    id: clipboardClearTimer
    interval: 45000
    repeat: false
    onTriggered: {
      clipboardCheckProcess.command = ["bash", "-c", "wl-paste --no-newline 2>/dev/null | sha256sum | cut -d' ' -f1"]
      clipboardCheckProcess.running = true
    }
  }

  Process {
    id: clipboardCheckProcess
    stdout: StdioCollector {
      id: clipboardCheckStdout
      waitForEnd: true
      onStreamFinished: {
        var currentHash = String(clipboardCheckStdout.text).trim()
        if (root.clipboardHash !== "" && currentHash === root.clipboardHash) {
          Quickshell.execDetached(["wl-copy", "--clear"])
        }
        root.clipboardHash = ""
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return root.summary }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    dimmed: root.phase !== "ready"
    tooltipText: "Vaultez: " + root.summary
    iconComponent: Component {
      Item {
        VaultezIcon {
          anchors.centerIn: parent
          iconSize: Style.space(14)
          color: root.foreground
          opacity: root.phase === "ready" ? 1.0 : 0.6
        }
      }
    }
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: filterField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Vaultez"
            meta: root.summary.toUpperCase()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.phase === "ready" ? 1.0 : 0.5
            iconComponent: Component {
              VaultezIcon {
                iconSize: Style.font.display
                color: root.foreground
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            PanelActionButton {
              visible: root.viewLevel !== "companies"
              iconText: ""
              tooltipText: "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.goBack()
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width - (root.viewLevel !== "companies" ? Style.space(30) : 0)
              text: root.breadcrumb
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
            }
          }

          TextField {
            id: filterField
            width: parent.width
            placeholderText: "Filter " + root.viewLevel + "…"
            foreground: root.foreground
            Keys.onEscapePressed: root.handleEscape()
          }

          Text {
            textFormat: Text.PlainText
            visible: root.errorText !== "" && root.phase === "error"
            width: parent.width
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.phase === "not-installed"
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "vaultez CLI not found" + (root.vaultezPath !== "vaultez" ? " at " + root.vaultezPath : "") + ". Install it to use this plugin."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              text: "Install"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openInstallTerminal()
            }
          }

          Column {
            visible: root.phase === "not-authenticated"
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "You're not logged in to Vaultez."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              text: "Log In"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openLoginTerminal()
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Don't have an account? Create one at vaultez.app"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSignup()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.phase === "loading"
            width: parent.width
            text: "Loading…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            visible: root.phase === "ready" && root.currentRows.length === 0
            width: parent.width
            text: root.viewLevel === "companies" ? "No companies found."
              : root.viewLevel === "projects" ? "No projects in " + (root.activeCompany ? root.activeCompany.name : "") + "."
              : "No secrets in " + (root.activeProject ? root.activeProject.name : "") + "."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.phase === "ready" && root.currentRows.length > 0 && root.displayRows.length === 0
            width: parent.width
            text: "No matches for “" + (filterField ? filterField.text : "") + "”."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: root.phase === "ready" && root.displayRows.length > 0
            width: parent.width
            foreground: root.foreground
          }

          Column {
            visible: root.phase === "ready" && root.viewLevel !== "secrets"
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.viewLevel === "secrets" ? [] : root.displayRows
              ListRow {
                required property var modelData
                width: parent.width
                foreground: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                rowName: modelData.name || ""
                rowMeta: modelData.role || ""
                onActivated: root.viewLevel === "companies" ? root.enterCompany(modelData) : root.enterProject(modelData)
              }
            }
          }

          Column {
            visible: root.phase === "ready" && root.viewLevel === "secrets"
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.viewLevel === "secrets" ? root.displayRows : []
              SecretRow {
                required property var modelData
                width: parent.width
                foreground: root.foreground
                dim: root.dim
                urgent: root.urgent
                fontFamily: root.fontFamily
                secretName: modelData.name || ""
                secretValue: modelData.value || ""
                revealed: root.revealedNames[modelData.name] === true
                onToggleReveal: root.toggleReveal(modelData.name)
                onCopy: root.copySecret(modelData.value)
              }
            }
          }
        }
      }
    }
  }

  component ListRow: CursorSurface {
    id: row
    property string rowName: ""
    property string rowMeta: ""
    property color dim: Color.foreground
    property string fontFamily: Style.font.family
    signal activated()

    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: mouse.containsMouse

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: row.rowName
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        visible: row.rowMeta !== ""
        text: row.rowMeta
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component SecretRow: CursorSurface {
    id: srow
    property string secretName: ""
    property string secretValue: ""
    property bool revealed: false
    property color dim: Color.foreground
    property color urgent: Color.foreground
    property string fontFamily: Style.font.family
    signal toggleReveal()
    signal copy()

    implicitHeight: srowContent.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: srowMouse.containsMouse

    MouseArea {
      id: srowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    RowLayout {
      id: srowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: srow.secretName
          color: srow.foreground
          font.family: srow.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: srow.revealed ? srow.secretValue : Model.maskedValue()
          color: srow.dim
          font.family: srow.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: srow.revealed ? "" : ""
        tooltipText: srow.revealed ? "Hide value" : "Reveal value"
        foreground: srow.foreground
        fontFamily: srow.fontFamily
        onClicked: srow.toggleReveal()
      }

      PanelActionButton {
        iconText: ""
        tooltipText: "Copy to clipboard"
        foreground: srow.foreground
        fontFamily: srow.fontFamily
        onClicked: srow.copy()
      }
    }
  }
}
