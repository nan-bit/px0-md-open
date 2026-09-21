# px0-md-open

Open a Markdown file — or a whole folder — from Finder, read it in
[px0](https://px0.ai), and have the server clean itself up once you are done
with it.

px0 is a lovely read-only Markdown viewer, but it is a *server*: you point it at
a directory, it serves a UI, and it keeps running until you stop it. That is a
poor fit for "I just want to read this one file." This wraps it so opening a
`.md` feels like opening a document, and opening a folder feels like opening a
workspace you can browse from the tab.

```
right-click notes.md -> Open With -> px0 Markdown      (or drag a folder on it)
   |
   +-- workspace root = the folder you named, if you named one
   |                    else the folder the file sits in
   +-- a px0 already serving that root -- or containing it?  reuse it
   |                                                      :  start one, free port
   +-- hand the URL to your browser  (+ ?path=<file> on px0 0.1.7+)
   +-- watch; stop px0 once no tab has been on that port for a while
```

Nothing is written into your repositories. State lives in
`~/.local/state/mdview/`.

## Install

Requires macOS and [px0](https://px0.ai) on your `PATH`.

```sh
git clone https://github.com/nan-bit/px0-md-open.git && cd px0-md-open
./install.sh
```

Then right-click any `.md` → **Open With** → **px0 Markdown**. To browse a whole
tree, drag the folder onto the app instead. There is also a CLI:

```sh
mdview path/to/notes.md    # root = the folder it sits in
mdview path/to/folder      # root = that folder, exactly
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
MDVIEW_FILE_ROOT=dir             # dir: a file's root is its folder; git: the repo
MDVIEW_IDLE=1800                 # seconds after the last tab closes
MDVIEW_GRACE=30                  # seconds to wait for the first tab
MDVIEW_POLL=3                    # seconds between tab checks
```

## What to expect

**You land on the file, if px0 is new enough.** px0 0.1.7 reads `?path=` on
load: it opens that file, reveals it in the sidebar, then strips the parameter
back out of the URL. So `mdview notes.md` hands the browser
`http://127.0.0.1:PORT/?path=notes.md` and you arrive on the file, inside the
wider workspace. Older px0 ignores the parameter and shows the root — which is
what this tool did for its whole life before 0.1.7, so nothing breaks, you just
pick the file out of the tree yourself.

There is deliberately no fork of px0's frontend here. Everything below is done
with px0 as shipped, which is why upstream gets to keep maintaining it.

**You get the folder, not the repo.** `mdview ~/repo/docs` roots px0 at
`docs/`, even though `~/repo` is a git top-level — you asked for that directory,
so that is the tree you get, and the sidebar is not buried under the rest of the
repo. A file is read the same way: `mdview ~/repo/docs/a.md` roots at `docs/`,
because the folder a file sits in is the closest thing to a stated intent it
has. From there, clicking into sub-directories is px0's own doing; it expands
them lazily over `/api/tree?dir=…`.

Set `MDVIEW_FILE_ROOT=git` if you would rather a file climb to the git
top-level and give you the whole repository in the sidebar. A directory is
unaffected either way — a directory is always taken at its word.

**An open workspace swallows what falls inside it.** If a live server's root
already contains the root you are asking for, `mdview` reuses it instead of
starting a second px0 underneath. Open `~/notes`, then double-click
`~/notes/proj/a.md`, and you land back in the `~/notes` tab rather than getting
a new server rooted at `proj/`. The deepest containing root wins.

**The server outlives the tab by half an hour.** `MDVIEW_IDLE` defaults to 1800
seconds: close the tab, come back within thirty minutes, and the workspace is
still there on the same port. Set it to `10` for the old one-shot behaviour, or
run `mdview --stop-all` when you want the processes gone now. The first tab
still has to appear within `MDVIEW_GRACE` (30s) or the server gives up — that
guards against a browser that never opened, not against you walking away.

**No live reload.** px0 has no file watcher and no websocket. Editing a file and
hitting ⌘R shows the new content (it is read from disk per request), but a
*newly created* file will not appear in the tree until px0 reindexes.

**Language servers are off** (`-no-lsp`). This is a read-only viewer, and it
stops tools like clangd from writing a `.cache/` directory into your project
when a workspace happens to contain code.

**So is the editing agent** (`-no-agent`), and telemetry (`-no-telemetry`),
where px0 supports them. Since 0.1.7 px0 can hand a file to a coding harness
and edit it; that is a fine thing for px0 to do and the wrong thing to get from
double-clicking a file you meant to read. Both flags are passed only if
`px0 --help` advertises them, because an unknown flag is fatal and this tool
should keep working against whatever px0 you have.

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
| `test/smoke.sh` | 23 tests, no browser required |

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
