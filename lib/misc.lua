local ffi = require("ffi")
local string,table,math,java,loadstring,tostring,tonumber=string,table,math,java,loadstring,tostring,tonumber
local ipairs,pairs,type=ipairs,pairs,type

function string.initcap(v)
    return (' '..v):lower():gsub("([^%w])(%w)",function(a,b) return a..b:upper() end):sub(2)
end

function os.shell(cmd,args)
    io.popen('"'..cmd..(args and (" "..args) or "")..'"')
end

function os.find_extension(exe,ignore_errors)
    local err='Cannot find executable "'..exe..'" in the default path, please add it into EXT_PATH of file data/'..(env.IS_WINDOWS and 'init.cfg' or 'init.conf')
    if exe:find('[\\/]') then
        local type,file=os.exists(exe)
        if not ignore_errors then env.checkerr(type,err) end
        return file
    end
    exe='"'..env.join_path(exe):trim('"')..'"'
    local nul=env.IS_WINDOWS and "NUL" or "/dev/null"
    local cmd=string.format("%s %s 2>%s", env.IS_WINDOWS and "where " or "which ",exe,nul)
    local f=io.popen(cmd)
    local path
    for file in f:lines() do
        path=file
        break
    end
    if not ignore_errors then env.checkerr(path,err) end
    return path
end

