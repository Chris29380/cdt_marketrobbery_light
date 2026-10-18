'use strict';
(() => {
  const panel = document.getElementById('inventory');
  const stock = document.getElementById('inventory-stock');
  const status = document.getElementById('inventory-status');
  let view = null, pending = false, generation = 0;
  let transferError='';
  async function take(payload){
    try { const result=await post('inventoryTake',payload);return result && typeof result==='object'?result:{error:'Le serveur ne répond pas.'}; }
    catch { return {error:'Le serveur ne répond pas.'}; }
  }
  const quantities = new Map();
  function updateStock(next){
    if(!view || !next || next.store!==view.store || next.point!==view.point)return;
    if(Number.isFinite(view.revision) && (!Number.isFinite(next.revision) || next.revision<view.revision))return;
    view=next;
  }
  function render() {
    const focused=document.activeElement?.dataset?.chunk;
    stock.replaceChildren();
    document.getElementById('inventory-title').textContent = view.label || 'Coffre';
    if(view.label)document.getElementById('inventory-title').dataset.noTranslate='';else delete document.getElementById('inventory-title').dataset.noTranslate;
    const lots = (view.chunks || []).filter(lot => lot.status !== 'taken');
    if(transferError)status.textContent=transferError;
    else if(view.canTake===false&&lots.length)status.textContent='Ce coffre est uniquement consultable.';
    document.getElementById('inventory-all').disabled=pending || view.canTake===false || !lots.some(lot=>lot.status==='ready');
    const visible=new Set(lots.map(lot=>lot.id));
    for(const id of quantities.keys())if(!visible.has(id))quantities.delete(id);
    document.getElementById('inventory-count').textContent = `${lots.length} lot${lots.length === 1 ? '' : 's'} restant${lots.length === 1 ? '' : 's'}`;
    for (const lot of lots) {
      const card = document.createElement('article'); card.className = 'point-card inventory-lot';
      const name = document.createElement('h3'); name.textContent = lot.label || lot.name;
      name.dataset.noTranslate='';
      const amount = document.createElement('p'); amount.className = 'muted'; amount.textContent = `Quantité : ${lot.amount}`;
      const button = document.createElement('button'); button.className = 'accent';
      const quantity = document.createElement('input');quantity.type='number';quantity.min=1;quantity.step=1;quantity.max=lot.amount;
      quantity.value=quantities.has(lot.id)?quantities.get(lot.id):lot.amount;
      if(Number(quantity.value)>lot.amount)quantity.value=lot.amount;
      quantity.dataset.chunk=lot.id;quantity.disabled=pending||view.canTake===false||lot.status!=='ready';
      quantity.oninput=()=>quantities.set(lot.id,quantity.value);
      quantity.setAttribute('aria-label','Quantité à récupérer');
      const image = document.createElement('img');
      const fallback=lot.kind==='money'?'illustrations/loot.svg':'illustrations/bag.svg';
      image.alt=lot.label||lot.name;
      image.src=typeof lot.image==='string'&&/^https?:\/\//i.test(lot.image)?lot.image:fallback;
      image.onerror=()=>{image.onerror=null;image.src=fallback;};
      button.textContent = lot.status === 'reserved' ? 'En cours de récupération…' : 'Prendre → Mon inventaire';
      button.disabled = pending || view.canTake===false || lot.status !== 'ready';
      button.onclick = async () => {
        if (pending || view.canTake===false || lot.status !== 'ready') return;
        const amount=Number(quantity.value);
        if(!Number.isSafeInteger(amount)||amount<1||amount>lot.amount){status.textContent='Saisissez une quantité entière entre 1 et '+lot.amount+'.';return;}
        const session = generation; transferError=''; pending = true; render(); status.textContent = 'Transfert en cours…';
        const result = await take({ chunk: lot.id, quantity: amount });
        if (session !== generation || !view) return;
        updateStock(result.inventory);
        if(!result.error)quantities.delete(lot.id);
        transferError=result.error||'';pending = false; render(); status.textContent = result.error || result.message || 'Transfert terminé.';
      };
      card.append(name, amount, button, image, quantity); stock.append(card);
      if(focused===lot.id && !quantity.disabled)quantity.focus();
    }
    if (!lots.length) { const empty = document.createElement('p'); empty.className = 'empty'; empty.textContent = 'Le coffre est vide.'; stock.append(empty); }
  }
  document.getElementById('inventory-close').onclick = () => post('close');
  document.getElementById('inventory-all').onclick = async () => {
    if(pending||!view||view.canTake===false)return;
    const session=generation;
    const lots=(view.chunks||[]).filter(l=>l.status==='ready').map(l=>l.id);
    if(!lots.length)return;
    transferError='';pending=true;render();status.textContent='Transfert en cours…';
    let stopped=false,lastError='';
    for(const id of lots){
      if(session!==generation||!view)break;
      if(view.canTake===false){lastError='Ce coffre est uniquement consultable.';stopped=true;break;}
      const lot=(view.chunks||[]).find(l=>l.id===id&&l.status!=='taken');
      if(!lot)continue;
      const result=await take({chunk:id,quantity:lot.amount,all:true});
      if(session!==generation||!view)break;
      updateStock(result.inventory);
      render();
      status.textContent=result.error||result.message||'Transfert terminé.';
      if(result.error){lastError=result.error;if(result.continue!==true){stopped=true;break;}}
    }
    if(session===generation&&view){
      transferError=lastError;pending=false;render();
      if(stopped && lastError)status.textContent=lastError;
      if(!stopped && (view.chunks||[]).some(l=>l.status!=='taken'))status.textContent=lastError||'Récupération terminée. Certains lots restent dans le coffre.';
    }
  };
  window.addEventListener('message', ({ data }) => {
    if (!data) return;
    if (data.type === 'inventory') {
      generation++; pending = false; transferError='';quantities.clear(); view = data.data;
      status.textContent = 'Choisissez un lot à transférer dans votre inventaire.';
      panel.classList.remove('hidden'); render();
    } else if (data.type === 'inventoryProgress' && view && pending) {
      status.textContent=`Transfert en cours… ${Math.max(0,Math.min(100,Math.floor(Number(data.percent)||0)))} %`;
    } else if (data.type === 'inventoryLive' && view) { updateStock(data.data);render(); }
    else if (['close', 'admin', 'safe', 'police'].includes(data.type)) {
      generation++; view = null; pending = false; quantities.clear(); panel.classList.add('hidden');
    }
  });
})();
