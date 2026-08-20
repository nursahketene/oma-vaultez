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

  function startFetch(level, extraArgs) {
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
    root.navStack = root.navStack.concat([pushFrame()])
    root.activeCompany = company
    root.activeProject = null
    root.viewLevel = "projects"
    root.projects = []
    if (filterField) filterField.text = ""
    startFetch("projects", ["--company=" + company.name, "--projects"])
  }

  function enterProject(project) {
    root.navStack = root.navStack.concat([pushFrame()])
    root.activeProject = project
    root.viewLevel = "secrets"
    root.secrets = []
    root.revealedNames = ({})
    if (filterField) filterField.text = ""
    startFetch("secrets", ["--company=" + root.activeCompany.name, "--project=" + project.name])
  }

  function goBack() {
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

  function copySecret(value) {
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(String(value || "")) + " | wl-copy"])
  }

  function handleEscape() {
    if (filterField && filterField.text !== "") { filterField.text = ""; return }
    if (root.viewLevel !== "companies") { root.goBack(); return }
    root.close()
  }

  function openInstallTerminal() {
    var command = "gem install vaultez-cli; exec \"${SHELL:-/bin/bash}\""
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
    resetNavigation()
    root.phase = "loading"
    root.errorText = ""
    if (!preflightProcess.running) preflightProcess.running = true
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
          root.startFetch("companies", ["--companies"])
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
    text: ""
    dimmed: root.phase !== "ready"
    tooltipText: "Vaultez: " + root.summary
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
              Text {
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
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
            visible: root.phase === "loading"
            width: parent.width
            text: "Loading…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
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
        Layout.fillWidth: true
        text: row.rowName
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
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
          Layout.fillWidth: true
          text: srow.secretName
          color: srow.foreground
          font.family: srow.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
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