--Continus sep would return empty element
function string.split (s, sep, plain,occurrence,case_insensitive)
    local r={}
    for v in s:gsplit(sep,plain,occurrence,case_insensitive) do
        r[#r+1]=v
    end
    return r
end

function string.replace(s,sep,txt,plain,occurrence,case_insensitive)
    local r=s:split(sep,plain,occurrence,case_insensitive)
    return table.concat(r,txt),#r-1
end

function string.escape(s, mode)
    s = s:gsub('([%^%$%(%)%.%[%]%*%+%-%?%%])', '%%%1')
    if mode == '*i' then s = s:case_insensitive_pattern() end
    return s
end

function string.gsplit(s, sep, plain,occurrence,case_insensitive)
    local start = 1
    local counter=0
    local done = false
    local s1=case_insensitive==true and s:lower() or s
    local sep1=case_insensitive==true and sep:lower() or sep
    local function pass(i, j)
        if i and ((not occurrence) or counter<occurrence) then
            local seg = i>1 and s:sub(start, i - 1) or ""
            start = j + 1
            counter=counter+1
            return seg, s:sub(i,j),counter
        else
            done = true
            return s:sub(start),"",counter+1
        end
    end
    return function()
        if done then return end
        if sep1 == '' then done = true return s end
        return pass(s1:find(sep1, start, plain))
    end
end

function string.case_insensitive_pattern(pattern)
    -- find an optional '%' (group 1) followed by any character (group 2)
    local p = pattern:gsub("(%%?)(.)",
        function(percent, letter)
            if percent ~= "" or not letter:match("%a") then
                -- if the '%' matched, or `letter` is not a letter, return "as is"
                return percent .. letter
            else
                -- else, return a case-insensitive character class of the matched letter
                return string.format("[%s%s]", letter:lower(), letter:upper())
            end
        end)
    return p
end

local spaces={}
local s=' \t\n\v\f\r\0'
for i=1,#s do spaces[s:byte(i)]=true end
local ext_spaces={}
local function exp_pattern(sep)
    local ary
    if sep then
        if not ext_spaces[sep] then
            ext_spaces[sep]={}
            for i=1,#sep do ext_spaces[sep][sep:byte(i)]=true end
        end
        ary=ext_spaces[sep]
    end
    return ary
end

local function rtrim(s,sep)
    local ary=exp_pattern(sep)
    if type(s)=='string' then
        local len=#s
        for i=len,1,-1 do
            local p=s:byte(i)
            if not spaces[p] and not (ary and ary[p]) then
                return i==len and s or s:sub(1,i)
            elseif i==1 then
                return ''
            end
        end
    end
    return s
end

local function ltrim(s,sep)
    local ary=exp_pattern(sep)
    if type(s)=='string' then
        local len=#s
        for i=1,len do
            local p=s:byte(i)
            if not spaces[p] and not (ary and ary[p]) then
                return i==1 and s or s:sub(i)
            elseif i==len then
                return ''
            end
        end
    end
    return s
end

string.ltrim,string.rtrim=ltrim,rtrim
function string.trim(s,sep)
    return rtrim(ltrim(s,sep),sep)
end


String=java.require("java.lang.String")
local String=String
--this function only support %s
function string.fmt(base,...)
    local args = {...}
    for k,v in ipairs(args) do
        if type(v)~="string" then
            args[k]=tostring(v)
        end
    end
    return String:format(base,table.unpack(args))
end

function string.format_number(base,s,cast)
    if not tonumber(s) then return s end
    return String:format(base,java.cast(tonumber(s),cast or 'double'))
end

function string.lpad(str, len, char)
    str=tostring(str) or str
    return (str and (str..(char or ' '):rep(len - #str)):sub(1,len)) or str
end

function string.rpad(str, len, char)
    str=tostring(str) or str
    return (str and ((char or ' '):rep(len - #str)..str):sub(-len)) or str
end

function string.cpad(str, len, char,func)
    str,char=tostring(str) or str,char or ' '
    if not str then return str end
    str=str:sub(1,len)
    local left=char:rep(math.floor((len-#str)/2))
    local right=char:rep(len-#left-#str)
    return type(func)~="function" and string.format("%s%s%s",left,str,right) or func(left,str,right)
end


if not table.unpack then table.unpack=function(tab) return unpack(tab) end end

local system=java.system
local clocker=system.currentTimeMillis
function os.timer()
    return clocker()/1000
end

function string.from(v)
    local path=_G.WORK_DIR
    path=path and #path or 0
    if type(v) == "function" then
        local d=debug.getinfo(v)
        local src=d.source:gsub("^@+","",1):split(path,true)
        if src and src~='' then
            return 'function('..src[#src]:gsub('%.lua$','#'..d.linedefined)..')'
        end
    elseif type(v) == "string" then
        return ("%q"):format(v:gsub("\t","    "))
    end
    return tostring(v)
end

local weekmeta={__mode='k'}
local globalweek=setmetatable({},weekmeta)
function table.weak(reuse)
    return reuse and globalweek or setmetatable({},weekmeta)
end

function table.append(tab,...)
    for i=1,select('#',...) do
        tab[#tab+1]=select(i,...)
    end
end

local json=json
if json.use_lpeg then json.use_lpeg () end
function table.totable(str)
    local txt,err,done=loadstring('return '..str)
    if not txt then 
        done,txt=pcall(json.decode,str) 
    else
        done,txt=pcall(txt)
    end
    if not done then
        local idx=0
        str=('\n'..str):gsub('\n',function(s) idx=idx+1;return string.format('\n%4d',idx) end)
        env.raise('Error while parsing text into Lua table:' ..(err or tostring(txt) or '')..str)
    end
    return txt
end

local function compare(a,b)
    local t1,t2=type(a[1]),type(b[1])
    if t1==t2 and t1~='table' and t1~='function' and t1~='userdata' and t1~='thread'  then return a[1]<b[1] end
    if t1=="number" then return true end
    if t2=="number" then return false end
    return tostring(a[1])<tostring(b[1])
end

function math.round(exact, quantum)
    if type(exact)~='number' then return exact end
    quantum = quantum and 0.1^quantum or 1
    local quant,frac = math.modf(exact/quantum)
    return quantum * (quant + (frac > 0.5 and 1 or 0))
end

function table.clone (t,depth) -- deep-copy a table
    if type(t) ~= "table" or (depth or 1)<=0 then return t end
    local meta = getmetatable(t)
    local target = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            target[k] = table.clone(v,(tonumber(depth) or 99)-1)
        else
            target[k] = v
        end
    end
    setmetatable(target, meta)
    return target
end

function table.week(typ,gc)
    return setmetatable({},{__mode=typ or 'k'})
end

function table.strong(tab)
    return setmetatable(tab or {},{__gc=function(self) print('table is gc.') end})
end

function table.dump(tbl,indent,maxdep,tabs)
    maxdep=tonumber(maxdep) or 9
    if maxdep<=1 then
        return tostring(tbl)
    end

    if tabs==nil then
        tabs={}
    end

    if not indent then indent = '' end

    indent=string.rep(' ',type(indent)=="number" and indent or #indent)

    local ind = 0
    local pad=indent..'  '
    local maxlen=0
    local keys={}

    local fmtfun=string.format
    for k,_ in pairs(tbl) do
        local k1=k
        if type(k)=="string" and not k:match("^[%w_]+$") then k1=string.format("[%q]",k) end
            keys[#keys+1]={k,k1}
            if maxlen<#tostring(k1) then maxlen=#tostring(k1) end
            if maxlen>99 then
                fmtfun=string.fmt
            end
        end

        table.sort(keys,compare)
        local rs=""
        for v, k in ipairs(keys) do
            v,k=tbl[k[1]],k[2]
        local fmt =(ind==0 and "{ " or pad)  .. fmtfun('%-'..maxlen..'s%s' ,tostring(k),'= ')
        local margin=(ind==0 and indent or '')..fmt
        rs=rs..fmt
        if type(v) == "table" then
            if k=='root' then
                rs=rs..'<<Bypass root>>'
            elseif tabs then
                if not tabs[v] then
                    local c=tabs.__current_key or ''
                    local c1=c..(c=='' and '' or '.')..tostring(k)
                    tabs[v],tabs.__current_key=c1,c1
                    rs=rs..table.dump(v,margin,maxdep-1,tabs)
                    tabs.__current_key=c
                else
                    rs=rs..'<<Refer to '..tabs[v]..'>>'
                end
            else
                rs=rs..table.dump(v,margin,maxdep-1,tabs)
            end
        elseif type(v) == "function" then
            rs=rs..'<'..string.from(v)..'>'
        elseif type(v) == "userdata" then
            rs=rs..'<userdata('..tostring(v)..')>'
        elseif type(v) == "string" then
            rs=rs..string.format("%q",v:gsub("\n","\n"..string.rep(" ",#margin)))
        else
            rs=rs..tostring(v)
        end
        rs=rs..',\n'
        ind=ind+1
    end
    if ind==0 then return  '{}' end
    rs=rs:sub(1,-3)..'\n'
    if ind<2 then return rs:sub(1,-2)..' }' end
    return rs..indent..'}'
end


function try(args)
    local succ,res,err,final=pcall(args[1])
    local catch=args.catch or args[2]
    local finally=args.finally or args[3]
    final,err=true,not succ
    if err and catch then
        if(type(res)=="string" and env.ansi) then 
            res=res:match(env.ansi.pattern.."(.-)"..env.ansi.pattern)
        end
        succ,res=pcall(catch,res)
    end

    if finally then
        final,err=pcall(finally,err)
        if not catch or not final then succ,res=final,err or res end
    end

    if not succ then env.raise_error(res) end
    return res
end

--[[UTF-8 codepoint:
     byte  1        2           3          4
    --------------------------------------------
     00 - 7F
     C2 - DF      80 - BF
     E0           A0 - BF     80 - BF
     E1 - EC      80 - BF     80 - BF
     ED           80 - 9F     80 - BF
     EE - EF      80 - BF     80 - BF
     F0           90 - BF     80 - BF    80 - BF
     F1 - F3      80 - BF     80 - BF    80 - BF
     F4           80 - 8F     80 - BF    80 - BF

    The first hex character present the bytes of the char:
    0-7: 1 byte, e.g.:  57
    C-D: 2 bytes,e.g.:  ce 9a
    E:   3 bytes,e.g.:  e6 ad a1
    F:   4 bytes 
--]]--
function string.chars(s,start)
    local i = start or 1
    if not s or i>#s then return nil end
    local function next()
        local c,i1,p,is_multi = s:byte(i),i
        if not c then return end
        if c >= 0xC2 and c <= 0xDF then
            local c2 = s:byte(i + 1)
            if c2 and c2 >= 0x80 and c2 <= 0xBF then i=i+1 end
        elseif c >= 0xE0 and c <= 0xEF then
            local c2 = s:byte(i + 1)
            local c3 = s:byte(i + 2)
            local flag = c2 and c3 and true or false
            if c == 0xE0 then
                if flag and c2 >= 0xA0 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then i1=i+2 end
            elseif c >= 0xE1 and c <= 0xEC then
                if flag and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then i1=i+2 end
            elseif c == 0xED then
                if flag and c2 >= 0x80 and c2 <= 0x9F and c3 >= 0x80 and c3 <= 0xBF then i1=i+2 end
            elseif c >= 0xEE and c <= 0xEF then
                if flag and 
                    not (c == 0xEF and c2 == 0xBF and (c3 == 0xBE or c3 == 0xBF)) and 
                    c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF 
                then i1=i+2 end
            end
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2 = s:byte(i + 1)
            local c3 = s:byte(i + 2)
            local c4 = s:byte(i + 3)
            local flag = c2 and c3 and c4 and true or false
            if c == 0xF0 then
                if flag and
                    c2 >= 0x90 and c2 <= 0xBF and
                    c3 >= 0x80 and c3 <= 0xBF and
                    c4 >= 0x80 and c4 <= 0xBF
                then i1=i+3 end
            elseif c >= 0xF1 and c <= 0xF3 then
                if flag and
                    c2 >= 0x80 and c2 <= 0xBF and
                    c3 >= 0x80 and c3 <= 0xBF and
                    c4 >= 0x80 and c4 <= 0xBF
                then i1=i+3 end
            elseif c == 0xF4 then
                if flag and
                    c2 >= 0x80 and c2 <= 0x8F and
                    c3 >= 0x80 and c3 <= 0xBF and
                    c4 >= 0x80 and c4 <= 0xBF
                then i1=i+3 end
            end
        end
        p,i,is_multi=s:sub(i,i1),i1+1,i1>i
        return p,is_multi,i
    end
    return next
end

function string.wcwidth(s)
    if s=="" then return 0,0 end
    if not s then return nil end 
    local len1,len2=0,0
    for c,is_multi in s:chars() do
        len1,len2=len1+1,len2+(is_multi and 2 or 1)
    end
    return len1,len2
end