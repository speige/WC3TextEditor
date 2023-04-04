# Warcraft III TextEditor (Custom In-Game Control for Map Makers)

https://www.youtube.com/@ai-gamer

This is a custom control for Warcraft III Modding & Map Making. It renders a multi-line editable text area so the user can type long-form text. This might be useful for embedding a Console Terminal in your app to allow users to enter complex commands.

Warcraft III has similar built-in controls, such as EditBox and TextArea, however, they have limitations. EditBox can only show 1 line of text. TextArea is multi-line but readonly. 

MIT License - Feel free to use/modify the code any way you want.

Code written in LUA

Installation: Copy/Paste contents of TextEditor.lua and TextEditor.toc into your map

Usage:
```
	--Create
	TextEditor:Constructor()
	
	--Destroy (memory cleanup)
	TextEditor:Dispose()
```

Public Utility Fields/Methods:
```
	TextEditor.CursorChar
	TextEditor.TabWidth
	TextEditor.TextChangedTrigger
	TextEditor:IsVisible()
	TextEditor:SetVisible(boolean)
	TextEditor:GetText()
	TextEditor:SetText(text)
	TextEditor:SetPositionAndSize(x, y, width, height) --FullScreen is 0, 1, 1, 1
```

Note: Lua doesn't distinguish between public/private class properties. If a field in code is not listed in the documentation, it should be assumed to be private, but you may still use it at your own risk.

Supported Shortcuts (matches typical text editor functionality):

	* HOME / END
	* CTRL+HOME / CTRL+END
	* ALT+UP / ALT+DOWN
	* CTRL+LEFT / CTRL+RIGHT
	* CTRL+Z / CTRL+Y
	* CTRL+DEL / CTRL+BACKSPACE
	* CTRL+X / CTRL+C (Affects entire line, since selection has not been coded)
	* CTRL+V
	
Limitations:

	Due to limitations of the Warcraft III engine and APIs, certain features have not been coded until a workaround is found
	* Sync with OS Clipboard
	* Don't show chat window when Enter key is pressed (partially fixed)
	* Don't zoom camera when PageUp/Down keys are pressed (partially fixed)
	* Don't attempt to create unit group when SHIFT+# is pressed
	* Auto-scroll TextArea slider to keep cursor visible

Help is welcome and appreciated!
Suggested features for future PRs:

	* Support CapsLock
	* Allow text selection (shift+arrows or mouse)
	* PageUp/PageDown
	
Possible Uses:

	* In combination with Lua Load() function, execute arbitrary code at runtime