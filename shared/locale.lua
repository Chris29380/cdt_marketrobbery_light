-- Traductions déclaratives : aucune traduction n'est exécutée comme du code.
local L={}
local catalog,bundles,patterns,parameters
local function read(path)
    if type(LoadResourceFile)~='function' then return nil end
    local raw=LoadResourceFile(GetCurrentResourceName(),path)
    if not raw then return nil end
    local ok,value=pcall(json.decode,raw)
    return ok and type(value)=='table' and value or nil
end
local function load()
    if catalog then return end
    catalog={fr='Français'};bundles={fr={}};patterns={};parameters={}
    local french=read('locales/fr.json')
    for source,indices in pairs(french and french.translateParameters or {})do
        if type(source)=='string' and type(indices)=='table' then
            parameters[source]={};for _,index in ipairs(indices)do if type(index)=='number' and index>=0 and index%1==0 then parameters[source][index]=true end end
        end
    end
    for code,label in pairs(read('locales/index.json') or {})do
        if type(code)=='string' and code:match('^[a-z][a-z0-9_%-]*$') and #code<=24 and type(label)=='string' and #label<=80 then
            local data=read('locales/'..code..'.json')
            if data and type(data.messages)=='table' then
                local messages={}
                for source,value in pairs(data.messages)do
                    if type(source)=='string' and type(value)=='string' then messages[source]=value end
                end
                catalog[code]=label;bundles[code]=messages
            end
        end
    end
    for code,messages in pairs(bundles)do
        patterns[code]={}
        for source,target in pairs(messages)do
            if source:find('{0}',1,true) then
                local pattern=source:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1'):gsub('{%d+}','([^\n]-)')
                local literal=source:gsub('{%d+}','')
                patterns[code][#patterns[code]+1]={pattern='^'..pattern..'$',target=target,source=source,weight=#literal}
            end
        end
        table.sort(patterns[code],function(a,b)return a.weight>b.weight end)
    end
end
function L.available()load();return catalog end
function L.defaultLanguage(fallback)
    load()
    local configured=type(GetConvar)=='function' and GetConvar('cdt_language','') or ''
    local code=configured~='' and configured or fallback or 'fr'
    code=tostring(code):match('^%s*(.-)%s*$'):lower()
    return catalog[code] and code or 'fr'
end
function L.bundle(code)
    load();code=bundles[code] and code or 'fr'
    local messages={};for k,v in pairs(bundles.fr)do messages[k]=v end
    for k,v in pairs(bundles[code])do messages[k]=v end
    local nested={};for source,indices in pairs(parameters)do nested[source]={};for index in pairs(indices)do nested[source][#nested[source]+1]=index end end
    return {language=code,languages=catalog,messages=messages,translateParameters=nested}
end
function L.text(source,code,depth)
    if type(source)~='string' then return source end
    depth=depth or 0;if depth>6 then return source end
    load();local messages=bundles[code] or bundles.fr
    if messages[source] then return messages[source] end
    local leading,body,trailing=source:match('^(%s*)(.-)(%s*)$')
    if body~=source then return leading..L.text(body,code,depth+1)..trailing end
    local multiple=source:find('\n',1,true) or source:find('%.%s+[A-Z]')
    for _,entry in ipairs(patterns[code] or patterns.fr)do
            local captures={source:match(entry.pattern)}
            if #captures>0 then return (entry.target:gsub('{(%d+)}',function(index)
                index=tonumber(index);local value=captures[index+1] or ''
                return parameters[entry.source] and parameters[entry.source][index] and L.text(value,code,depth+1) or value
            end))end
    end
    if multiple then
        -- Les rapports combinent des phrases et des lignes, sans traduire les noms injectés.
        if source:find('\n',1,true) then return (source:gsub('([^\n]+)',function(line)return L.text(line,code,depth+1)end))end
        local parts={};local start=1
        while true do
            local last,nextStart=source:find('%.%s+[A-Z]',start)
            if not last then parts[#parts+1]=L.text(source:sub(start),code,depth+1);break end
            parts[#parts+1]=L.text(source:sub(start,last),code,depth+1)..source:sub(last+1,nextStart-1)
            start=nextStart
        end
        return table.concat(parts)
    end
    return bundles.fr[source] or source
end
return L
