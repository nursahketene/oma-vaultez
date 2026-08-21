# Vaultez for Omarchy

Get your [Vaultez](https://vaultez.app) secrets from the Omarchy menu bar, sorted
by company and project.

![Vaultez plugin showing a company's secrets](preview.png)

## Installation

You'll need the `vaultez-cli` gem installed, at least version 0.3.0 (earlier
versions had a config-file-permissions bug and a CLI flag that could expose
your session token to other local users — this plugin hands that CLI your
saved session and every secret it returns, so don't install an older version):

```bash
gem install vaultez-cli --version '>= 0.3.0'
```

Then add it as a plugin:

```bash
omarchy plugin add https://github.com/nursahketene/oma-vaultez.git --enable
```

## Removal

```bash
omarchy plugin remove app.vaultez
```

This disables the plugin and removes it from `~/.config/omarchy/plugins/`
(a timestamped backup is kept alongside the other plugin directories). To
also remove the CLI: `gem uninstall vaultez-cli`.

## Usage

Click the key icon in the bar.

- **Not logged in?** Click "Log In" — this opens a terminal running `vaultez login`
  (email, password, and your TOTP code, same as running it yourself). Reopen the
  panel once you're done. Don't have an account yet? There's a link to sign up at
  vaultez.app right below the button.
- **CLI not found?** Click "Install" — opens a terminal running
  `gem install vaultez-cli --version '>= 0.3.0'`.
- Click a company, then a project, to see its secrets. Secret values are masked by
  default — click a secret to reveal it, or use the copy button to copy the value to
  your clipboard without revealing it on screen.
- Type in the filter box at any level to narrow the list.

## Settings

If `vaultez` isn't on your `$PATH` (for example, installed under a Ruby version
manager like `rbenv`, `rvm`, or `mise`), open the plugin's settings and set
"Path to vaultez binary" to wherever `gem install` actually put it — `which vaultez`
after installing will tell you.

## How it works

The plugin shells out to `vaultez fetch ... --json` for data and reuses whatever
session `vaultez login` already created (`~/.vaultez/config.yml`) — there's no
separate login state to manage. Every secret fetch is still logged as an activity in
the Vaultez web UI, same as using the CLI directly.

## License

MIT
