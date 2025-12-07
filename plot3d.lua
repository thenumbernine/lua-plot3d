local ffi = require 'ffi'
local path = require 'ext.path'
local vec2 = require 'vec.vec2'
local vec3 = require 'vec.vec3'
local vec4 = require 'vec.vec4'
local vec3f = require 'vec-ffi.vec3f'
local vec3d = require 'vec-ffi.vec3d'
local vec4f = require 'vec-ffi.vec4f'
local vec4d = require 'vec-ffi.vec4d'
local box2 = require 'vec.box2'
local gl = require 'gl'
local glCallOrRun = require 'gl.call'
local GLSceneObject = require 'gl.sceneobject'
local GUI = require 'gui'


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


local resetView


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
			graph.obj = ni
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

	local Plot3DApp = require 'glapp.orbit'()

	Plot3DApp.viewDist = 3
	Plot3DApp.viewUseGLMatrixMode = true

	function Plot3DApp:initGL(...)
		if Plot3DApp.super.initGL then
			Plot3DApp.super.initGL(self, ...)
		end
		if not fontfile or not path(fontfile):exists() then
			-- TODO resolve path to `require 'gui'`
			fontfile = os.getenv'LUA_PROJECT_PATH'..'/plot3d/font.png'
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
		}
	end

	local matrix = require 'matrix.ffi'
	local mvMat = matrix({4,4}, 'float'):zeros()
	local projMat = matrix({4,4}, 'float'):zeros()
	local mvProjMat = matrix({4,4}, 'float'):zeros()
	function Plot3DApp:update()
		gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
		Plot3DApp.super.update(self)	-- update view

		gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, mvMat.ptr)
		gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, projMat.ptr)
		mvProjMat:mul4x4(projMat, mvMat)

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
					graph.obj.uniforms.mvMat = mvMat.ptr
					graph.obj.uniforms.projMat = projMat.ptr
					graph.obj.uniforms.mvProjMat = mvProjMat.ptr
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
						local indexes = {}
						local vecs = {}
						local qvtx = {{}, {}, {}, {}}
						
						local vertexes = table()
						local normals = table()
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
										for k=1,3 do
											vertexes:insert(qvtx[j][k])
											normals:insert(n[k])
										end
									end
								end
							end
						end
print('building graph...')						
						graph.obj = GLSceneObject{
							program = {
								version = 'latest',
								precision = 'best',
								vertexCode = [[
layout(location = 0) in vec3 vertex;
layout(location = 1) in vec3 normal;
out vec3 worldCoordv;
out vec3 eyePosv;
out vec3 normalv;
uniform mat4 mvMat;
uniform mat4 projMat;
void main() {
	normalv = normalize((mvMat * vec4(normal, 0.)).xyz);
	worldCoordv = vertex;
	vec4 viewCoords = mvMat * vec4(vertex, 1.);
	gl_Position = projMat * viewCoords;

	eyePosv = (mvMat * vec4(0., 0., 0., 1.)).xyz;
}
]],
								fragmentCode = [[
in vec3 worldCoordv;
in vec3 eyePosv;
in vec3 normalv;
out vec4 fragColor;
uniform vec4 color;
void main() {
	// TODO FIXME
	vec3 surfaceToLightNormalized = normalize(worldCoordv);
	vec3 viewDir = -normalize(eyePosv);
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
									color = {graph.color[1], graph.color[2], graph.color[3], .8},
								},
							},
							geometry = {
								mode = gl.GL_QUADS,
							},
							vertexes = {
								data = vertexes,
								dim = 3,
							},
							attrs = {
								normal = {
									buffer = {
										data = normals,
										dim = 3,
									},
								},
							},
						}						
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
									color = {graph.color[1], graph.color[2], graph.color[3], .8},
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

		local function drawText3D(pt, text)
			pt = vec4d(mat4x4vecmul(mvProjMat.ptr, pt:unpack()))
			pt = vec3d(homogeneous(pt:unpack()))
			for i=0,2 do
				if pt.s[i] < -1 or pt.s[i] > 1 then return end
			end
			pt = (pt * .5 + vec3d(.5, .5, .5))
			local w,h = gui:sysSize()
			pt.x = pt.x * w
			pt.y = pt.y * h

			gl.glMatrixMode(gl.GL_PROJECTION)
			gl.glPushMatrix()
			gl.glLoadIdentity()
			gl.glOrtho(0, w, 0, h, -1, 1)
			gl.glMatrixMode(gl.GL_MODELVIEW)
			gl.glPushMatrix()
			gl.glLoadIdentity()

			gui.font:draw{
				pos = vec3(pt:unpack()),
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
			self.lineObj.uniforms.mvProjMat = mvProjMat.ptr
			local vtxs = self.lineObj:beginUpdate()
			vtxs:emplace_back():set(args.p1:unpack())
			vtxs:emplace_back():set(args.p2:unpack())
			self.lineObj:endUpdate()	-- and draw
		end

		local function drawTicks(args)
			local ticks = args.ticks or 8
			local d = args.p2 - args.p1
			for i=0,ticks do
				local center = args.p1 + d*(i/ticks)
				drawLine{
					p1 = center + args.perp*.1,
					p2 = center - args.perp*.1,
				}
				local v = (args.to - args.from) * i/ticks + args.from
				drawText3D(args.perp*.1 + center, tostring(v))
			end
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
			drawTicks{
				p1=fromPt,
				p2=toPt,
				perp=fwd:cross(axis),
				from=from,
				to=to,
			}
		end

		local bottomVtxs = {
			vec3f(-1,-1,-1),
			vec3f(1,-1,-1),
			vec3f(1,1,-1),
			vec3f(-1,1,-1),
		}

		for i=1,4 do
			-- TODO only draw if not in the front
			drawLine{
				p1=bottomVtxs[i],
				p2=bottomVtxs[i%4+1],
			}
			drawLine{
				p1=bottomVtxs[i],
				p2=bottomVtxs[i] + vec3f(0,0,2),
			}
		end

		gl.glEnable(gl.GL_DEPTH_TEST)

		gui:update()
	end
	local plot3dapp = Plot3DApp()
	return plot3dapp:run()
end

return plot3d
