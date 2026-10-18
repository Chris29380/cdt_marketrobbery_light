-- Bridge déclaratif : exports serveur uniquement, sans exécution de code Lua.
local I={}
function I.defaults()
    return {mode='file',resource='',itemCase='preserve',methods={
        count={export='',args={'source','item'},path='',returns=1,mode='number',itemField='name',amountField='amount'},
        canCarry={export='',args={'source','item','amount'},path='',returns=1,mode='boolean'},
        add={export='',args={'source','item','amount'},path='',returns=1,mode='boolean'},
        remove={export='',args={'source','item','amount'},path='',returns=1,mode='boolean'}
    }}
end
local function field(value,path)
    if path=='' then return value end
    for part in path:gmatch('[^.]+')do if type(value)~='table'then return nil end;value=value[tonumber(part)or part]end
    return value
end
function I.validate(config)
    if type(config)~='table' or (config.mode~='file' and config.mode~='exports')then return false,'Mode de bridge personnalisé invalide.'end
    if type(config.resource)~='string' or #config.resource>80 or config.resource~='' and not config.resource:match('^[%w_%-]+$')then return false,'Nom de ressource invalide.'end
    if not ({preserve=true,lower=true,upper=true,weaponUpper=true})[config.itemCase]then return false,'Casse des objets invalide.'end
    if config.mode=='exports' and config.resource==''then return false,'Renseigne la ressource de ton inventaire.'end
    if type(config.methods)~='table'then return false,'Fonctions du bridge manquantes.'end
    for _,name in ipairs({'count','canCarry','add','remove'})do
        local method=config.methods[name]
        if type(method)~='table' or type(method.export)~='string' or #method.export>80 or (method.export~='' and not method.export:match('^[%w_]+$')) or config.mode=='exports' and method.export==''then return false,'Export invalide : '..name end
        if type(method.path)~='string' or #method.path>120 or method.path~='' and not method.path:match('^[%w_%.]+$')then return false,'Chemin de retour invalide : '..name end
        if type(method.returns)~='number' or method.returns%1~=0 or method.returns<1 or method.returns>4 then return false,'Index de retour invalide.'end
        local modes=name=='count' and {number=true,sum=true} or name=='canCarry' and {boolean=true} or {boolean=true,delta=true}
        if not modes[method.mode]then return false,'Interprétation du résultat invalide : '..name end
        if type(method.args)~='table' or #method.args>12 then return false,'Arguments invalides : '..name end
        for key,arg in pairs(method.args)do
            if type(key)~='number' or key%1~=0 or key<1 or key>#method.args or type(arg)~='string' or #arg>500 then return false,'Liste d’arguments invalide.'end
            if not ({source=true,item=true,amount=true,['nil']=true,['true']=true,['false']=true})[arg]then
                if arg:sub(1,5)=='text:' then
                elseif arg:sub(1,7)=='number:'then local n=tonumber(arg:sub(8));if not n or n~=n or math.abs(n)==math.huge then return false,'Argument numérique invalide.'end
                elseif arg:sub(1,5)=='json:'then local ok=pcall(json.decode,arg:sub(6));if not ok then return false,'Argument JSON invalide.'end
                else return false,'Argument inconnu : '..arg end
            end
        end
        if name=='count' then
            for _,key in ipairs({'itemField','amountField'})do if type(method[key])~='string' or #method[key]>80 or method[key]~='' and not method[key]:match('^[%w_%.]+$')then return false,'Champ de quantité invalide.'end end
        end
    end
    return true
end
function I.build(config)
    local valid,why=I.validate(config);assert(valid,why)
    local function itemName(item)
        if config.itemCase=='lower'then return item:lower()end
        if config.itemCase=='upper' or config.itemCase=='weaponUpper' and item:lower():sub(1,7)=='weapon_'then return item:upper()end
        return item
    end
    local function invoke(name,source,item,amount)
        local method=config.methods[name];local args={}
        for index,arg in ipairs(method.args)do
            if arg=='source'then args[index]=source elseif arg=='item'then args[index]=itemName(item) elseif arg=='amount'then args[index]=amount
            elseif arg=='true'then args[index]=true elseif arg=='false'then args[index]=false
            elseif arg:sub(1,5)=='text:'then args[index]=arg:sub(6)
            elseif arg:sub(1,7)=='number:'then args[index]=tonumber(arg:sub(8))
            elseif arg:sub(1,5)=='json:'then args[index]=json.decode(arg:sub(6))end
        end
        local proxy=exports[config.resource]
        local results=table.pack(proxy[method.export](proxy,table.unpack(args,1,#method.args)))
        return field(results[method.returns],method.path)
    end
    local function count(source,item)
        local value=invoke('count',source,item);local method=config.methods.count
        if method.mode=='sum'then
            assert(type(value)=='table','Le comptage doit retourner une liste.')
            local sum=0;for _,line in pairs(value)do
                if method.itemField=='' or field(line,method.itemField)==itemName(item)then local n=field(line,method.amountField);assert(type(n)=='number' and n>=0 and n%1==0,'Quantité invalide.');sum=sum+n end
            end;value=sum
        end
        assert(type(value)=='number' and value>=0 and value<math.huge and value%1==0,'Quantité invalide.');return value
    end
    local function mutate(name,source,item,amount)
        local method=config.methods[name]
        local before=method.mode=='delta' and count(source,item)
        local result=invoke(name,source,item,amount)
        if method.mode=='delta'then return count(source,item)==before+(name=='add' and amount or -amount)end
        return result==true
    end
    return {configured=true,resource=config.resource,count=count,
        hasWeapon=function(source,item)return count(source,item)>0 end,
        canCarry=function(source,item,amount)return invoke('canCarry',source,item,amount)==true end,
        add=function(source,item,amount)return mutate('add',source,item,amount)end,
        remove=function(source,item,amount)return mutate('remove',source,item,amount)end}
end
return I
