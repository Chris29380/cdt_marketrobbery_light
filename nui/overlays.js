'use strict';
(() => {
  const promptRoot=document.getElementById('point-prompts');
  const toastRoot=document.getElementById('market-toasts');
  const dispatchRoot=document.getElementById('police-dispatch');
  const clerkWatch=document.getElementById('clerk-watch');
  const dispatches=[];
  const hint=document.getElementById('placement-hint');
  const intimidation=document.getElementById('intimidation');
  const intimidationFill=document.getElementById('intimidation-fill');
  const intimidationTime=document.getElementById('intimidation-time');
  const prompts=new Map(),toasts=[];
  function localizedNumber(value){try{return value.toLocaleString(globalThis.MarketLocale?.language||'fr');}catch{return value.toLocaleString('fr');}}
  function localizedTime(value){const options={hour:'2-digit',minute:'2-digit',second:'2-digit'};try{return value.toLocaleTimeString(globalThis.MarketLocale?.language||'fr',options);}catch{return value.toLocaleTimeString('fr',options);}}
  const paths={
    intimidate:['M12 3v6','M8 7V5a2 2 0 0 1 4 0','M8 9V7a2 2 0 0 0-4 0v7l4 7h8l4-9a2 2 0 0 0-4-1l-1 2V6a2 2 0 0 0-3 0'],
    register:['M4 10h16v11H4z','M7 3h10v7H7z','M7 14h10','M9 18h6'],
    safe:['M4 3h16v18H4z','M7 6h10v12H7z','M13 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4','M13 8v2m0 4v2m-4-4h2m4 0h2'],
    success:['m5 12 4 4L19 6'],
    error:['M12 8v5','M12 17h.01','M10.3 3.8 2.4 18a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.8a2 2 0 0 0-3.4 0'],
    warning:['M12 8v5','M12 17h.01','M12 2 2 21h20z'],
    inform:['M12 10v7','M12 6h.01','M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0'],
    placement:['M9 3H3v6m12-6h6v6M3 15v6h6m12-6v6h-6','M12 8v8m-4-4h8']
  };
  paths.inspectSafe=paths.safe;
  function node(tag,text,className){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(className)e.className=className;return e;}
  function icon(name){
    const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
    for(const [k,v] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.6','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true'}))svg.setAttribute(k,v);
    for(const d of paths[name]||paths.inform){const path=document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d',d);svg.append(path);}return svg;
  }
  function clearPrompts(){for(const entry of prompts.values())entry.root.remove();prompts.clear();}
  function showPrompts(points){
    const active=new Set(),occupied=[];
    const width=window.innerWidth||1920,height=window.innerHeight||1080;
    for(const point of (Array.isArray(points)?points:[]).slice(0,6)){
      if(!point || typeof point.id!=='string' || !Number.isFinite(point.x) || !Number.isFinite(point.y))continue;
      active.add(point.id);
      let entry=prompts.get(point.id);
      if(!entry){
        const root=node('div',undefined,'point-prompt');const glyph=node('span',undefined,'point-prompt-icon');glyph.append(icon(point.stage));
        const key=node('kbd',point.key||'E','point-prompt-key'),label=node('span',point.label,'point-prompt-label');
        root.append(glyph,key,label);promptRoot.append(root);entry={root,key,label};prompts.set(point.id,entry);
      }
      entry.key.textContent=point.disabled?'':String(point.key||'E').slice(0,12);entry.key.hidden=point.disabled===true;entry.label.textContent=String(point.label||'Interagir').slice(0,100);
      entry.root.classList.toggle('is-selected',point.selected===true);
      let x=Math.max(145,Math.min(width-145,point.x*width)),y=Math.max(65,Math.min(height-90,point.y*height));
      for(const previous of occupied)if(Math.abs(previous.x-x)<280 && Math.abs(previous.y-y)<60)y=previous.y-62;
      y=Math.max(35,y);occupied.push({x,y});entry.root.style.left=x+'px';entry.root.style.top=y+'px';
    }
    for(const [id,entry] of prompts)if(!active.has(id)){entry.root.remove();prompts.delete(id);}
  }
  function removeToast(entry){clearTimeout(entry.timer);const index=toasts.indexOf(entry);if(index!==-1)toasts.splice(index,1);entry.root.remove();}
  function removeDispatch(entry){clearTimeout(entry.timer);const index=dispatches.indexOf(entry);if(index!==-1)dispatches.splice(index,1);entry.root.remove();}
  function showDispatch(message){
    if(typeof message.location!=='string'||!message.location.trim())return;
    const duration=Number(message.duration);
    if(!Number.isFinite(duration)||duration<=0||duration>3600000)return;
    while(dispatches.length>=3)removeDispatch(dispatches[0]);
    const root=node('article',undefined,'dispatch-call');
    const header=node('header',undefined,'dispatch-header');
    const channel=node('span','CDT / DISPATCH','dispatch-channel');
    const receivedAt=new Date();
    const timestamp=node('time',localizedTime(receivedAt),'dispatch-timestamp');timestamp.setAttribute('data-no-translate','');
    header.append(channel,timestamp);
    const title=node('h2','Braquage en cours','dispatch-title');
    const status=node('span','ALERTE POLICE','dispatch-status');
    const location=node('p',message.location.slice(0,160),'dispatch-location');
    location.setAttribute('data-no-translate','');
    const footer=node('footer',undefined,'dispatch-footer');
    footer.append(node('span','Signalement actif'),node('strong',Math.ceil(duration/1000)+' s'));
    const progress=node('div',undefined,'dispatch-progress');progress.style.animationDuration=duration+'ms';
    root.append(header,status,title,location,footer,progress);dispatchRoot.append(root);
    const entry={root,timestamp,receivedAt};entry.timer=setTimeout(()=>removeDispatch(entry),duration);dispatches.push(entry);
  }
  function showToast(message){
    const text=String(message.message||'').slice(0,16000);if(!text)return;
    const kind=Object.hasOwn(paths,message.kind)?message.kind:'inform';
    const duration=Math.max(1500,Math.min(15000,Number(message.duration)||5000));
    let entry=toasts.find(e=>e.text===text && e.kind===kind);
    if(entry){entry.count++;entry.counter.textContent='×'+entry.count;clearTimeout(entry.timer);entry.progress.style.animationName='none';void entry.progress.offsetWidth;entry.progress.style.animationDuration=duration+'ms';entry.progress.style.animationName='marketToastProgress';entry.timer=setTimeout(()=>removeToast(entry),duration);return;}
    while(toasts.length>=4)removeToast(toasts[0]);
    const root=node('article',undefined,'market-toast');
    const glyph=node('div',undefined,'market-toast-icon');glyph.append(icon(kind));
    const content=node('div',undefined,'market-toast-content');
    content.append(node('p',text,'market-toast-message'));
    const counter=node('span','','market-toast-count');const progress=node('div',undefined,'market-toast-progress');progress.style.animationDuration=duration+'ms';
    root.append(glyph,content,counter,progress);toastRoot.append(root);
    entry={root,counter,progress,text,kind,count:1};entry.timer=setTimeout(()=>removeToast(entry),duration);toasts.push(entry);
  }
  function showLoot(message){
    const duration=Math.max(1500,Math.min(15000,Number(message.duration)||5000));
    for(const item of (Array.isArray(message.items)?message.items:[]).slice(0,36)){
      if(!item || typeof item.name!=='string' || !Number.isSafeInteger(item.amount) || item.amount<=0)continue;
      const key=item.kind+':'+item.name+':'+(item.image||'');
      let entry=toasts.find(e=>e.lootKey===key);
      if(entry){
        const total=entry.amount+item.amount;if(!Number.isSafeInteger(total))continue;
        entry.amount=total;entry.quantity.textContent='+'+localizedNumber(total);
        clearTimeout(entry.timer);entry.progress.style.animationName='none';void entry.progress.offsetWidth;entry.progress.style.animationName='marketToastProgress';
      }else{
        while(toasts.length>=4)removeToast(toasts[0]);
        const root=node('article',undefined,'market-toast');root.classList.add('market-toast-loot');
        const image=node('img',undefined,'loot-toast-image');
        const fallback=item.kind==='money'?'illustrations/loot.svg':'illustrations/bag.svg';
        image.alt='';image.setAttribute('aria-hidden','true');
        image.src=typeof item.image==='string' && /^https?:\/\//i.test(item.image)?item.image:fallback;
        image.onerror=()=>{image.onerror=null;image.src=fallback;};
        const content=node('div',undefined,'market-toast-content');
        const title=node('small',item.kind==='money'?'Argent récupéré':'Objet récupéré','loot-toast-title');
        const label=node('p',String(item.label||item.name).slice(0,160),'loot-toast-label');label.setAttribute('data-no-translate','');
        const quantity=node('strong','+'+localizedNumber(item.amount),'loot-toast-quantity');quantity.setAttribute('data-no-translate','');
        content.append(title,label,node('p',item.kind==='money'?'Ajouté à votre argent':'Ajouté à votre inventaire','loot-toast-detail'));
        const progress=node('div',undefined,'market-toast-progress');root.append(image,content,quantity,progress);toastRoot.append(root);
        entry={root,quantity,progress,amount:item.amount,lootKey:key};toasts.push(entry);
      }
      entry.progress.style.animationDuration=duration+'ms';entry.timer=setTimeout(()=>removeToast(entry),duration);
    }
  }
  globalThis.MarketLocale?.onChange(()=>{
    for(const entry of toasts)if(entry.lootKey)entry.quantity.textContent='+'+localizedNumber(entry.amount);
    for(const entry of dispatches)entry.timestamp.textContent=localizedTime(entry.receivedAt);
  });
  const radiusHint=node('strong','','placement-radius');hint.append(radiusHint);
  const hintIcon=document.getElementById('placement-hint-icon');hintIcon.append(icon('placement'));
  window.addEventListener('message',({data})=>{
    if(!data || typeof data.type!=='string')return;
    if(data.type==='intimidation' && intimidation){
      intimidation.classList.toggle('hidden',data.visible!==true);
      if(data.visible){
        const duration=Math.max(1,Number(data.duration)||4000);
        const elapsed=Math.max(0,Math.min(duration,Number(data.elapsed)||0));
        intimidationFill.style.width=(elapsed/duration*100)+'%';
        intimidationTime.textContent=(elapsed/1000).toFixed(1)+' / '+(duration/1000).toFixed(1)+' s';
        intimidation.setAttribute('aria-valuenow',Math.round(elapsed/duration*100));
      }
    }
    if(['admin','safe','placing','close'].includes(data.type) && intimidation)intimidation.classList.add('hidden');
    if(data.type==='prompts')showPrompts(data.points);
    if(data.type==='toast')showToast(data);
    if(data.type==='lootToast')showLoot(data);
    if(data.type==='clerkWatch' && clerkWatch){
      clerkWatch.classList.toggle('hidden',data.visible!==true);
      clerkWatch.classList.toggle('watch-lost',data.watched===false);
      if(data.visible)clerkWatch.textContent=data.watched===false?'Gardez le commerçant en vue, sinon il arrêtera de préparer le sac.':'Surveillez le commerçant pendant qu’il prépare le sac. Si vous détournez le regard, il s’arrêtera.';
    }
    if(data.type==='dispatch')showDispatch(data);
    if(data.type==='dispatchClear')for(const entry of [...dispatches])removeDispatch(entry);
    if(data.type==='placementHint'){hint.classList.toggle('hidden',data.visible!==true);if(data.visible){clearPrompts();radiusHint.textContent=Number.isFinite(data.radius)?`Rayon : ${data.radius.toFixed(1)} m · Molette pour ajuster`:'';}}
    if(['admin','safe','placing','close'].includes(data.type))clearPrompts();
    if(['admin','safe','placing','close'].includes(data.type) && clerkWatch)clerkWatch.classList.add('hidden');
    if(data.type==='close')hint.classList.add('hidden');
  });
})();
