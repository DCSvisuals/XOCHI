-- XOCHI — bundled TUI entry point
-- Shell scripts are packaged under:
-- XOCHI.app/Contents/Resources/XOCHI/

on run
	try
		set applicationPath to POSIX path of (path to me)
		set launcherPath to applicationPath & "Contents/Resources/XOCHI/Xochi.sh"

		-- quoted form protects paths containing spaces or apostrophes.
		-- A login shell supplies the user's normal command-line environment.
		set launcherCommand to "/bin/bash " & quoted form of launcherPath
		set terminalCommand to "/bin/zsh -l -c " & quoted form of launcherCommand

		tell application "Terminal"
			do script terminalCommand
			activate
		end tell

	on error errorMessage number errorNumber
		display alert "XOCHI could not open" message ¬
			(errorMessage & return & return & "Error: " & errorNumber) as critical
	end try
end run
