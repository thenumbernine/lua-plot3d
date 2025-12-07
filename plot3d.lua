local ffi = require 'ffi'
local path = require 'ext.path'
local vec3f = require 'vec-ffi.vec3f'
local vec3d = require 'vec-ffi.vec3d'
local vec4d = require 'vec-ffi.vec4d'
local matrix = require 'matrix.ffi'
local box2 = require 'vec.box2'
local gl = require 'gl'
local glCallOrRun = require 'gl.call'
local GLSceneObject = require 'gl.sceneobject'
local GUI = require 'gui'

GUI.drawImmediateMode = false
require 'gui.font'.drawImmediateMode = false


local function mat4x4vecmul(m, x, y, z, w)
	x = tonumber(x)
	y = tonumber(y)
	z = tonumber(z) or 0
	w = tonumber(w) or 1
	return
		m[0] * x + m[4] * y + m[ 8] * z + m[12] * w,
		m[1] * x + m[5] * y + m[ 9] * z + m[13] * w,
		m[2] * x + m[6] * y + m[10] * z + m[14] * w,
		m[3] * x + m[7] * y + m[11] * z + m[15] * w
end

local function homogeneous(x,y,z,w)
	if w > 0 then
		x = x / w
		y = y / w
		z = z / w
	end
	return x,y,z
