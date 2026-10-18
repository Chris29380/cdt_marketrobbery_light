-- Historique administrateur distinct des états publics et conservé après reset.
local T={}
function T.record(all,id)
    if not all[id] then all[id]={started=0,completed=0,resets=0,totals={},pointTotals={},sessions={}} end
    return all[id]
end
function T.start(all,id,token,now)
    local r=T.record(all,id)
    r.started=r.started+1
    local session={id=token,startedAt=now,outcome='intimidating',points={}}
    table.insert(r.sessions,1,session)
    while #r.sessions>30 do table.remove(r.sessions) end
    r.current=token
    return session
end
function T.current(all,id)
    local r=all[id]; if not r or not r.current then return nil end
    for _,s in ipairs(r.sessions) do if s.id==r.current then return s end end
end
function T.activate(all,id)
    local s=T.current(all,id); if s then s.outcome='active' end
end
function T.reserve(all,id,stage,point,rewards,player,token,now,append,sessionId)
    local s=T.current(all,id)
    if sessionId then
        s=nil
        for _,session in ipairs(T.record(all,id).sessions) do if session.id==sessionId then s=session;break end end
    end
    if not s then return nil end
    local previous=append and s.points[stage..':'..point]
    local result=previous or {stage=stage,point=point,player=player,token=token,time=now,status='payment_pending',loot={}}
    local offset=#result.loot
    result.status='payment_pending'
    for _,v in ipairs(rewards) do result.loot[#result.loot+1]={kind=v.kind,name=v.name,amount=v.amount,status='unknown',player=player,time=now,token=token} end
    s.points[stage..':'..point]=result
    return result,offset
end
function T.payment(all,id,result,index,success)
    if not result then return end
    local v=result.loot[index]
    if v.status~='unknown' then return end
    v.status=success and 'paid' or 'failed'
    if success then
        local r=T.record(all,id); local key=v.kind..':'..v.name
        local total=r.totals[key] or {kind=v.kind,name=v.name,amount=0}; r.totals[key]=total
        total.amount=total.amount+v.amount
        r.pointTotals=r.pointTotals or {}
        local pointKey=result.stage..':'..result.point
        local totals=r.pointTotals[pointKey] or {}; r.pointTotals[pointKey]=totals
        local pointTotal=totals[key] or {kind=v.kind,name=v.name,amount=0}; totals[key]=pointTotal
        pointTotal.amount=pointTotal.amount+v.amount
    end
end
function T.finish(all,id,reason,now)
    local r=T.record(all,id); local s=T.current(all,id)
    if s then s.outcome=reason; s.endedAt=now; r.current=nil; if reason=='completed' then r.completed=r.completed+1 end end
end
function T.reset(all,id,now)
    T.record(all,id).resets=T.record(all,id).resets+1
    T.finish(all,id,'reset',now)
end
return T
