# px0-md-open

Open a Markdown file from Finder, read it in [px0](https://px0.ai), and have the
server shut itself down when you close the tab.

px0 is a lovely read-only Markdown viewer, but it is a *server*: you point it at
a directory, it serves a UI, and it keeps running until you stop it. That is a
poor fit for "I just want to read this one file." This wraps it so opening a
`.md` feels like opening a document.

```
right-click notes.md -> Open With -> px0 Markdown
   |
   +-- workspace root = git top-level (else the file's directory)
   +-- a px0 already serving that root?  reuse it : start one on a free port
   +-- hand the URL to your browser
   +-- watch; when the last tab on that port closes, stop px0
```

Nothing is written into your repositories. State lives in
`~/.local/state/mdview/`.

## Install

Requires macOS and [px0](https://px0.ai) on your `PATH`.

```sh
git clone https://github.com/nan-bit/px0-md-open.git && cd px0-md-open
./install.sh
```

Then right-click any `.md` → **Open With** → **px0 Markdown**. There is also a
CLI:

```sh
mdview path/to/notes.md
mdview --stop-all          # stop every server this tool started
```

`install.sh` does not take over your `.md` association — it registers as an
*alternate* handler, so whatever you use today stays the default. To go further:

```sh
./install.sh --default     # needs `brew install duti`
```

or Finder → Get Info on a `.md` → Open With → **Change All**.

**macOS will prompt once** for permission to control your browser. Allow it; the
shutdown watcher asks the browser which tabs are open, and without that
permission the server will not stop on its own.

## Configuration

Optional, `~/.config/mdview/config`:

```sh
MDVIEW_BROWSER="Google Chrome"   # Brave Browser, Safari, Arc, Vivaldi, ...
MDVIEW_IDLE=10                   # seconds after the last tab closes
MDVIEW_GRACE=30                  # seconds to wait for the first tab
MDVIEW_POLL=3                    # seconds between tab checks
```

## What to expect

**You land on the workspace tree, not the file.** px0 has no deep-link: it
rejects a file argument (`px0 notes.md` → `not a directory`) and its UI never
reads the URL, so `/?path=…` and `/#notes.md` all just render the root view.
Use px0's file finder to jump to the file. This is the deliberate tradeoff —
the alternative was patching px0's frontend, which means maintaining a fork and
rebuilding on every px0 release. Using px0 as shipped means upstream keeps
maintaining it.

**No live reload.** px0 has no file watcher and no websocket. Editing a file and
hitting ⌘R shows the new content (it is read from disk per request), but a
*newly created* file will not appear in the tree until px0 reindexes.

**Language servers are off** (`-no-lsp`). This is a read-only viewer, and it
stops tools like clangd from writing a `.cache/` directory into your project
when a workspace happens to contain code.

## Why tabs, not sockets

The obvious way to detect "the tab is closed" is to count established
connections to the port — px0's UI polls `/api/metrics` every 2.5s, so an open
tab holds a live socket.

**This does not work, and the failure is silent.** Chrome keeps sockets in a
reuse pool well after a tab is gone. Measured: tab closed, `lsof` still reported
an established connection, and the server stayed up indefinitely. A synthetic
client that closes its socket immediately passes this test, which is exactly how
the bug got written in the first place.

So `mdview-tabcount` asks the browser directly, via AppleScript, how many tabs
are open on that port — guarded by a System Events check so it never launches a
browser just to ask the question. That correctly covers both closing the tab and
quitting the browser entirely.

If you are tempted to replace the AppleScript with socket counting: please
don't, or at least test it against a real browser rather than a script.

## Layout

| Path | Purpose |
| --- | --- |
| `bin/mdview` | resolve root, reuse-or-start px0, supervise shutdown |
| `bin/mdview-tabcount` | ask the browser how many tabs are on a port |
| `app/mdview.applescript` | the Finder droplet source |
| `install.sh` / `uninstall.sh` | install, register, remove |
| `test/smoke.sh` | 13 tests, no browser required |

The droplet has to be AppleScript: Finder delivers files to an app through
Apple Events, not `argv`, so a shell script in an `.app` bundle would never
receive the path. `install.sh` compiles it with `osacompile` and bakes in the
absolute path to `mdview`, because `do shell script` runs with a minimal `PATH`.

## Tests

```sh
./test/smoke.sh
```

Stubs the browser two ways — `open` is shadowed on `PATH`, and the tab counter
is a fake whose answer is read from a file — so the "tab closed" transition can
be driven deterministically without a real window. Exits `77` if px0 is absent.

## Uninstall

```sh
./uninstall.sh            # remove app + scripts
./uninstall.sh --purge    # also remove state and config
```

px0 itself is never touched.

## License

MIT
