local env=env
local db=env.getdb()
local words,abbrs={
    'AUTHORS','BINARY','BINLOG','CHARACTER','CODE','COLLATION','COLUMNS','CONTRIBUTORS','CREATE',
    'DATABASE','DATABASES','ENGINE','ERRORS','EVENT','FROM','FULL','FUNCTION',
    'GLOBAL','GRANTS','HOSTS','INDEX','LIMIT','LOGS','MASTER','OPEN','PLUGINS','PRIVILEGES',
    'PROCEDURE','PROCESSLIST','PROFILE','SESSION','SLAVE','STATUS','STORAGE','TABLE',
    'TRIGGER','VARIABLES','VIEW','WARNINGS','LIKE','WHERE'}

local show={name="SHOW"}

function show.run(arg)
    env.checkhelp(arg)
    db:assert_connect()
    local cmd={"SHOW"}
    local args=env.parse_args(3,arg)
    env.set.set("printsize",10000)
    for i,k in ipairs(args) do
        cmd[#cmd+1]=i<3 and abbrs[k:upper()] or k
        local c=cmd[#cmd]:upper()
        if c=="VARIABLES" or c=="STATUS" or c=="COLLATION" then
            local text=(args[i+1] or ""):upper()
            if text~="" and not text:find("^LIKE") and not text:find("^WHERE") then
                env.printer.set_grep(text)
                break
            end
        end
    end
    cmd=table.concat(cmd,' ')
    if cmd~="SHOW "..arg then print("Command: "..cmd) end
    env.set.set("feed","off")

    db:query(cmd)
end

function show.help(...)
    return db:help_topic(table.concat({...}," "))
end

function show.onload()
    abbrs={}
    for _,k in ipairs(words) do
        abbrs[k:sub(1,2)],abbrs[k:sub(1,3)]=k,k
    end
    abbrs["TBS"]="TABLES"
    abbrs["EVS"]="EVENTS"
    abbrs["DBS"]="DATABASES"
    abbrs["ENS"]="ENGINES"
    abbrs["POS"]="PROFILES"
    abbrs["TRS"]="TRIGGERS"
    abbrs["CLT"]="COLLATION"
    env.set_command(nil,show.name, {"Show database information",show.help},show.run,false,2)
end

return show