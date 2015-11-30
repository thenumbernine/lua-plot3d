#!/usr/bin/env luajit
--[[ invoke with gnuplot-formatted files

data will be in the form of "x y [z]"
and plotted accordingly

--]]
local args = {...}

require 'ext'

local defaultValue = 0

local files = table()
local getarg = coroutine.wrap(function() for _,arg in ipairs(args) do coroutine.yield(arg) end end)
local arg
while true do
	arg = getarg()
	if not arg then break end
	if arg == 'using' then
		files:last().cols = getarg():split':':map(function(x) return tonumber(x) end)
	elseif arg == 'title' then
		files:last().title = getarg()
	else
		files:insert{name=arg}
	end
end

local dataForFile = {}
local graphs = table()
for _,fi in ipairs(files) do
	local fn = fi.name
	if not io.fileexists(fn) then
		io.stderr:write('file '..tostring(fn)..' does not exist\n')
		io.stderr:flush()
	else
		local g = dataForFile[fn]
		if not g then
			g = {}
			dataForFile[fn] = g
			local eols = {}
			
			local j = 1
			for l in io.lines(fn) do
				if l:sub(1,1) ~= '#' then	-- skip comments
					local ws = l:trim():split('%s+')
					if #ws == 1 and ws[1] == '' then
						-- then this is a row separator in splot
						table.insert(eols, j-1)
					else
						for i=1,#ws do
							if not g[i] then g[i] = table() end
							g[i][j] = tonumber(ws[i])
						end
						j = j + 1
					end
				end
			end
			if #eols > 0 then g.eols = eols end
			
			local jmax = j
			for i=1,#g do
				local gi = g[i]
				for j=1,jmax do
					gi[j] = gi[j] or defaultValue
				end
			end
		end

		local title = fi.title or fn

		-- make sure title is unique
		if graphs[title] then
			local test
			for i=1,1000 do
				test = title..'('..i..')'
				if not graphs[test] then break end
			end
			title = test
		end

		graphs[title] = setmetatable(table(g), nil)	-- soft copy, so don't mess with data ...
		graphs[title].enabled = true
		graphs[title].cols = fi.cols
	end
end

local plot3d = require 'plot3d'
plot3d(graphs)
