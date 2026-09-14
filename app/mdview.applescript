-- px0 Markdown -- a Finder droplet that opens .md files in px0.
-- Finder hands files to an app via Apple Events, not argv, so this needs a
-- real `on open` handler; a shell script in an .app bundle would never see
-- the path. install.sh compiles this with osacompile.

on open theFiles
	repeat with f in theFiles
		do shell script "__MDVIEW__ " & quoted form of (POSIX path of f) & " >/dev/null 2>&1"
	end repeat
end open

on run
	display dialog "px0 Markdown Viewer" & return & return & ¬
		"Right-click a .md file and choose Open With to view it in px0." ¬
		buttons {"OK"} default button "OK" with icon note
end run