end



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
local colors = {
	vec3d(1,0,0),
	vec3d(1,1,0),
	vec3d(0,1,0),
	vec3d(0,1,1),
	vec3d(.3,.3,1),
	vec3d(1,.2,1),
}
local function plot3d(graphs, numRows, fontfile)
	for name,graph in pairs(graphs) do
		if not graph.color then
			local h = math.random() * #colors + 1
			local hi = math.floor(h)
			local hii = hi % #colors + 1
			local f = h - hi
			local c = colors[hi] * f + colors[hii] * (1 - f)
			-- add luminance
			local s = .1
			c = c * (1 - s) + vec3d(1,1,1) * s
			--c = c / math.max(c:unpack())
			graph.color = c
		end
		if not graph.cols then
			graph.cols = {1,2,3}
		end
		if not graph.mins or not graph.maxs then
			graph.mins = {}
			graph.maxs = {}
			for i,data in ipairs(graph) do
				for _,value in ipairs(data) do
					if math.isfinite(value) then
						if not graph.mins[i] then graph.mins[i] = value else graph.mins[i] = math.min(graph.mins[i], value) end
						if not graph.maxs[i] then graph.maxs[i] = value else graph.maxs[i] = math.max(graph.maxs[i], value) end
					end
				end
			end
		end

		print('mins', unpack(graph.mins))
		print('maxs', unpack(graph.maxs))

		local length
		for i,data in ipairs(graph) do
			if not length then
				length = #data
			else
				assert(#data == length, "data mismatched length, found "..#data.." expected "..length)
			end
		end
		graph.length = length
	end

	local gui
	local coordText

	local function redraw()
		for _,graph in pairs(graphs) do
			--graph.obj:delete()
			graph.obj = nil
		end
	end

	local mins, maxs
	local function resetView()
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

	local function scaleToMinMax(x, y, z)
		return
			(x - mins[1]) / (maxs[1] - mins[1]) * 2 - 1,
			(y - mins[2]) / (maxs[2] - mins[2]) * 2 - 1,
			(z - mins[3]) / (maxs[3] - mins[3]) * 2 - 1
	end

	resetView()

	local Plot3DApp = require 'glapp.orbit'()

	Plot3DApp.viewDist = 3

	function Plot3DApp:initGL(...)
		if Plot3DApp.super.initGL then
			Plot3DApp.super.initGL(self, ...)
		end
		if not fontfile or not path(fontfile):exists() then
			-- TODO resolve path to `require 'gui'`
			fontfile = os.getenv'LUA_PROJECT_PATH'..'/plot3d/font.png'
		end

		gui = GUI{font=fontfile}
		gui.view = require 'glapp.view'()
		gui.font.view = gui.view

		local names = table()
		for name,_ in pairs(graphs) do
			names:insert(name)
		end
		names:sort()

		local function colorForEnabled(graph)
			if graph.enabled then
				return graph.color.x, graph.color.y, graph.color.z, 1
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

		self.lineObj = GLSceneObject{
			program = {
				precision = 'best',
				version = 'latest',
				vertexCode = [[
in vec3 vertex;
uniform mat4 mvProjMat;
void main() {
	gl_Position = mvProjMat * vec4(vertex, 1.);
}
]],
				fragmentCode = [[
uniform vec4 color;
out vec4 fragColor;
void main() {
	fragColor = color;
}
]],
				-- upload once
				uniforms = {
					color = {1,1,1,1},
				},
			},
			geometry = {
				mode = gl.GL_LINES,
			},
			vertexes = {
				useVec = true,
				dim = 3,
			},
			-- upload every draw
			uniforms = {
				mvProjMat = self.view.mvProjMat.ptr,
			},
		}
	end

	local bottomVtxs = {
		vec3f(-1,-1,-1),
		vec3f(1,-1,-1),
		vec3f(1,1,-1),
		vec3f(-1,1,-1),
	}
	function Plot3DApp:update()
		gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
		Plot3DApp.super.update(self)	-- update view

		local mx,my = gui:sysSize()
		gui.view.mvMat:setIdent()
		gui.view.projMat:setOrtho(0, mx, 0, my, -1, 1)
		gui.view.mvProjMat:copy(gui.view.projMat)


		--[[
		local mx, my = gui:sysSize()
		coordText:pos(mousepos[1] * mx, mousepos[2] * my)
		coordText:setText(
			('%.3e'):format(mousepos[1] * viewbbox.max[1] + (1-mousepos[1]) * viewbbox.min[1])..','..
			('%.3e'):format((1-mousepos[2]) * viewbbox.max[2] + mousepos[2] * viewbbox.min[2])
		)
		--]]

		gl.glDisable(gl.GL_DEPTH_TEST)
		for _,graph in pairs(graphs) do
			local cols = graph.cols
			if graph.enabled then
				if graph.obj then
					graph.obj.uniforms.mvMat = self.view.mvMat.ptr
					graph.obj.uniforms.projMat = self.view.projMat.ptr
					graph.obj.uniforms.mvProjMat = self.view.mvProjMat.ptr
					graph.obj:draw()
				else
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

						graph.obj = GLSceneObject{
							program = {
								version = 'latest',
								precision = 'best',
								vertexCode = [[
layout(location = 0) in vec3 vertex;
layout(location = 1) in vec3 normal;
out vec3 surfaceToLightNormalized;
out vec3 normalv;
uniform mat4 mvMat;
uniform mat4 mvProjMat;
void main() {
	normalv = normalize((mvMat * vec4(normal, 0.)).xyz);
	surfaceToLightNormalized = -normalize((mvMat * vec4(vertex, 1.)).xyz);
	gl_Position = mvProjMat * vec4(vertex, 1.);
}
]],
								fragmentCode = [[
in vec3 surfaceToLightNormalized;
in vec3 normalv;
out vec4 fragColor;
uniform vec4 color;
uniform mat4 mvMat;
void main() {
	vec3 eyePosv = mvMat[3].xyz;
	const vec3 viewDir = vec3(0., 0., 1.);
	float cosNormalToLightAngle = dot(surfaceToLightNormalized, normalv);

	vec3 lightColor =
		color.xyz * abs(cosNormalToLightAngle)
		+ vec3(1., 1., 1.) * pow(	// specular
			abs(dot(viewDir, reflect(-surfaceToLightNormalized, normalv))),
			127.					// shininess
		);

	fragColor = vec4(lightColor, color.w);
}
]],
								uniforms = {
									color = {graph.color.x, graph.color.y, graph.color.z, .8},
								},
							},
							geometry = {
								mode = gl.GL_QUADS,
							},
							vertexes = {
								useVec = true,
								dim = 3,
							},
							attrs = {
								normal = {
									buffer = {
										useVec = true,
										dim = 3,
									},
								},
							},
						}

						local indexes = {}
						local qvtx = {{}, {}, {}, {}}

						local vertexes = graph.obj.attrs.vertex.buffer:beginUpdate()
						local normals = graph.obj.attrs.normal.buffer:beginUpdate()

						local colA, colB, colC = table.unpack(cols)
						for basey=1,#graph.eols-2 do
							for basex=1,graph.eols[1]-1 do
								for ofsi,ofs in ipairs(quad) do
									local x = basex + ofs[1]
									local y = basey + ofs[2]
									indexes[ofsi] = (graph.eols[y-1] or 0) + x
								end

								-- position data in center of view
								local ax = graph[colA][indexes[1]]
								local ay = graph[colB][indexes[1]]
								local az = graph[colC][indexes[1]]
								if not (math.isfinite(ax) and math.isfinite(ay) and math.isfinite(az)) then goto bad end
								ax, ay, az = scaleToMinMax(ax, ay, az)
								qvtx[1][1], qvtx[1][2], qvtx[1][3] = ax, ay, az
								
								local bx = graph[colA][indexes[2]]
								local by = graph[colB][indexes[2]]
								local bz = graph[colC][indexes[2]]
								if not (math.isfinite(bx) and math.isfinite(by) and math.isfinite(bz)) then goto bad end
								bx, by, bz = scaleToMinMax(bx, by, bz)
								qvtx[2][1], qvtx[2][2], qvtx[2][3] = bx, by, bz

								local cx = graph[colA][indexes[3]]
								local cy = graph[colB][indexes[3]]
								local cz = graph[colC][indexes[3]]
								if not (math.isfinite(cx) and math.isfinite(cy) and math.isfinite(cz)) then goto bad end
								cx, cy, cz = scaleToMinMax(cx, cy, cz)
								qvtx[3][1], qvtx[3][2], qvtx[3][3] = cx, cy, cz

								local dx = graph[colA][indexes[4]]
								local dy = graph[colB][indexes[4]]
								local dz = graph[colC][indexes[4]]
								if not (math.isfinite(dx) and math.isfinite(dy) and math.isfinite(dz)) then goto bad end
								dx, dy, dz = scaleToMinMax(dx, dy, dz)
								qvtx[4][1], qvtx[4][2], qvtx[4][3] = dx, dy, dz

								local dxX = (bx - ax + cx - dx) * .5
								local dxY = (by - ay + cy - dy) * .5
								local dxZ = (bz - az + cz - dz) * .5
								local dyX = (dx - ax + cx - bx) * .5
								local dyY = (dy - ay + cy - by) * .5
								local dyZ = (dz - az + cz - bz) * .5

								local nx = dxY * dyZ - dxZ * dyY
								local ny = dxZ * dyX - dxX * dyZ
								local nz = dxX * dyY - dxY * dyX

								for i=1,4 do
									vertexes:emplace_back():set(table.unpack(qvtx[i]))
									normals:emplace_back():set(nx, ny, nz)
								end
::bad::
							end
						end

						-- everything in graph.obj:endUpdate() except :draw()
						graph.obj.attrs.vertex.buffer:endUpdate()
						graph.obj.attrs.normal.buffer:endUpdate()
						graph.obj.geometry.count = #vertexes

						--]]
					else
						local data = table()
						for i=1,graph.length do
							local v = {graph[cols[1]][i], graph[cols[2]][i], graph[cols[3]][i]}
							for j=1,3 do
								v[j] = (v[j] - mins[j]) / (maxs[j] - mins[j]) * 2 - 1
								data:insert(v[j])
							end
						end
						graph.obj = GLSceneObject{
							program = {
								version = 'latest',
								precision = 'best',
								vertexCode = [[
in vec3 vertex;
uniform mat4 mvProjMat;
void main() {
	gl_Position = mvProjMat * vec4(vertex, 1.);
}
]],
								fragmentCode = [[
uniform vec4 color;
out vec4 fragColor;
void main() {
	fragColor = color;
}
]],
								uniforms = {
									color = {graph.color.x, graph.color.y, graph.color.z, .8},
								},
							},
							geometry = {
								mode = gl.GL_POINTS,
							},
							vertexes = {
								data = data,
								dim = 3,
							},
						}
					end
				end
			end
		end

		gl.glDisable(gl.GL_DEPTH_TEST)
		--[[
		gl.glPolygonMode(gl.GL_FRONT_AND_BACK, gl.GL_LINE)
		glCallOrRun(list)
		gl.glPolygonMode(gl.GL_FRONT_AND_BACK, gl.GL_FILL)
		--]]

		local function drawText3D(text, x, y, z, w)
			x,y,z,w = mat4x4vecmul(self.view.mvProjMat.ptr, x, y, z, w)
			x,y,z = homogeneous(x,y,z,w)
			if x < -1 or x > 1
			or y < -1 or y > 1
			or z < -1 or z > 1
			then return end

			local w, h = gui:sysSize()
			x = (x * .5 + .5) * w
			y = (y * .5 + .5) * h

			gui.font:drawUnpacked(
				x, y,	-- pos
				1,-1,	-- fontSize
				text,	-- text
				w, h	-- size
			)
		end

		local function drawLine(x1, y1, z1, x2, y2, z2)
			local vtxs = self.lineObj:beginUpdate()
			vtxs:resize(2)
			local v = vtxs.v+0
			v.x, v.y, v.z = x1, y1, z1
			local v = vtxs.v+1
			v.x, v.y, v.z = x2, y2, z2
			self.lineObj:endUpdate()	-- and draw
		end

		-- project view -z
		local viewRot = self.view.angle
		local right = viewRot:xAxis()
		local fwd = -viewRot:zAxis()

		-- draw a box around it
		-- draw tickers along each axis at specific spacing ... 5 tics per axii?
		local v = vec3d()
		v.x = (right.x < 0) and -1 or 1
		v.y = (right.y < 0) and -1 or 1
		v.z = -1

		for j=0,2 do
			local from = mins[j+1]
			local to = maxs[j+1]
			if v.s[j] > 0 then from,to = to,from end
			local fromPt = v:clone()
			local toPt = v:clone()
			toPt.s[j] = -toPt.s[j]
			local axis = vec3d()
			axis.s[j] = 1

			local perpX = fwd.y * axis.z - fwd.z * axis.y
			local perpY = fwd.z * axis.x - fwd.x * axis.z
			local perpZ = fwd.x * axis.y - fwd.y * axis.x

			local ticks = 8
			for i=0,ticks do
				local f = i / ticks
				local centerX = fromPt.x * (1-f) + toPt.x * f
				local centerY = fromPt.y * (1-f) + toPt.y * f
				local centerZ = fromPt.z * (1-f) + toPt.z * f
				drawLine(
					centerX + perpX * .1,
					centerY + perpY * .1,
					centerZ + perpZ * .1,
					centerX - perpX * .1,
					centerY - perpY * .1,
					centerZ - perpZ * .1
				)
				drawText3D(
					tostring(from * (1-f) + to * f),
					perpX * .1 + centerX,
					perpY * .1 + centerY,
					perpZ * .1 + centerZ
				)
			end
		end

		for i=1,4 do
			-- TODO only draw if not in the front
			local v1 = bottomVtxs[i]
			local v2 = bottomVtxs[i%4+1]
			drawLine(
				v1.x, v1.y, v1.z,
				v2.x, v2.y, v2.z)
			drawLine(
				v1.x, v1.y, v1.z,
				v1.x, v1.y, v1.z + 2)
		end

		gl.glEnable(gl.GL_DEPTH_TEST)

		gui:update()
		gl.glEnable(gl.GL_BLEND)
	end
	local plot3dapp = Plot3DApp()
	return plot3dapp:run()
end

return plot3d
