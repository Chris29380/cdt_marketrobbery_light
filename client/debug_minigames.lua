-- Test local : aucune action, consommation ou récompense de braquage.
local S=require 'shared.safes'
local M={}
function M.start(game,now)
    return {game=game,challenge=S.challenge(game),started=now,stepTime=now}
end
function M.step(session,input,now)
    local g,c=session.game,session.challenge
    if now-session.started>g.duration*1000 then return {error='Tentative interrompue.'} end
    if type(input)~='table' then return {error='Entrée invalide.'} end
    local elapsed=now-session.stepTime
    if g.type=='drill' then
        if elapsed<350 then return {error='Mesure trop rapide.'} end
        local ok,err=S.drill(g,c,input.pressure,elapsed/1000,input.alignment)
        session.stepTime=now
        if not ok then return {error=err} end
        if c.depth>=100 then return {solved=true} end
        return {heat=c.heat,depth=c.depth,target=c.target,step=c.step,obstacle=c.obstacle}
    end
    local function angle(a,b)return math.abs((a-b+180)%360-180)end
    local a=input.angle
    local valid=type(a)=='number' and a==a and a>=0 and a<360 and angle(a,c.target)<=g.tolerance
    if g.type=='dial' then valid=valid and input.direction==c.direction
    else valid=valid and math.abs(a-c.target)<=g.tolerance and type(input.phase)=='number' and input.phase==input.phase and input.phase>=0 and input.phase<360 and angle(input.phase,c.phase)<=g.tolerance*3 end
    if not valid or elapsed<math.max(900,g.holdMs) then return {error='Combinaison incorrecte.'} end
    c.step=c.step+1;session.stepTime=now;c.direction=-c.direction
    if c.step>g.steps then return {solved=true} end
    c.target=math.random(20,339);c.phase=math.random(30,329)
    return {target=c.target,phase=c.phase,step=c.step,direction=c.direction}
end
return M
