package = "plot3d"
version = "dev-1"
source = {
	url = "git+https://github.com/thenumbernine/lua-plot3d"
}
description = {
	homepage = "https://github.com/thenumbernine/lua-plot3d",
	license = "MIT"
}
dependencies = {
	"lua >= 5.1"
}
build = {
	type = "builtin",
	modules = {
		plot3d = "plot3d.lua",
		["plot3d.run"] = "run.lua"
	}
}
