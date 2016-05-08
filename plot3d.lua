local ffi = require 'ffi'
local gl = require 'ffi.OpenGL'
local glu = require 'ffi.glu'
local sdl = require 'ffi.sdl'
local GLApp = require 'glapp'
local glCallOrRun = require 'gl.call'
local vec2 = require 'vec.vec2'
local vec3 = require 'vec.vec3'
local vec4 = require 'vec.vec4'
local vec4f = require 'ffi.vec.vec4f'
local Quat = require 'vec.quat'
local box2 = require 'vec.box2'
local GUI = require 'gui'

local resetView

local viewRot = Quat(math.sqrt(.5),0,0,-math.sqrt(.5))
local leftButtonDown
local viewDist = 5
local zNear = 1
local zFar = 1000
local tanFovX = .5
local tanFovY = .5

local quad = {{0,0}, {1,0}, {1,1}, {0,1}}

--[[
graphs = {
	[name] = {
		[enabled = true,]	-- optional
		{x1,x2,...},
		{y1,y2,...},
		{z1,z2,...},
		...
	}
--]]
local function plot3d(graphs, numRows, fontfile)

	local colors = {
		vec3(1,0,0),
		vec3(1,1,0),
		vec3(0,1,0),
		vec3(0,1,1),
		vec3(.3,.3,1),
		vec3(1,.2,1),
	}

	for name,graph in pairs(graphs) do
		if not graph.color then
			local h = math.random() * #colors + 1
			local hi = math.floor(h)
			local hii = hi % #colors + 1
			local f = h - hi
			local c = colors[hi] * f + colors[hii] * (1 - f)
			-- add luminance
			local s = .1
			c = c * (1 - s) + vec3(1,1,1) * s
			--c = c / math.max(unpack(c))
			graph.color = c
		end
		if not graph.cols then
			graph.cols = {1,2,3}
		end
		local length
		graph.mins = {}
		graph.maxs = {}
		for i,data in ipairs(graph) do
			if not length then
				length = #data
			else
				assert(#data == length, "data mismatched length, found "..#data.." expected "..length)
			end
			for _,value in ipairs(data) do
				if math.isfinite(value) then
					if not graph.mins[i] then graph.mins[i] = value else graph.mins[i] = math.min(graph.mins[i], value) end
					if not graph.maxs[i] then graph.maxs[i] = value else graph.maxs[i] = math.max(graph.maxs[i], value) end
				end
			end
		end
	
		print('mins', unpack(graph.mins))
		print('maxs', unpack(graph.maxs))
	
		graph.length = length
	end

	local viewpos = vec2()
	local viewsize = vec2(1,1)
	local leftButtonDown = false
	local gui
	local coordText
	local mousepos = vec2()

	local list = {}
	local function redraw()
		if list.id then
			gl.glDeleteLists(1, list.id)
			list.id = nil
		end
	end

	resetView = function()
	
		-- TODO calculate all points and determine the best distance to view them at
		mins = {}
		maxs = {}
		for _,graph in pairs(graphs) do
			if graph.enabled then
				local cols = graph.cols
				for i=1,3 do 
					mins[i] = math.min(mins[i] or graph.mins[cols[i]], graph.mins[cols[i]])
					maxs[i] = math.max(maxs[i] or graph.maxs[cols[i]], graph.maxs[cols[i]])
				end
			end
		end
		if #mins == 0 then mins = {-1,-1,-1} end
		if #maxs == 0 then maxs = {1,1,1} end
	end
	
	resetView()

	local Plot3DApp = class(GLApp)
	function Plot3DApp:initGL(gl,glname)
		if not fontfile or not io.fileexists(fontfile) then
			local home = os.getenv'HOME'
			fontfile = home..'/Projects/lua/plot3d/font.png'
		end
	
		gui = GUI{font=fontfile}
		
		local names = table()
		for name,_ in pairs(graphs) do
			names:insert(name)
		end
		names:sort()
		
		local function colorForEnabled(graph)
			if graph.enabled then
				return graph.color[1], graph.color[2], graph.color[3], 1
			else
				return .4, .4, .4, 1
			end
		end
		
		local Text = require 'gui.widget.text'
		
		coordText = gui:widget{
			class=Text,
			text='',
			parent={gui.root},
			pos={0,0},
			fontSize={2,2}
		}
		
		local y = 1
		local x = 1
		for i,name in ipairs(names) do
			local graph = graphs[name]
			gui:widget{
				class=Text,
				text=name,
				parent={gui.root},
				pos={x,y},
				fontSize={2,2},
				graph=graph,
				fontColor={colorForEnabled(graph)},
				mouseEvent=function(menu,event,x,y)
					if bit.band(event,1) ~= 0 then	-- left press
						graph.enabled = not graph.enabled
						menu:fontColor(colorForEnabled(graph))
						redraw()
					end
				end,
			}
			y=y+2
			
			if numRows and i % numRows == 0 then
				y = 1
				x = x + 10
			end
		end
		
		gl.glClearColor(0,0,0,0)
		--gl.glEnable(gl.GL_DEPTH_TEST)
		gl.glEnable(gl.GL_BLEND)
		gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE)
		
		gl.glEnable(gl.GL_NORMALIZE)

		gl.glLightModelfv(gl.GL_LIGHT_MODEL_AMBIENT, vec4f(0,0,0,0):ptr())
		gl.glLightModelf(gl.GL_LIGHT_MODEL_LOCAL_VIEWER, gl.GL_TRUE)
		gl.glLightModelf(gl.GL_LIGHT_MODEL_TWO_SIDE, gl.GL_TRUE)
		gl.glLightModelf(gl.GL_LIGHT_MODEL_COLOR_CONTROL, gl.GL_SEPARATE_SPECULAR_COLOR)

		gl.glMaterialf(gl.GL_FRONT_AND_BACK, gl.GL_SHININESS, 127)
		gl.glMaterialfv(gl.GL_FRONT_AND_BACK, gl.GL_SPECULAR, vec4f(1,1,1,1):ptr())
		gl.glColorMaterial(gl.GL_FRONT_AND_BACK, gl.GL_DIFFUSE)
		gl.glEnable(gl.GL_COLOR_MATERIAL)

		gl.glLightfv(gl.GL_LIGHT0, gl.GL_SPECULAR, vec4f(1,1,1,1):ptr())
		gl.glLightfv(gl.GL_LIGHT0, gl.GL_POSITION, vec4f(0,0,0,1):ptr())
		gl.glEnable(gl.GL_LIGHT0)
	end
		
	function Plot3DApp:event(event)
		if event.type == sdl.SDL_MOUSEMOTION then
			if leftButtonDown then
				local idx = tonumber(event.motion.xrel)
				local idy = tonumber(event.motion.yrel)
				local magn = math.sqrt(idx * idx + idy * idy)
				local dx = idx / magn
				local dy = idy / magn
				local r = Quat():fromAngleAxis(dy, dx, 0, magn)
				viewRot = (r * viewRot):normalize()
			end
		elseif event.type == sdl.SDL_MOUSEBUTTONDOWN then
			if event.button.button == sdl.SDL_BUTTON_LEFT then
				leftButtonDown = true
			elseif event.button.button == sdl.SDL_BUTTON_WHEELUP then
				viewDist = viewDist - .5
			elseif event.button.button == sdl.SDL_BUTTON_WHEELDOWN then
				viewDist = viewDist + .5
			end
		elseif event.type == sdl.SDL_MOUSEBUTTONUP then
			if event.button.button == sdl.SDL_BUTTON_LEFT then
				leftButtonDown = false
			end
		end
	end
		
	function Plot3DApp:update()
		gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

		local viewWidth, viewHeight = self:size()
		local aspectRatio = viewWidth / viewHeight
		gl.glMatrixMode(gl.GL_PROJECTION)
		gl.glLoadIdentity()
		gl.glFrustum(-zNear * aspectRatio * tanFovX, zNear * aspectRatio * tanFovX, -zNear * tanFovY, zNear * tanFovY, zNear, zFar);

		gl.glMatrixMode(gl.GL_MODELVIEW)
		gl.glLoadIdentity()

		gl.glTranslated(0,0,-viewDist)
		
		local aa = viewRot:toAngleAxis()
		gl.glRotated(aa[4], aa[1], aa[2], aa[3])

		-- position view in center of data
		--gl.glTranslated( -(maxs[1] + mins[1])/2, -(maxs[2] + mins[2])/2, 0)
		
		gl.glColor3d(1,1,1)
		
		
		--[[
		local mx, my = gui:sysSize()
		coordText:pos(mousepos[1] * mx, mousepos[2] * my)
		coordText:setText(
			('%.3e'):format(mousepos[1] * viewbbox.max[1] + (1-mousepos[1]) * viewbbox.min[1])..','..
			('%.3e'):format((1-mousepos[2]) * viewbbox.max[2] + mousepos[2] * viewbbox.min[2])
		)
		--]]

		gl.glEnable(gl.GL_LIGHTING)
		
		gl.glDisable(gl.GL_DEPTH_TEST)
		glCallOrRun(list, function()
			for _,graph in pairs(graphs) do
				local cols = graph.cols
				if graph.enabled then
					gl.glColor4f(graph.color[1], graph.color[2], graph.color[3], .8)
					if graph.eols then
						--[[ line
						for ei=1,#graph.eols do
							local istart = (graph.eols[ei-1] or 0) + 1
							local iend = graph.eols[ei]
							gl.glBegin(gl.GL_LINE_STRIP)
							for i=istart,iend do
								gl.glVertex3d(graph[1][i], graph[2][i], graph[3][i])
							end
							gl.glEnd()
						end
						
						local ofs = 0
						local done = false
						repeat
							gl.glBegin(gl.GL_LINE_STRIP)
							for ei=1,#graph.eols do
								local i = (graph.eols[ei-1] or 0) + 1 + ofs
								if i > graph.eols[ei] then
									done = true
									break
								end
								gl.glVertex3d(graph[1][i], graph[2][i], graph[3][i])
							end
							gl.glEnd()
							ofs = ofs + 1
						until done
						--]]
						-- [[ surface -- assuming consistent-sized offsets
						local indexes = {}
						local vecs = {}
						local qvtx = {{}, {}, {}, {}}
						gl.glBegin(gl.GL_QUADS)
						for basey=1,#graph.eols-2 do
							for basex=1,graph.eols[1]-1 do
								for ofsi,ofs in ipairs(quad) do
									local x = basex + ofs[1]
									local y = basey + ofs[2]
									indexes[ofsi] = (graph.eols[y-1] or 0) + x
								end
								for i,index in ipairs(indexes) do
									vecs[i] = vec3(graph[cols[1]][index], graph[cols[2]][index], graph[cols[3]][index])
									-- position data in center of view
									for j=1,3 do
										vecs[i][j] = (vecs[i][j] - mins[j]) / (maxs[j] - mins[j]) * 2 - 1
									end
								end
								local dx = (vecs[2] - vecs[1] + vecs[3] - vecs[4]) * .5
								local dy = (vecs[4] - vecs[1] + vecs[3] - vecs[2]) * .5
								local n = vec3.cross(dx, dy)
								gl.glNormal3d(n[1], n[2], n[3])
								local bad = false
								for j,i in ipairs(indexes) do
									for k=1,3 do
										local x = graph[cols[k]][i]
										bad = bad or not math.isfinite(x) 
										x = (x - mins[k]) / (maxs[k] - mins[k]) * 2 - 1
										qvtx[j][k] = x
									end
								end
								if not bad then
									for j=1,4 do
										gl.glVertex3d(unpack(qvtx[j]))
									end
								end
							end
						end
						gl.glEnd()
						--]]
					else
						gl.glBegin(gl.GL_POINTS)
						for i=1,graph.length do
							local v = {graph[cols[1]][i], graph[cols[2]][i], graph[cols[3]][i]}
							for j=1,3 do
								v[j] = (v[j] - mins[j]) / (maxs[j] - mins[j]) * 2 - 1
							end
							gl.glVertex3d(unpack(v))
						end
						gl.glEnd()
					end
				end
			end
		end)

		gl.glDisable(gl.GL_LIGHTING)

		gl.glDisable(gl.GL_DEPTH_TEST)
		gl.glPolygonMode(gl.GL_FRONT_AND_BACK, gl.GL_LINE)
		--glCallOrRun(list)
		gl.glPolygonMode(gl.GL_FRONT_AND_BACK, gl.GL_FILL)

		local function drawText3D(pt, text)
			local mv = ffi.new('float[16]')
			local proj = ffi.new('float[16]')
			gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, mv)
			gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, proj)
			pt = vec4(
				mv[0] * pt[1] + mv[4] * pt[2] + mv[8] * pt[3] + mv[12],
				mv[1] * pt[1] + mv[5] * pt[2] + mv[9] * pt[3] + mv[13],
				mv[2] * pt[1] + mv[6] * pt[2] + mv[10] * pt[3] + mv[14],
				mv[3] * pt[1] + mv[7] * pt[2] + mv[11] * pt[3] + mv[15])
			pt = vec4(
				proj[0] * pt[1] + proj[4] * pt[2] + proj[8] * pt[3] + proj[12] * pt[4],
				proj[1] * pt[1] + proj[5] * pt[2] + proj[9] * pt[3] + proj[13] * pt[4],
				proj[2] * pt[1] + proj[6] * pt[2] + proj[10] * pt[3] + proj[14] * pt[4],
				proj[3] * pt[1] + proj[7] * pt[2] + proj[11] * pt[3] + proj[15] * pt[4])
			pt = vec3(pt[1], pt[2], pt[3]) / pt[4]
			for i=1,3 do
				if pt[i] < -1 or pt[i] > 1 then return end
			end
			pt = (pt * .5 + vec3(.5, .5, .5))
			local w,h = gui:sysSize()
			pt[1] = pt[1] * w
			pt[2] = pt[2] * h
			gl.glMatrixMode(gl.GL_PROJECTION)
			gl.glPushMatrix()
			gl.glLoadIdentity()
			gl.glOrtho(0, w, 0, h, -1, 1) 
			gl.glMatrixMode(gl.GL_MODELVIEW)
			gl.glPushMatrix()
			gl.glLoadIdentity()
			gui.font:draw{
				pos = pt,
				fontSize = {1,-1},
				text = text,
				size = {w,h},
			}
			gl.glMatrixMode(gl.GL_PROJECTION)
			gl.glPopMatrix()
			gl.glMatrixMode(gl.GL_MODELVIEW)
			gl.glPopMatrix()
		end

		local function drawLine(args)
			gl.glBegin(gl.GL_LINES)
			gl.glVertex3f(unpack(args.p1))
			gl.glVertex3f(unpack(args.p2))
			gl.glEnd()
		end
		
		local function drawTicks(args)
			local ticks = args.ticks or 8
			gl.glColor3f(1,1,1)
			local d = args.p2 - args.p1
			for i=0,ticks do
				local center = args.p1 + d*(i/ticks)
				gl.glBegin(gl.GL_LINES)
				gl.glVertex3f(unpack(center + args.perp*.1))
				gl.glVertex3f(unpack(center - args.perp*.1))
				gl.glEnd()

				local v = (args.to - args.from) * i/ticks + args.from
				drawText3D(args.perp*.1 + center, tostring(v))
			end
		end
		
		-- project view -z
		local right = viewRot:conjugate():xAxis()
		local fwd = -viewRot:conjugate():zAxis()

		-- draw a box around it
		-- draw tickers along each axis at specific spacing ... 5 tics per axii? 
		local v = vec3()
		v[1] = (right[1] < 0) and -1 or 1
		v[2] = (right[2] < 0) and -1 or 1
		v[3] = -1

		for j=1,3 do
			local from = mins[j]
			local to = maxs[j]
			if v[j] > 0 then from,to = to,from end
			local fromPt = vec3(unpack(v))
			local toPt = vec3(unpack(v))
			toPt[j] = -toPt[j]
			local axis = vec3(0,0,0)
			axis[j] = 1
			drawTicks{
				p1=fromPt,
				p2=toPt,
				perp=fwd:cross(axis),
				from=from,
				to=to,
			}
		end
		
		local bottomVtxs = {
			vec3(-1,-1,-1),
			vec3(1,-1,-1),
			vec3(1,1,-1),
			vec3(-1,1,-1),
		}
		for i=1,4 do
			-- TODO only draw if not in the front
			drawLine{
				p1=bottomVtxs[i],
				p2=bottomVtxs[i%4+1],
			}
			drawLine{
				p1=bottomVtxs[i],
				p2=bottomVtxs[i]+vec3(0,0,2),
			}
		end
		
		gl.glEnable(gl.GL_DEPTH_TEST)

		gui:update()
	end
	local plot3dapp = Plot3DApp()
	plot3dapp:run()
end

return plot3d
