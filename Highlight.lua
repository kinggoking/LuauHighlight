export type HighlighterColors = { [string]: Color3 }

export type TextObject = TextLabel | TextBox

export type HighlightProps = {
	textObject: TextObject,
	src: string?,
	forceUpdate: boolean?,
	lexer: Lexer?,
	customLang: { [string]: string }?
}

export type Lexer = {
	scan: (src: string) -> () -> (string, string),
	navigator: () -> any,
	finished: boolean?,
}

export type Highlighter = {
	defaultLexer: Lexer,
	setTokenColors: (colors: HighlighterColors?) -> (),
	highlight: (props: HighlightProps) -> (() -> ())?,
	refresh: () -> (),
}

export type ObjectData = {
	Text: string,
	Labels: { TextLabel },
	Lines: { string },
	Lexer: Lexer?,
	CustomLang: { [string]: string }?,
}

local function SanitizeRichText(s: string): string
	return string.gsub(
		string.gsub(string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;"),
		"'",
		"&apos;"
	)
end

local function SanitizeTabs(s: string): string
	return string.gsub(s, "\t", "    ")
end

local function SanitizeControl(s: string): string
	return string.gsub(s, "[\0\1\2\3\4\5\6\7\8\11\12\13\14\15\16\17\18\19\20\21\22\23\24\25\26\27\28\29\30\31]+", "")
end

local TokenColors: HighlighterColors = {
	["background"] = Color3.fromRGB(47, 47, 47),
	["iden"] = Color3.fromRGB(234, 234, 234),
	["keyword"] = Color3.fromRGB(248, 109, 124),
	["builtin"] = Color3.fromRGB(132, 214, 247),
	["string"] = Color3.fromRGB(196, 255, 193),
	["number"] = Color3.fromRGB(255, 198, 0),
	["comment"] = Color3.fromRGB(140, 140, 155),
	["operator"] = Color3.fromRGB(255, 239, 148),
	["custom"] = Color3.fromRGB(119, 122, 255),
}
local ColorFormatter: { [Color3]: string } = {}
local LastData: { [TextObject]: ObjectData } = {}
local Cleanups: { [TextObject]: () -> () } = {}

local Highlighter = {
	defaultLexer = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiBiRiK/highlighter/main/Lexer"))(),
	defaultLang = loadstring(game:HttpGet(""))()
}

function Highlighter.highlight(Editor:Instance,Lines:Instance)
	local lines = Lines
	local textObject = Editor
	local src = SanitizeTabs(SanitizeControl(textObject.Text))
	local lexer = Highlighter.defaultLexer
	local customLang = Highlighter.defaultLang
	local forceUpdate = true
	local Lines = 1
	src:gsub("\n",function() Lines = ' ' ..Lines+1 end)
	local LinesText = ""
	for i = 1,Lines do
		LinesText = LinesText..i.."\n"
	end 
	lines.Text = LinesText
	-- Avoid updating when unnecessary
	local data = LastData[textObject]
	if data == nil then
		data = {
			Text = "",
			Labels = {},
			Lines = {},
			Lexer = lexer,
			CustomLang = customLang,
		}
		LastData[textObject] = data
	elseif forceUpdate ~= true and data.Text == src then
		return
	end

	local lineLabels = data.Labels
	local previousLines = data.Lines

	data.Lines = lines
	data.Text = src
	data.Lexer = lexer
	data.CustomLang = customLang

	-- Ensure valid object properties
	textObject.RichText = false
	textObject.Text = src
	textObject.TextXAlignment = Enum.TextXAlignment.Left
	textObject.TextYAlignment = Enum.TextYAlignment.Top
	textObject.BackgroundColor3 = TokenColors.background
	textObject.TextColor3 = TokenColors.iden
	textObject.TextTransparency = 0.5

	-- Build the highlight labels
	local lineFolder = textObject:FindFirstChild("SyntaxHighlights")
	if lineFolder == nil then
		local newLineFolder = Instance.new("Folder")
		newLineFolder.Name = "SyntaxHighlights"
		newLineFolder.Parent = textObject

		lineFolder = newLineFolder
	end

	-- Add a cleanup handler for this textObject
	local cleanup = Cleanups[textObject]
	if not cleanup then
		local connections: { RBXScriptConnection } = {}
		local function newCleanup()
			for _, label in ipairs(lineLabels) do
				label:Destroy()
			end
			table.clear(lineLabels)
			lineLabels = nil

			LastData[textObject] = nil
			Cleanups[textObject] = nil

			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			connections = nil
		end
		Cleanups[textObject] = newCleanup
		cleanup = newCleanup

		table.insert(
			connections,
			textObject.AncestryChanged:Connect(function()
				if textObject.Parent then
					return
				end

				cleanup()
			end)
		)
		table.insert(
			connections,
			textObject:GetPropertyChangedSignal("TextBounds"):Connect(function()
				Highlighter.highlight({
					textObject = textObject,
					forceUpdate = true,
					lexer = lexer,
					customLang = customLang,
				})
			end)
		)
		table.insert(
			connections,
			textObject:GetPropertyChangedSignal("Text"):Connect(function()
				Highlighter.highlight({
					textObject = textObject,
					lexer = lexer,
					customLang = customLang,
				})
			end)
		)
		table.insert(
			connections,
			textObject:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				Highlighter.highlight({
					textObject = textObject,
					forceUpdate = true,
					lexer = lexer,
					customLang = customLang,
				})
			end)
		)
	end

	-- Shortcut empty labels
	if src == "" then
		for l=1, #lineLabels do
			if lineLabels[l].Text == "" then continue end
			lineLabels[l].Text = ""
		end
		return cleanup
	end

	-- Wait for TextBounds to be non-NaN and non-zero because Roblox
	local textBounds = textObject.TextBounds
	while (textBounds.Y ~= textBounds.Y) or (textBounds.Y < 1) do
		task.wait()
		textBounds = textObject.TextBounds
	end

	if LastData[textObject] == nil then
		-- Got cleaned up while we were waiting
		return cleanup
	end

	local textHeight = textBounds.Y / Lines * textObject.LineHeight

	local richText, index, lineNumber = table.create(5), 0, 1
	for token: string, content: string in lexer.scan(src) do
		local Color =
			if customLang and customLang[content] then
				TokenColors["custom"]
			else
				TokenColors[token] or TokenColors["iden"]

		local tokenLines = string.split(SanitizeRichText(content), "\n")

		for l, line in ipairs(tokenLines) do
			-- Find line label
			local lineLabel = lineLabels[lineNumber]
			if not lineLabel then
				local newLabel = Instance.new("TextLabel")
				newLabel.Name = "Line_" .. lineNumber
				newLabel.RichText = true
				newLabel.BackgroundTransparency = 1
				newLabel.Text = ""
				newLabel.TextXAlignment = Enum.TextXAlignment.Left
				newLabel.TextYAlignment = Enum.TextYAlignment.Top
				newLabel.Parent = lineFolder
				lineLabels[lineNumber] = newLabel
				lineLabel = newLabel
			end

			-- Align line label
			lineLabel.TextColor3 = TokenColors["iden"]
			lineLabel.Font = textObject.Font
			lineLabel.TextSize = textObject.TextSize
			lineLabel.Size = UDim2.new(1, 0, 0, math.ceil(textHeight))
			lineLabel.Position = UDim2.fromScale(0, textHeight * (lineNumber - 1) / textObject.AbsoluteSize.Y)

			-- If multiline token, then set line & move to next
			if l > 1 then
				if forceUpdate or lines[lineNumber] ~= previousLines[lineNumber] then
					-- Set line
					lineLabels[lineNumber].Text = table.concat(richText)
				end
				-- Move to next line
				lineNumber += 1
				index = 0
				table.clear(richText)
			end

			-- If changed, add token to line
			if forceUpdate or lines[lineNumber] ~= previousLines[lineNumber] then
				index += 1
				-- Only add RichText tags when the color is non-default and the characters are non-whitespace
				if Color ~= TokenColors["iden"] and string.find(line, "[%S%C]") then
					richText[index] = string.format(ColorFormatter[Color], line)
				else
					richText[index] = line
				end
			end
		end
	end

	-- Set final line
	if richText[1] and lineLabels[lineNumber] then
		lineLabels[lineNumber].Text = table.concat(richText)
	end

	-- Clear unused line labels
	for l=lineNumber+1, #lineLabels do
		if lineLabels[l].Text == "" then continue end
		lineLabels[l].Text = ""
	end

	return cleanup
end

function Highlighter.refresh(): ()
	-- Rehighlight existing labels using latest colors
	for textObject, data in pairs(LastData) do
		for _, lineLabel in ipairs(data.Labels) do
			lineLabel.TextColor3 = TokenColors["iden"]
		end

		Highlighter.highlight({
			textObject = textObject,
			forceUpdate = true,
			src = data.Text,
			lexer = data.Lexer,
			customLang = data.CustomLang,
		})
	end
end

function Highlighter.setTokenColors(colors: HighlighterColors)
	for token, color in colors do
		TokenColors[token] = color
		ColorFormatter[color] = string.format(
			'<font color="#%.2x%.2x%.2x">',
			color.R * 255,
			color.G * 255,
			color.B * 255
		) .. "%s</font>"
	end

	Highlighter.refresh()
end
Highlighter.setTokenColors(TokenColors)

return Highlighter :: Highlighter
