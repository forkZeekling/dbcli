--export LUA_BIN=/media/sf_D_DRIVE/dbcli/lib/linux
-- export LD_LIBRARY_PATH=/media/sf_D_DRIVE/jdk_linux/jre/bin:/media/sf_D_DRIVE/jdk_linux/jre/lib/amd64/server:./lib/linux
--local java_bin="/media/sf_D_DRIVE/jdk_linux/jre/bin"
--local java_bin="d:/program files/java/jre/bin"


local _os=jit.os:lower()
local psep,fsep,dll,which,dlldir
if _os=="windows" then 
	psep,fsep,dll,which,dlldir=';','\\','.dll','where java 2>nul',jit.arch
else
	psep,fsep,dll,which,dlldir=':','/',_os=="darwin" and ".dylib" or ".so",'which java 2>/dev/null',_os
end

local function resolve(path) return (path:gsub("[\\/]+",fsep)) end

local lua_path=resolve(debug.getinfo(1).source:sub(2):gsub('[^\\/]+$','')..dlldir)
package.cpath='?'..dll..';'..resolve(lua_path..'/?'..dll)

local uv=require("luv")

uv.set_process_title("DBCli - Initializing")
local files={}
local function scan(dir,ext)
	local req = uv.fs_scandir(dir)
	local pattern='%.'..ext..'$'
	local function iter()
		return uv.fs_scandir_next(req)
	end
	local subdirs={}
	for name, ftype in iter do
		name=resolve(dir..'/'..name)
		if ftype==nil then
			local attr=uv.fs_stat(name)
			ftype=attr and attr.type or "file"
		end
		if ftype=="directory" then
			subdirs[#subdirs+1]=name
		elseif name:find(pattern) then
			files[#files+1]=name
		end
	end
	for _,sub in ipairs(subdirs) do scan(sub,ext) end
end


scan("lib","jar")
local other_lib=os.getenv("OTHER_LIB")
local other_options={}
if other_lib then
	for param in other_lib:gmatch("%S*") do
		other_options[#other_options+1]=param
	end
	files[#files+1]=table.remove(other_options,1)
end
local jars=table.concat(files,psep)

local java_bin,java_home
java_bin=arg[1]
if not java_bin or not uv.fs_stat(resolve(java_bin)) then
	print("Cannot find java executable, exit.")
	os.exit(1)
end

java_bin=java_bin:gsub("[\\/][^\\/]+$","")
java_home=java_bin:gsub("[\\/][^\\/]+$","")
if uv.fs_stat(resolve(java_home..'/jre')) then
	java_bin=resolve(java_home..'/jre/bin')
end

local path={java_bin}
local jvmpath=uv.fs_stat(resolve(java_bin..'/server')) and resolve(java_bin..'/server')
if not jvmpath then jvmpath=uv.fs_stat(resolve(java_bin..'/client')) and resolve(java_bin..'/client') end
if not jvmpath then jvmpath=resolve(java_bin:gsub("/bin/?$",'/lib/amd64/server')) end

path[#path+1]=jvmpath
--path[#path+1]=jvmpath:gsub("[\\/][^\\/]+$","")

local libpath=os.getenv("LD_LIBRARY_PATH")
if libpath then path[#path+1]=libpath end
uv.os_setenv("LD_LIBRARY_PATH",table.concat(path,psep))


path[#path+1]=os.getenv("PATH")
uv.os_setenv("PATH",table.concat(path,psep))

local charset=os.getenv("DBCLI_ENCODING") or "UTF-8"
local options ={'-noverify' ,
			    '-Xmx384M',
			    '-XX:+UseStringDeduplication','-XX:+UseParallelGC','-XX:+UseCompressedOops',
			    '-Dfile.encoding='..charset,
			    '-Duser.language=en','-Duser.region=US','-Duser.country=US',
			    '-Djava.awt.headless=true',
				'-Djava.home='..java_home,
			    '-Djava.class.path='..jars}
for _,param in ipairs(other_options) do options[#options+1]=param end 

javavm = require("javavm",true)
javavm.create(table.unpack(options))
local destroy=javavm.destroy
loader = java.require("org.dbcli.Loader",true).get()
console=loader.console
terminal,reader,writer=console.terminal,console.reader,console.writer

local m,_env,_loaded=_ENV or _G,{},{}
for k,v in pairs(m) do _env[k]=v end
if m.loaded then for k,v in pairs(m.loaded) do _loaded[k]=v end end

while true do
	local input,err=loadfile(resolve(loader.root.."/lua/input.lua"),'bt',_env)
	if not input then error(err) end
	loader:resetLua()
	input(table.unpack(arg))
	if not rawget(_G,'REOAD_SIGNAL') then break end
	m.loaded=_loaded
end

destroy()
