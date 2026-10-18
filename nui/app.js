'use strict';
const $ = (id) => document.getElementById(id);
const clone = (value) => JSON.parse(JSON.stringify(value));
const phaseLabels = { available: 'Disponible', intimidating: 'Intimidation', active: 'Braquage actif', cooldown: 'En recharge', investigation:'Constatations police', reopening:'Remise en état' };
let config, revision, states = {}, selected = '', tab = 'home', dirty = false, pending = false, globalUntil = 0, serverOffset = 0;
let safe = null, held = 0, audio, lastFrame = 0, lastClick = 0, confirmResolve;
let safePresets = { normal: {steps:3,tolerance:7,duration:100,attempts:3,penalty:20,speed:65,holdMs:650} };
let placementContext=null;
let statistics={}, wizard=null, statsPending=false, creationPending=false;
let persistedStores=new Set();
let savedConfig=null;
let editFlows={};
let administration={},savedAdministration={},administrationRevision=0,administrationDirty=false,canAdminister=false,customInventory={};
let languages={fr:'Français',en:'English'};
const parentResource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cdt_marketrobbery_light';
async function post(name, payload = {}) {
  try {
    const response = await fetch(`https://${parentResource}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    return await response.json();
  } catch { return { error: 'Communication interrompue. Réessayez.' }; }
}
function el(tag, text, className,translate=true) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  if(!translate)node.dataset.noTranslate='';
  return node;
}
function status(text, error = false) { $('status').textContent = text; $('status').classList.toggle('error', error); }
function stableValue(value) {
  return JSON.stringify(value, function(key, entry) {
    if(entry && typeof entry==='object' && !Array.isArray(entry))return Object.fromEntries(Object.keys(entry).sort().map(k=>[k,entry[k]]));
    return entry;
  });
}
function configValue(value) {
  if(!value)return null;
  const copy=clone(value);normalizeConfig(copy);
  for(const s of copy.stores){
    for(const r of s.registers)ensureRegisterBag(r);
    for(const v of s.safes)for(const key of ['minigame','loot','requiresRegisters'])if(v.inherit?.[key])delete v[key];
  }
  return stableValue(copy);
}
function administrationValue(value) {
  const copy=clone(value);copy.inventoryCustom ||= customInventoryDefaults();
  return stableValue(copy);
}
function updateDirty() {
  administrationDirty=administrationValue(administration)!==administrationValue(savedAdministration);
  dirty=administrationDirty||configValue(config)!==configValue(savedConfig);
  $('dirty').textContent=dirty?'Modifications non enregistrées':'Configuration enregistrée';
  return dirty;
}
function markDirty() { updateDirty();if(!pending)$('save-feedback').classList.add('hidden');status(dirty?'Enregistrez pour appliquer les changements.':'Configuration enregistrée'); }
function store() { return config?.stores.find((s) => s.id === selected); }
function pathGet(path) {
  const keys = path.split('.');
  if(keys[0]==='administration')return keys.slice(1).reduce((obj,key)=>obj?.[key],administration);
  if(keys[0]==='stores' && keys[2]==='registers') {
    const s=config.stores[keys[1]], r=s?.registers[keys[3]], key=keys[4];
    if(r && r[key]===undefined) {
      const defaults=key==='duration' ? (s.settings.registerDuration ?? config.defaults.registerDuration) : key==='reward' ? (s.settings.registerReward || config.defaults.registerReward) : key==='visual' ? registerVisual(r) : undefined;
      if(defaults!==undefined) return keys.slice(5).reduce((obj,k)=>obj?.[k],defaults);
    }
  }
  if(keys[0]==='stores' && keys[2]==='safes' && keys[4]==='visual' && keys.length>5){const visual={bodyModel:'bkr_prop_biker_safebody_01a',doorModel:'bkr_prop_biker_safedoor_01a',openAngle:-70,doorOffsetX:0,doorOffsetY:0,doorOffsetZ:0,lootOffsetX:0,lootOffsetY:0,lootOffsetZ:0,...(config.stores[keys[1]].safes[keys[3]].visual||{})};return keys.slice(5).reduce((obj,key)=>obj?.[key],visual);}
  if (keys[0] === 'stores' && keys[2] === 'settings' && config.stores[keys[1]]?.settings[keys[3]] === undefined) return keys.slice(4).reduce((obj, key) => obj?.[key], config.defaults[keys[3]]);
  return keys.reduce((obj, key) => obj?.[key], config);
}
function pathSet(path, value) {
  const keys = path.split('.'); let obj = config;
  if(keys[0]==='administration'){
    if(!canAdminister)return;
    obj=administration;keys.slice(1,-1).forEach(key=>{obj[key] ||= {};obj=obj[key];});obj[keys.at(-1)]=value;
    administrationDirty=administrationValue(administration)!==administrationValue(savedAdministration);markDirty();return;
  }
  if(keys[0]==='stores' && keys[2]==='safes' && ['minigame','loot','requiresRegisters'].includes(keys[4])){const vault=config.stores[keys[1]].safes[keys[3]];if(vault.inherit)vault.inherit[keys[4]]=false;}

  if(keys[0]==='stores' && keys[2]==='registers' && keys.length>5) {
    const r=config.stores[keys[1]].registers[keys[3]];
    if(r[keys[4]]===undefined) r[keys[4]]=clone(pathGet(keys.slice(0,5).join('.')));
  }
  if (keys[0] === 'stores' && keys[2] === 'settings' && config.stores[keys[1]].settings[keys[3]] === undefined) config.stores[keys[1]].settings[keys[3]] = clone(config.defaults[keys[3]]);
  keys.slice(0, -1).forEach((key) => { if (obj[key] === undefined) obj[key] = {}; obj = obj[key]; });
  if(['x','y','z'].includes(keys.at(-1)) && obj.placement)delete obj.placement;
  obj[keys.at(-1)] = value;
  if(keys[0]==='stores' && keys[2]==='location' && ['mapping','address'].includes(keys[3])){const s=config.stores[keys[1]];s.label=(s.location.mapping+' · '+s.location.address).slice(0,100);}
  markDirty();
}
function button(text, action, className) {
  const b = el('button', text, className); b.type = 'button'; b.addEventListener('click', action); return b;
}
function confirmAction(title, text) {
  $('confirm-title').textContent = title; $('confirm-text').textContent = text;
  $('confirm').classList.remove('hidden'); $('confirm-no').focus();
  return new Promise((resolve) => { confirmResolve = resolve; });
}
function resolveConfirm(value) { $('confirm').classList.add('hidden'); if (confirmResolve) confirmResolve(value); confirmResolve = null; }
$('confirm-no').onclick = () => resolveConfirm(false);
$('confirm-yes').onclick = () => resolveConfirm(true);
function field(parent, label, path, options = {}) {
  const wrap = el('label', undefined, 'field'); wrap.append(el('span', label));
  window.MarketConfigCards?.field(wrap,path,label);
  const input = document.createElement(options.choices ? 'select' : 'input');
  input.dataset.path=path;
  if (options.choices) for (const [value, text, disabled] of options.choices) { const o = el('option', text); o.value = value; o.disabled=!!disabled; input.append(o); }
  else input.type = options.type || 'text';
  if (input.type === 'number') { input.step = options.step || '1'; if (options.min !== undefined) input.min = options.min; if (options.max !== undefined) input.max = options.max; }
  const current = pathGet(path);
  if (input.type === 'checkbox') input.checked = !!current;
  else input.value = options.format ? options.format(current) : current ?? '';
  input.addEventListener('change', () => {
    let value = input.type === 'checkbox' ? input.checked : input.type === 'number' ? Number(input.value) : input.value;
    if (options.parse) value = options.parse(value);
    const invalid = (input.type === 'number' && (!input.validity.valid || !Number.isFinite(value))) || (options.validate && !options.validate(value));
    wrap.classList.toggle('error', invalid);
    if (invalid) { status(options.error || 'Corrigez le champ : ' + label, true); return; }
    pathSet(path, value);
    if (options.after) options.after(value);
  });
  wrap.append(input); if (options.help) wrap.append(el('small', options.help)); parent.append(wrap); return input;
}
function section(title, help) {
  const block = el('section', undefined, 'section');
  const heading = el('div', undefined, 'section-heading'); heading.append(el('h3', title)); block.append(heading);
  window.MarketConfigCards?.section(block,heading,title);
  if (help) block.append(el('p', help, 'section-help'));
  $('editor').append(block); return block;
}
function grid(parent) { const g = el('div', undefined, 'grid'); parent.append(g); return g; }
function storePath() { return `stores.${config.stores.indexOf(store())}`; }
function inherit(key) {
  return `${storePath()}.settings.${key}`;
}
function settingsPath(key, defaults) { return defaults ? `defaults.${key}` : inherit(key); }
function renderList() {
  $('overview').classList.toggle('active',tab==='home');
  $('defaults-nav').classList.toggle('active',tab==='defaults');
  $('administration-nav').classList.toggle('active',tab==='administration');
  $('administration-nav').classList.toggle('hidden',!canAdminister);
  const query = $('search').value.toLocaleLowerCase('fr'); $('stores').replaceChildren();
  for (const s of config.stores) {
    if (!`${s.label} ${s.id}`.toLocaleLowerCase('fr').includes(query)) continue;
    const b = button('', () => { selected = s.id; tab=wizard?.id===s.id&&!wizard.finished?'wizard':'step0'; render(); }, s.id === selected&&!['home','defaults','administration','modules'].includes(tab) ? 'active' : '');
    b.append(el('span',s.label,undefined,false));
    const state = states[s.id], now = Math.floor(Date.now() / 1000) + serverOffset;
    const remaining = Math.max(0, (state?.phase === 'cooldown' ? state.cooldownUntil : state?.endsAt || 0) - now);
    b.append(el('span', s.enabled ? (phaseLabels[state?.phase] || 'Disponible') + (remaining ? ` · ${remaining} s` : '') : 'Désactivée')); $('stores').append(b);
  }
}
function renderMetrics() {
  const values = [ ['SUPÉRETTES', config.stores.length], ['BRAQUAGES ACTIFS', Object.values(states).filter((s) => ['active', 'intimidating'].includes(s.phase)).length], ['EN RECHARGE', Object.values(states).filter((s) => s.phase === 'cooldown').length] ];
  $('metrics').replaceChildren(...values.map(([label, value]) => { const box = el('div', undefined, 'metric'); box.append(el('span', label), el('strong', String(value))); return box; }));
}

const propCatalog = [
  {name:'prop_ld_int_safe_01',label:'Coffre compact',group:'safe'},
  {name:'p_v_43_safe_s',label:'Coffre sur pied',group:'safe'}
];
function modelImage(entry) {
  const image=el('img');image.src='models/'+entry.name+'.webp';image.alt=entry.label+' · '+entry.name;image.loading='lazy';image.width=180;image.height=120;
  image.width=140;image.height=70;image.addEventListener('error',()=>{image.hidden=true;});return image;
}
function modelField(parent,label,path,groups,options={}) {
  const block=el('div',undefined,'model-picker');
  let refresh=()=>{};
  const input=field(block,label,path,{...options,parse:v=>v.trim()||undefined,after:()=>refresh()});
  if(!input.value && options.fallback)input.value=options.fallback;
  const gallery=el('div',undefined,'model-gallery');const cards=[];
  for(const entry of propCatalog.filter(entry=>groups.includes(entry.group))) {
    const card=button('',()=>{
      pathSet(path,entry.name);
      if(/^stores\.\d+\.safes\.\d+\.model$/.test(path)){
        const base=path.replace(/\.model$/,'');
        pathSet(base+'.visual.bodyModel','bkr_prop_biker_safebody_01a');
        pathSet(base+'.visual.doorModel','bkr_prop_biker_safedoor_01a');
      }
      input.value=entry.name;refresh();
    },'model-choice');
    card.title='Utiliser '+entry.name;card.dataset.model=entry.name;
    card.append(modelImage(entry),el('strong',entry.label),el('code',entry.name));gallery.append(card);cards.push(card);
  }
  const current=el('small',undefined,'model-current');
  refresh=()=>{const value=pathGet(path)||options.fallback||'';for(const card of cards){const selected=card.dataset.model===value;card.classList.toggle('selected',selected);card.setAttribute('aria-pressed',String(selected));}current.textContent=cards.some(card=>card.dataset.model===value)?'Cliquez sur une image pour utiliser ce modèle.':'Saisie libre conservée. Aucune vignette locale pour ce modèle.';};
  refresh();block.append(gallery,current);parent.append(block);return input;
}

function pointCard(parent, title, path, { model = false, heading = false, removable } = {}) {
  const card = el('div', undefined, 'point-card'); const top = el('div', undefined, 'point-title'); top.append(el('h3', title));
  const actions = el('div', undefined, 'actions');
  const apply = (p) => { for (const key of ['x', 'y', 'z', ...(heading ? ['heading'] : [])]) pathSet(path+'.'+key,Math.round(p[key] * 100) / 100); if(p.placement)pathSet(path+'.placement',clone(p.placement)); if(path.endsWith('.visual'))pathSet(path+'.autoLocate',false); render(); };
  actions.append(button('Ma position', async () => { const p = await post('capture',model?{model:pathGet(path)?.model}:{}); if (!p.error) apply(p);else status(p.error,true); }), button('Placer en jeu', async () => { const result = await post('place', { path,mode:path.endsWith('.center')?'zone':undefined,radius:path.endsWith('.center')?store().radius:undefined,heading:pathGet(path)?.heading,preview:heading && model?{kind:path.endsWith('.clerk')?'ped':'object',model:pathGet(path)?.model}:undefined }); if (result.error) status(result.error, true); }));
  if (removable) actions.append(button('Supprimer', removable, 'danger')); top.append(actions); card.append(top);
  const g = grid(card);
  if (model) {
    if(path.includes('.safes.'))modelField(g,'Modèle du coffre fermé',path+'.model',['safe'],{help:'Le modèle fermé est remplacé en jeu par le corps et la porte séparés compatibles avec l’ouverture.'});
    else if(path.includes('.props.'))field(g,'Modèle du prop',path+'.model');
    else field(g,'Modèle',path+'.model');
  }
  for (const key of ['x', 'y', 'z']) field(g, key.toUpperCase(), path + '.' + key, { type: 'number', step: '0.01' });
  if (heading) field(g, 'Orientation', path + '.heading', { type: 'number', step: '0.01', min: 0, max: 360 });
  parent.append(card); return card;
}
function renderGeneral(includeClerk=true) {
  const s = store(), root = storePath();
  const block = section('Identité du lieu', 'L’identifiant est fixé à la création. Une supérette désactivée reste dans votre configuration.');
  const g = grid(block);
  field(g, 'Nom affiché', root + '.label', { after: () => { renderList(); $('store-title').textContent = s.label; } });
  field(g, 'Active', root + '.enabled', { type: 'checkbox', after: renderList });
  field(g, 'Rayon de participation (m)', root + '.radius', { type: 'number', min: 3, max: 80 });
  block.append(button('Visualiser et régler la zone en jeu',()=>post('place',{path:root+'.center',mode:'zone',radius:s.radius})));
  block.append(button('Se téléporter à la supérette',()=>teleportStore(s.id)));
  if(s.location){field(g,'Type de mapping',root+'.location.mapping');field(g,'Adresse',root+'.location.address');}
  pointCard(section('Zone de participation'), 'Centre du magasin', root + '.center');
  if(includeClerk)pointCard(section('Commerçant', 'Le commerçant est protégé des dégâts ; son état est reconstruit à partir de la session serveur.'), 'Commerçant', root + '.clerk', { model: true, heading: true });
}
function renderPoints() {
  const s = store(), root = storePath();
  const registers = section('Caisses', 'Chaque caisse possède un état partagé et ne peut verser qu’un seul butin par braquage.');
  registers.append(button('Rescanner les caisses du mapping',()=>{if(tab!=='wizard')tab='step2';else wizard.step=2;render();return scanWizard();}));
  s.registers.forEach((p, i) => {
    const path=`${root}.registers.${i}`;
    const card=pointCard(registers,p.id,path,{removable:()=>{if(s.registers.length<=1){status('Conservez au moins une caisse.',true);return;}s.registers.splice(i,1);markDirty();render();}});
    const model=field(card,'Modèle de caisse du décor',path+'.model',{parse:v=>v.trim().toLowerCase(),validate:v=>v==='prop_till_01',error:'Caisse incompatible : utilisez prop_till_01. Le tiroir animé utilise automatiquement p_till_01_s.',help:'Modèle accepté : prop_till_01. Remplacement automatique par p_till_01_s pour l’animation du tiroir.'});
    if(!model.value)model.value='prop_till_01';
    const g=grid(card);
    registerInheritance(g,p,path,'duration','Durée de cette caisse');registerInheritance(g,p,path,'reward','Butin de cette caisse');
    field(g,'Temps de pillage (s)',path+'.duration',{type:'number',min:2,max:300,help:'Une valeur propre à cette caisse peut remplacer le réglage du magasin.'});
    field(g,'Type de gain',path+'.reward.kind',{choices:[['money','Argent / compte'],['item','Objet']]});
    field(g,'Compte ou objet',path+'.reward.name');
    field(g,'Gain minimum',path+'.reward.min',{type:'number',min:1,max:100000});
    field(g,'Gain maximum',path+'.reward.max',{type:'number',min:1,max:100000});
    field(g,'Trouver la caisse GTA du décor',path+'.visual.autoLocate',{type:'checkbox',help:'Remplacement local par sa version animée. Désactivez pour utiliser la position manuelle.'});
    const visual=pointCard(card,'Placement de la caisse animée',path+'.visual',{heading:true}); const tune=grid(visual);
    card.append(button('Reprendre le temps et le gain du magasin',()=>{delete p.duration;delete p.reward;markDirty();render();}));
  });
  registers.append(button('+ Ajouter une caisse', async () => { if (s.registers.length >= 10) return; const p = await post('capture'); if (p.error) return; let n = 1; while (s.registers.some((r) => r.id === `caisse_${n}`)) n++; s.registers.push({ id: `caisse_${n}`, x: p.x, y: p.y, z: p.z }); markDirty(); render(); }, 'accent'));

}
function registerVisual(r) { const v={autoLocate:true,x:r.x,y:r.y,z:r.z,heading:r.heading||0,hideRadius:0.35,openPhase:0.65,offsetX:0,offsetY:0,offsetZ:0,...(r.visual||{})}; if(v.openPhase===0.32)v.openPhase=0.65; return v; }
function renderSafes() {
  const s = store(), root = storePath();
  const block = section('Coffres indépendants', 'Aucun, un ou plusieurs coffres par supérette. Chaque coffre possède son butin, son mini-jeu, ses tentatives et son occupation. Maximum 12 coffres.');
  s.safes.forEach((vault, i) => {
    const path = `${root}.safes.${i}`;
    applySafeInheritance(vault,s);
    const card = pointCard(block, vault.label, path, { model:true, heading:true, removable: async () => {
      if (await confirmAction('Supprimer ce coffre ?', 'Son prop, ses conditions et son butin seront retirés lors de l’enregistrement.')) { s.safes.splice(i,1); markDirty(); render(); }
    }});
    const g = grid(card);
    field(g, 'Nom du coffre', path+'.label');
    for(const [key,label] of [['minigame','Mini-jeu et difficulté'],['loot','Butin'],['requiresRegisters','Caisses requises']])safeInheritance(card,vault,path,key,label);
    field(g, 'Créer le prop GTA', path+'.spawnProp', {type:'checkbox',help:'Désactivez pour utiliser un coffre déjà intégré au décor.'});
    field(g, 'Caisses requises avant ce coffre', path+'.requiresRegisters', {type:'checkbox'});
    renderSafeVisual(card,path);
    renderSafeItems(card,vault,path);
    const interactionCard=pointCard(card, 'Point où le joueur interagit', path+'.interaction');
    interactionCard.append(el('p','Le coffre et ce point doivent être dans la zone du magasin, avec au maximum 4 m entre eux. Après déplacement du coffre, vérifiez aussi ce point.','section-help'));
    interactionCard.append(button('Replacer l’interaction sur le coffre',()=>{
      for(const axis of ['x','y','z']) pathSet(path+'.interaction.'+axis,vault[axis]);
      render();
    }));
    renderGame(card,path+'.minigame');
    card.append(el('h3','Butin de ce coffre'));
    card.append(el('p','Chaque ligne est tirée indépendamment selon sa probabilité. Une liste vide donne un coffre sans gain.','section-help'));
    vault.loot.forEach((reward,index)=>{
      const line=el('div',undefined,'loot-line'); const rewardPath=`${path}.loot.${index}`; const fields=grid(line);
      field(fields,'Type',rewardPath+'.kind',{choices:[['money','Argent / compte'],['item','Objet']]});
      field(fields,'Compte ou objet',rewardPath+'.name');
      field(fields,'Nom affiché (facultatif)',rewardPath+'.label',{parse:v=>v.trim()||undefined});
      field(fields,'Prop GTA du butin (facultatif)',rewardPath+'.model',{parse:v=>v.trim()||undefined,help:'Modèle physique à prendre. Vide : correspondance du script, ou colis pour un objet inconnu.'});
      field(fields,'Minimum',rewardPath+'.min',{type:'number',min:1,max:100000});
      field(fields,'Maximum',rewardPath+'.max',{type:'number',min:1,max:100000});
      field(fields,'Probabilité (%)',rewardPath+'.chance',{type:'number',min:0,max:100});
      line.append(button('Retirer ce butin',()=>{if(vault.inherit)vault.inherit.loot=false;vault.loot.splice(index,1);markDirty();render();},'danger')); card.append(line);
    });
    const add=button('+ Ligne de butin',()=>{if(vault.inherit)vault.inherit.loot=false;vault.loot.push({kind:'money',name:'cash',min:100,max:500,chance:100});markDirty();render();}); add.disabled=vault.loot.length>=12; card.append(add);
  });
  if(!s.safes.length) block.append(el('p','Cette supérette ne contient aucun coffre.','empty'));
  const add=button('+ Ajouter un coffre GTA',async()=>{
    const p=await post('capture'); if(p.error)return;
    let n=1; while(s.safes.some(v=>v.id===`coffre_${n}`))n++;
    s.safes.push({inherit:{minigame:true,loot:true,requiresRegisters:true},id:`coffre_${n}`,label:`Coffre ${n}`,model:'bkr_prop_biker_safebody_01a',spawnProp:true,...p,interaction:{x:p.x,y:p.y,z:p.z},requiresRegisters:s.settings.safeRequiresRegisters??config.defaults.safeRequiresRegisters,loot:[{...clone(s.settings.safeReward||config.defaults.safeReward),chance:100}],minigame:{type:'dial',difficulty:'normal'}});
    markDirty();render();
  },'accent'); add.disabled=s.safes.length>=12; block.append(add);
}
function renderSafeItems() {}

function renderRules() {}

const settingFields = [
  ['minPolice','Policiers en service',0,200],
  ['cooldown','Recharge de la supérette (s)',0,604800],
  ['globalCooldown','Délai global entre départs (s)',0,604800],
  ['maxDuration','Durée maximale du braquage (s)',60,7200],
  ['abandonDelay','Abandon si magasin vide (s)',10,3600],
  ['alertDelay','Délai d’alerte (s)',0,300],
  ['intimidateDuration','Durée d’intimidation (s)',2,120],
  ['registerDuration','Durée de pillage d’une caisse (s)',2,300]
];
function renderSettings(defaults = false) {
  const block = section(defaults ? 'Paramètres globaux' : 'Délais, police et difficulté', 'Le délai global limite les nouveaux braquages sur l’ensemble du serveur. Réinitialiser une supérette ne supprime pas ce délai.');
  const g = grid(block);
  if(!defaults) {
    const s=store();const wrapper=el('label',undefined,'field');wrapper.append(el('span','Quota de policiers de cette supérette'));
    const select=document.createElement('select');select.dataset.path=storePath()+'.policeQuotaMode';
    for(const [value,label] of [['global','Hériter du quota global'],['custom','Quota propre à cette supérette']]){const o=el('option',label);o.value=value;select.append(o);}
    select.value=s.settings.minPolice===undefined?'global':'custom';
    select.onchange=()=>{if(select.value==='global')delete s.settings.minPolice;else s.settings.minPolice=config.defaults.minPolice;markDirty();render();};
    wrapper.append(select,el('small',`Quota effectif : ${s.settings.minPolice??config.defaults.minPolice} policier(s) en service.`));g.append(wrapper);
    if(s.settings.minPolice!==undefined)field(g,'Minimum de policiers propre au magasin',settingsPath('minPolice',false),{type:'number',min:0,max:200});
  }
  for (const [key, label, min, max] of settingFields) if((defaults||key!=='minPolice')&&!['maxActive','alertChance','refusalChance'].includes(key)){if(!defaults)overrideControl(g,key,label+' · source');field(g, label, settingsPath(key, defaults), { type: 'number', min, max });}
  if(!defaults)overrideControl(g,'safeRequiresRegisters','Condition des coffres · source');
  field(g, 'Caisses requises par défaut pour les nouveaux coffres', settingsPath('safeRequiresRegisters', defaults), { type: 'checkbox' });
}
function renderRewards(defaults = false) {
  const block = section('Tables de récompenses', 'Le serveur choisit le montant entre les bornes. Les noms doivent exister dans votre inventaire ou votre framework. Sur ESX, cash correspond au compte money.');
  for (const [key, label] of [['registerReward', 'Gain par défaut des caisses']]) {
    const path = settingsPath(key, defaults); const card = el('div', undefined, 'point-card'); card.append(el('h3', label));if(!defaults)overrideControl(card,key,'Source des paramètres');const g = grid(card);
    field(g, 'Type', path + '.kind', { choices: [['money', 'Argent / compte'], ['item', 'Objet']] });
    field(g, 'Nom du compte ou de l’objet', path + '.name');
    field(g, 'Minimum', path + '.min', { type: 'number', min: 1, max: 100000 });
    field(g, 'Maximum', path + '.max', { type: 'number', min: 1, max: 100000 }); block.append(card);
  }
}
function render() {
  window.MarketMicrophone?.stop('Test arrêté. Microphone coupé.');
  if (!config) return;
  renderList(); renderMetrics(); $('editor').replaceChildren();
  const s = store(); $('store-title').textContent = s?.label || 'Votre configuration'; $('store-id').textContent = s?.id || 'AUCUNE SUPÉRETTE';
  const editing=!!s&&!['home','defaults','administration','activity','modules'].includes(tab);
  if(editing)$('store-title').dataset.noTranslate='';else delete $('store-title').dataset.noTranslate;
  $('metrics').classList.toggle('hidden',tab!=='home');
  $('tabs').classList.toggle('hidden',!editing||tab==='wizard');
  $('store-actions').classList.add('hidden');
  $('back-overview').classList.toggle('hidden',!editing&&tab!=='activity');
  $('save').classList.toggle('hidden',!editing&&!['defaults','administration'].includes(tab));
  $('restore').classList.toggle('hidden',tab!=='defaults');
  for (const id of ['duplicate', 'reset-store', 'delete-store']) $(id).disabled = !s || ['home','defaults','administration','modules'].includes(tab) || (id!=='delete-store' && wizard?.id===s.id && !wizard.finished);
  document.querySelectorAll('#tabs button').forEach((b) => {
    const wasActive=b.classList.contains('active');
    const step=/^step\d+$/.test(b.dataset.tab),creating=wizard?.id===selected&&!wizard.finished;
    if(step && !b.dataset.illustrated && window.MarketConfigCards){const index=Number(b.dataset.tab.slice(4));window.MarketConfigCards.step(b,index,wizardSteps[index]);b.dataset.illustrated='true';}
    b.classList.toggle('hidden',step&&(!s||['home','defaults','activity','administration','modules'].includes(tab)) || b.dataset.tab==='administration'&&!canAdminister);
    b.disabled=step&&creating&&Number(b.dataset.tab.slice(4))>wizard.reached;
    b.classList.toggle('active',b.dataset.tab===tab || step&&tab==='wizard'&&Number(b.dataset.tab.slice(4))===wizard?.step || b.dataset.tab==='step0'&&tab==='general');
    if(!wasActive && b.classList.contains('active'))b.scrollIntoView?.({block:'nearest',inline:'nearest'});
  });
  if(tab==='home'){ $('store-title').textContent='Vue d’ensemble'; $('store-id').textContent='SUPERVISION / TOUTES LES SUPÉRETTES';renderDashboard();return; }
  if(tab==='wizard' && wizard){renderWizard();return;}
  if(/^step\d+$/.test(tab) && s){const flow=currentFlow();flow.step=Number(tab.slice(4));renderWizard(flow);return;}
  if(tab==='general' && s && persistedStores.has(s.id)){const flow=currentFlow();flow.step=0;renderWizard(flow);return;}
  if(tab==='activity'){renderActivity();return;}
  if(tab==='modules'){renderModules();return;}
  if(tab==='administration'){if(canAdminister)renderAdministration();return;}
  if (tab === 'defaults') { $('store-title').textContent='Valeurs globales';$('store-id').textContent='RÉGLAGES COMMUNS AUX SUPÉRETTES';if(canAdminister){const police=section('Police : métiers et accès');police.append(button('Configurer les métiers et accès police',()=>{tab='administration';render();}));}renderSettings(true); renderRules(true); renderRewards(true); renderSafeDefaults(true); return; }
  if (!s) { $('editor').append(el('p', 'Ajoutez une supérette pour commencer.', 'empty')); return; }
  if (tab === 'general') renderGeneral();
  if (tab === 'points') renderPoints();
  if (tab === 'safes') renderSafes();
  if (tab === 'rules') renderRules();
  if (tab === 'settings') {renderSettings();renderSafeDefaults(false);}
  if (tab === 'rewards') renderRewards();
  if (['rules', 'settings', 'rewards'].includes(tab)) $('editor').append(button('Revenir aux valeurs globales pour ce magasin', async () => {
    if (await confirmAction('Utiliser les valeurs globales ?', 'Toutes les exceptions de ce magasin seront supprimées.')) { s.settings = {}; markDirty(); render(); }
  }));
}
// L’affichage d’un réglage hérité ne doit pas créer une exception persistante.
function pruneInherited() {
  return clone(config);
}
function loadAdmin(result) {
  if(result.localization){languages=result.localization.languages||languages;globalThis.MarketLocale?.apply(result.localization);}
  if(confirmResolve)resolveConfirm(false);
  config = clone(result.config); statistics=clone(result.statistics||{}); wizard=null; tab='home'; revision = result.revision; states = result.states || {}; globalUntil = result.globalUntil || 0; dirty = false;
  normalizeConfig(config);
  persistedStores=new Set(config.stores.map(s=>s.id));
  savedConfig=clone(config);
  editFlows={};
  administration=clone(result.administration||{});savedAdministration=clone(administration);administrationRevision=result.administrationRevision||0;administrationDirty=false;canAdminister=result.canAdminister===true;customInventory=result.customInventory||{};
  administration.policeCanRob??=true;savedAdministration.policeCanRob??=true;
  $('save-feedback').classList.add('hidden');
  if(result.safePresets) safePresets=clone(result.safePresets);
  serverOffset = result.serverTime ? result.serverTime - Math.floor(Date.now() / 1000) : 0;
  if (!config.stores.some((s) => s.id === selected)) selected = config.stores[0]?.id || '';
  $('connection').textContent = `${result.framework} · ${result.inventory}`; $('dirty').textContent = 'Configuration enregistrée'; status('Prêt.');
  $('admin').classList.remove('hidden'); render();
}
function normalizeConfig(value) {
  const array = (v) => Array.isArray(v) ? v : Object.values(v || {});
  function rules(r) { if (!r) return; for (const stage of Object.values(r)) { stage.weapons = array(stage.weapons); stage.items = array(stage.items); } }
  value.defaults.safeMinigame ||= {type:'dial',difficulty:'normal'};
  value.defaults.safeMinigame.type='dial';
  for(const store of array(value.stores)){if(store.settings?.safeMinigame)store.settings.safeMinigame.type='dial';for(const safe of array(store.safes))if(safe.minigame)safe.minigame.type='dial';}
  value.defaults.safeLoot = array(value.defaults.safeLoot || [{...value.defaults.safeReward,chance:100}]);
  value.stores = array(value.stores); rules(value.defaults.requirements);
  for (const s of value.stores) { if(s.settings.safeLoot)s.settings.safeLoot=array(s.settings.safeLoot); s.registers = array(s.registers); s.props = array(s.props); s.safes=array(s.safes); for(const safe of s.safes){safe.loot=array(safe.loot);if(safe.itemRequirements)safe.itemRequirements.items=array(safe.itemRequirements.items);} rules(s.settings.requirements); }
}
function uniqueId(base) { let id = base, n = 1; while (config.stores.some((s) => s.id === id)) id = base + '_' + n++; return id; }
$('overview').onclick=()=>{tab='home';render();};
$('back-overview').onclick=$('overview').onclick;
$('defaults-nav').onclick=()=>{tab='defaults';render();};
$('administration-nav').onclick=()=>{if(!canAdminister)return;tab='administration';render();};
$('search').oninput = ()=>{renderList();if(tab==='home'){ $('editor').replaceChildren();renderDashboard(); }};
document.querySelectorAll('#tabs button').forEach((b) => { b.onclick = () => {
  if(/^step\d+$/.test(b.dataset.tab) && wizard?.id===selected && !wizard.finished){const index=Number(b.dataset.tab.slice(4));if(index>wizard.reached)return;wizard.step=index;tab='wizard';}
  else tab=b.dataset.tab;
  render();
}; });
$('add-store').onclick = startWizard;
$('duplicate').onclick = () => { if (!store()) return; const s = clone(store()); s.id = uniqueId(s.id + '_copie'); s.label += ' · copie'; s.enabled = false; config.stores.push(s); selected = s.id; markDirty(); render(); };
$('delete-store').onclick = () => deleteStore(selected);
$('reload').onclick = async () => { if (updateDirty() && !await confirmAction('Abandonner les modifications ?', 'La configuration du serveur remplacera votre brouillon.')) return; const r = await post('reload'); if (r.error) status(r.error, true); else loadAdmin(r); };
$('save').onclick = async () => {
  if (pending || confirmResolve) return;
  if(tab==='administration'){await saveAdministration();return;}
  if(wizard && !wizard.finished){status('Terminez les étapes de création avant d’enregistrer.',true);return;}
  pending = true; $('save').disabled = true;saveFeedback('saving','Enregistrement en cours…');$('save').textContent='Enregistrement…';
  const submitted=pruneInherited();
  const r = await post('save', { config: submitted, revision }); pending = false; $('save').disabled = false;
  $('save').textContent='Enregistrer les modifications';
  if (r.error) {status(r.error, true);saveFeedback('error','Enregistrement refusé.');} else { revision = r.revision; persistedStores=new Set(submitted.stores.map(s=>s.id));savedConfig=clone(submitted);updateDirty();if(wizard?.finished)wizard=null; $('dirty').textContent=dirty?'Modifications non enregistrées':'Configuration enregistrée';status(dirty?'Enregistrement effectué. Les modifications plus récentes restent à enregistrer.':'Les modifications sont appliquées.');saveFeedback('saved','Enregistré avec succès'); }
};
function saveFeedback(kind,text){
  const feedback=$('save-feedback');feedback.classList.remove('hidden','saving','saved','error');feedback.classList.add(kind);feedback.textContent=text;
}
async function saveAdministration(){
  if(!canAdminister||pending)return;
  pending=true;$('save').disabled=true;saveFeedback('saving','Enregistrement en cours…');
  const submitted=clone(administration);
  const result=await post('saveAdministration',{settings:submitted,revision:administrationRevision});
  pending=false;$('save').disabled=false;
  if(result.error){status(result.error,true);saveFeedback('error','Enregistrement refusé.');return;}
  administrationRevision=result.revision;savedAdministration=clone(result.administration||submitted);
  administrationDirty=administrationValue(administration)!==administrationValue(savedAdministration);
  updateDirty();
  $('dirty').textContent=dirty?'Modifications non enregistrées':'Configuration enregistrée';
  $('connection').textContent=result.framework+' · '+result.inventory;
  status('Réglages administratifs appliqués.');saveFeedback('saved','Administration enregistrée');
}
function renderAdministration(){
 $('store-title').textContent='Administration du script';$('store-id').textContent='CDT MARKET ROBBERY LIGHT';
 const g=grid(section('Langue'));field(g,'Langue du script','administration.language',{choices:Object.entries(languages)});
 const b=grid(section('Framework et inventaire'));
 field(b,'Framework','administration.framework',{choices:[['auto','Détection automatique'],['qbox','Qbox'],['qbcore','QBCore'],['esx','ESX']]});
 field(b,'Bridge inventaire','administration.inventory',{choices:[['auto','Détection automatique'],['ox','Ox Inventory'],['qb','QB Inventory'],['qs','Quasar Inventory'],['origen','Origen Inventory'],['core','Core Inventory'],['tgiann','TGIANN Inventory'],['jaksam','Jaksam Inventory'],['framework','Inventaire du framework']]});
 const diagnostic=grid(section('Diagnostic des coffres', 'Traces dans les consoles serveur et F8 : inventaire, retraits et fonctionnement des coffres.'));
 field(diagnostic,'Activer le debug','administration.debug',{choices:[['off','Désactivé'],['on','Activé']],format:v=>v===true?'on':'off',parse:v=>v==='on'});
 const p=grid(section('Police : métiers et accès'));
 field(p,'Métiers police (séparés par des virgules)','administration.policeJobs',{format:v=>Object.keys(v||{}).filter(k=>v[k]).join(', '),parse:v=>Object.fromEntries(v.split(',').map(x=>x.trim()).filter(Boolean).map(x=>[x,true]))});
 const n=grid(section('Interactions et notifications', 'Le système interne est utilisé par défaut. Le bridge personnalisé se configure dans client/notifications_custom.lua.')); 
 field(n,'Notifications','administration.notifications',{choices:[['cdt','Notifications intégrées'],['ox','Ox Lib'],['okok','okokNotify'],['wasabi','Wasabi Notify'],['brutal','Brutal Notify'],['mythic','Mythic Notify'],['quasar','Quasar Interface'],['qb','QBCore Notify'],['esx','ESX Notify'],['custom','Personnalisé'],['off','Désactivées']],parse:v=>v==='off'?false:v,format:v=>v===false?'off':v});
 }


function customInventoryDefaults(){
  const method=(mode,args)=>({export:'',args,path:'',returns:1,mode});
  return {mode:'file',resource:'',itemCase:'preserve',methods:{count:{...method('number',['source','item']),itemField:'name',amountField:'amount'},canCarry:method('boolean',['source','item','amount']),add:method('boolean',['source','item','amount']),remove:method('boolean',['source','item','amount'])}};
}


$('reset-store').onclick = () => resetFromDashboard(selected);
$('restore').onclick = async () => { if (!await confirmAction('Charger la sauvegarde précédente ?', 'Elle remplacera votre brouillon. Vérifiez-la, puis enregistrez pour l’appliquer.')) return; const r = await post('backup'); if (r.error) status(r.error, true); else { config = clone(r.config); normalizeConfig(config); selected = config.stores[0]?.id || ''; markDirty(); render(); status('Sauvegarde chargée dans le brouillon.'); } };
async function close() {
  if (!$('confirm').classList.contains('hidden')) { resolveConfirm(false); return; }
  if (!$('admin').classList.contains('hidden') && updateDirty() && !await confirmAction('Fermer sans enregistrer ?', 'Vos modifications non enregistrées seront perdues.')) return;
  await post('close');
}
document.querySelectorAll('.close').forEach((b) => { b.onclick = close; });
function sound(hint, now) {
  if (!$('sound').checked || now-lastClick<45) return;
  try {
    audio ||= new (window.AudioContext || window.webkitAudioContext)();
    if (audio.state==='suspended') audio.resume();
    const osc=audio.createOscillator(), gain=audio.createGain();
    osc.type=hint?'sine':'triangle'; osc.frequency.setValueAtTime(hint?720:260,audio.currentTime);
    osc.frequency.exponentialRampToValueAtTime(hint?480:110,audio.currentTime+(hint?.055:.018));
    gain.gain.setValueAtTime(hint?.018:.025,audio.currentTime);
    gain.gain.exponentialRampToValueAtTime(.001,audio.currentTime+(hint?.065:.025));
    osc.connect(gain); gain.connect(audio.destination); osc.start(); osc.stop(audio.currentTime+.08);
    osc.onended=()=>{osc.disconnect();gain.disconnect();}; lastClick=now;
  } catch { /* L’indice graphique reste disponible. */ }
}
// 15 graduations du cadran (0–99), soit 54 degrés de chaque côté.
function moveDial(movement) {
  const offset=(safe.angle-safe.target+540)%360-180;
  const forward=Math.sign(movement)===safe.direction;
  const staysInside=Math.abs(offset)<=54 && Math.abs(offset+movement)<=54;
  safe.angle=((safe.angle+movement)%360+360)%360;
  const distance=Math.abs((safe.angle-safe.target+540)%360-180);
  if(movement){
    safe.adjustmentArmed=forward?distance<=54:!!safe.adjustmentArmed && staysInside;
    safe.lastDirection=Math.sign(movement);
  }
}
function dialDirectionAllowed() {
  return safe.lastDirection===safe.direction || !!safe.adjustmentArmed && Math.abs((safe.angle-safe.target+540)%360-180)<=54;
}
function advanceDial(now) {
  if(!safe || safe.game.type!=='dial' || !held || safe.waiting || safe.turnUpdated==null)return 0;
  const elapsed=Math.max(0,now-safe.turnUpdated)/1000;
  safe.turnUpdated=Math.max(now,safe.turnUpdated);
  const movement=held*safe.game.speed*elapsed;
  moveDial(movement);
  return movement;
}
function setDialHeld(direction, now=performance.now()) {
  if(held===direction)return;
  advanceDial(now);
  held=direction;
  if(!safe || safe.game.type!=='dial')return;
  safe.turnUpdated=null;
  if(!direction || safe.waiting)return;
  // Un appui donne une graduation ; le maintien prend le relais après 180 ms.
  moveDial(direction*3.6);
  safe.turnUpdated=now+180;
  safe.lastDirection=direction;safe.stableSince=0;$('dial-validate').disabled=true;
  const distance=Math.abs((safe.angle-safe.target+540)%360-180);
  sound(dialDirectionAllowed() && distance<=safe.tolerance,now);
}
function showDialDirection() {
  $('safe-direction').textContent=safe.direction===1?'Tournez vers la droite →':'← Tournez vers la gauche';
}
async function validateDial() {
  if (!safe || safe.game.type==='drill' || safe.waiting || performance.now() - safe.stepStarted < Math.max(1000,safe.game.holdMs) || !safe.stableSince || performance.now() - safe.stableSince < safe.game.holdMs) return;
  if(safe.game.type==='dial' && (held || !dialDirectionAllowed())) return;
  safe.waiting = true;
  const r = await post('safeStep', { angle: safe.game.type==='electronic' ? Number($('signal-frequency').value) : safe.angle, phase:Number($('signal-phase').value), direction: safe.game.type==='dial' && dialDirectionAllowed()?safe.direction:safe.lastDirection });
  if (!safe) return;
  if (r.error || r.solved) { safe = null; return; }
  safe.target = r.target; safe.phase = r.phase; safe.step = r.step; safe.direction = r.direction; safe.stepStarted = performance.now(); safe.stableSince = 0; safe.waiting = false; held = 0; safe.lastDirection=0; safe.adjustmentArmed=false; if(safe.game.type==='dial')showDialDirection();
}
$('dial-validate').onclick = validateDial;
for (const [id, direction] of [['dial-left', -1], ['dial-right', 1]]) {
  $(id).onpointerdown = (event) => { setDialHeld(direction); event.currentTarget.setPointerCapture(event.pointerId); };
  $(id).onpointerup = () => setDialHeld(0);
  $(id).onpointercancel = () => { held=0; if(safe)safe.turnUpdated=null; };
}
window.addEventListener('blur', () => { held = 0; if(safe)safe.turnUpdated=null; });
window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { e.preventDefault(); close(); }
  if (!safe) return;
  if (safe.game.type==='dial' && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) { e.preventDefault(); setDialHeld(e.key === 'ArrowLeft' ? -1 : 1); }
  if (e.key === 'Enter') { e.preventDefault(); validateDial(); }
});
window.addEventListener('keyup', (e) => { if ((e.key === 'ArrowLeft' && held===-1) || (e.key === 'ArrowRight' && held===1)) setDialHeld(0); });
function updateSafeTimer(now) {
  const remaining=Math.max(0,Math.ceil((safe.deadline-now)/1000));
  $('safe-timer').textContent=String(Math.floor(remaining/60)).padStart(2,'0')+':'+String(remaining%60).padStart(2,'0');
  $('safe-timer').classList.toggle('is-urgent',remaining<=10);
  return remaining;
}
function animate(now) {
  const elapsedSeconds = Math.max(0, (now - lastFrame) / 1000); lastFrame = now;
  const dt = Math.min(elapsedSeconds, 0.05);
  if (safe) {
    if(safe.game.type==='dial') {
    // La vitesse est en degrés/seconde, sans plafond lié à la fréquence des images.
    const moving=held && !safe.waiting;
    const previousAngle=safe.angle;
    const movement=moving?(safe.turnUpdated==null?held*safe.game.speed*elapsedSeconds:advanceDial(now)):0;
    if(moving && safe.turnUpdated==null)moveDial(movement);
    const distance=Math.abs((safe.angle-safe.target+540)%360-180);
    const correctDirection=!safe.waiting && dialDirectionAllowed();
    const near=correctDirection && distance<=safe.tolerance;
    if(near && !held) safe.stableSince ||= now; else safe.stableSince=0;
    const stable=safe.stableSince && now-safe.stableSince>=safe.game.holdMs;
    $('dial-validate').disabled=safe.waiting || !stable;
    $('dial-value').textContent=String(Math.floor(safe.angle/3.6)).padStart(2,'0');
    $('dial').style.backgroundPosition='center';$('dial').classList.toggle('near',near);
    $('dial').style.setProperty('background',`repeating-conic-gradient(from ${safe.angle-1}deg,#79808c 0deg 1deg,transparent 1deg 10deg),radial-gradient(circle,#101317 0 58%,#30353b 59% 65%,#111419 66%)`);
    $('safe-cue').textContent=stable?'Le cran tient. Appuyez sur Entrée pour le maintenir.':near?'Un cran accroche. Relâchez le cadran et gardez la main immobile.':correctDirection && distance<35?'Une vibration se précise… Cherchez doucement le cran.':'Tournez doucement le cadran. Sentez le mécanisme sous vos doigts.';
    showDialDirection();
    // Un clic par graduation franchie ; le cran utile a un timbre plus doux et plus long.
    if(moving && Math.floor(previousAngle/3.6)!==Math.floor((previousAngle+movement)/3.6)) sound(near,now);
    } else if(safe.game.type==='electronic') {
      const frequency=Number($('signal-frequency').value), phase=Number($('signal-phase').value);
      const distance=Math.abs(frequency-safe.target), phaseDistance=Math.abs((phase-safe.phase+540)%360-180);
      if(distance<=safe.tolerance && phaseDistance<=safe.tolerance*3) safe.stableSince ||= now; else safe.stableSince=0;
      const stable=safe.stableSince && now-safe.stableSince>=safe.game.holdMs;
      $('dial-validate').disabled=safe.waiting || !stable;
      $('safe-cue').textContent=stable ? 'Signal stabilisé. Validez ce canal.' : 'Superposez le signal gris au signal vert.';
      $('safe-direction').textContent='Canal '+safe.step+' · fréquence et phase';
      const wave=(frequency,phase)=>{let path='';for(let x=0;x<=400;x+=4){const y=65+Math.sin(x/400*Math.PI*2*(1+frequency/60)+phase/180*Math.PI)*40;path+=(x?'L':'M')+x+','+y.toFixed(2);}return path;};
      $('signal-reference').setAttribute('d',wave(safe.target,safe.phase)); $('signal-input').setAttribute('d',wave(frequency,phase));
    } else {
      safe.displayDepth+=(safe.depth-safe.displayDepth)*Math.min(1,dt*10);
      $('drill-cutaway').style.setProperty('--penetration',String(safe.displayDepth/100));
      $('drill-carriage').classList.toggle('is-spinning',Number($('drill-pressure').value)>0);
      $('drill-cutaway').classList.toggle('is-hot',safe.heat>75);
      $('drill-layer-label').textContent=`COUCHE ${safe.step} / ${safe.steps}`;
      $('drill-cut-depth').textContent=Math.floor(safe.displayDepth)+' % de l’épaisseur franchie';
      for(const [index,layer] of [...$('lock-layers').children].entries()){layer.classList.toggle('is-drilled',safe.depth>=(index+1)/safe.steps*100);layer.classList.toggle('is-current',index===safe.step-1);}
      const obstacle=safe.obstacle;
      $('drill-challenge').classList.toggle('hidden',!obstacle);
      $('drill-alignment-field').classList.toggle('hidden',obstacle?.kind!=='align');
      if(obstacle){
        const titles={release:'Décompression du mécanisme',align:'Vibration de la mèche',steady:'Résistance renforcée'};
        $('drill-challenge-title').textContent=titles[obstacle.kind]||'Défi de couche';
        $('drill-challenge-text').textContent=obstacle.kind==='release'?'Relâchez la pression et maintenez-la sous 5 %.':obstacle.kind==='align'?`Relâchez la pression et stabilisez le correcteur sur ${obstacle.target} %.`:`Maintenez une pression stable autour de ${safe.target} %.`;
        $('drill-challenge-meter').value=obstacle.progress/obstacle.required*100;
        $('drill-challenge-time').textContent=Math.max(0,Math.ceil(obstacle.limit-obstacle.elapsed-(now-safe.lastMeasure)/1000))+' s';
      }
      $('safe-cue').textContent=obstacle?'Passage bloqué : terminez le défi pour poursuivre.':safe.heat>75 ? 'Chauffe élevée. Relâchez la pression.' : 'Maintenez la pression dans la zone indiquée.';
      $('safe-direction').textContent='La progression de la mèche et les défis sont contrôlés par le serveur';
      $('drill-depth').value=safe.depth; $('drill-heat').value=safe.heat;
      $('drill-depth-value').textContent=Math.floor(safe.depth)+' %'; $('drill-heat-value').textContent=Math.floor(safe.heat)+' %';
      const band=Math.max(4,safe.tolerance*1.5); $('drill-band').textContent=`Zone de pression : ${Math.ceil(safe.target-band)} à ${Math.floor(safe.target+band)} %`;
    }
    $('safe-step').textContent = `CRAN ${safe.step} / ${safe.steps}`;
    const remaining = updateSafeTimer(now);
    if (!remaining && !safe.waiting) { safe.waiting = true; post('safeFail'); }
  }
  requestAnimationFrame(animate);
}
requestAnimationFrame(animate);
setInterval(async()=>{
  if(!safe || safe.game.type!=='drill' || safe.waiting)return;
  const attempt=safe; attempt.waiting=true;
  const r=await post('safeStep',{pressure:Number($('drill-pressure').value),alignment:Number($('drill-alignment').value)});
  if(safe!==attempt)return;
  if(r.error || r.solved){safe=null;return;}
  safe.heat=r.heat; safe.depth=r.depth; safe.target=r.target; safe.step=r.step; safe.obstacle=r.obstacle; safe.lastMeasure=performance.now(); safe.waiting=false;
},650);
setInterval(() => { const remaining = Math.max(0, globalUntil - Math.floor(Date.now() / 1000) - serverOffset); $('global-timer').textContent = remaining ? `Délai global : ${remaining} s` : 'Nouveaux braquages autorisés'; if (config && !$('admin').classList.contains('hidden')) renderList(); }, 1000);
window.addEventListener('message', ({ data: message }) => {
  if (!message || typeof message.type !== 'string') return;
  if (message.type === 'admin') { $('safe').classList.add('hidden'); loadAdmin(message.data); }
  if (message.type === 'live') { states = message.states; globalUntil = message.globalUntil || 0; if (message.serverTime) serverOffset = message.serverTime - Math.floor(Date.now() / 1000); if (config) { renderList(); renderMetrics(); if(tab==='home'||tab==='activity'){const scroll=$('editor').scrollTop;render();$('editor').scrollTop=scroll;} } }
  if (message.type === 'close') { if(confirmResolve)resolveConfirm(false);$('admin').classList.add('hidden'); $('safe').classList.add('hidden'); $('confirm').classList.add('hidden'); safe = null; held = 0; }
  if (message.type === 'placing') {
    placementContext={selected,tab,editorScroll:$('editor').scrollTop,storesScroll:$('stores').scrollTop};
    $('admin').classList.add('hidden');
  }
  if (message.type === 'placed') {
    $('admin').classList.remove('hidden');
    if(placementContext){selected=placementContext.selected;tab=placementContext.tab;}
    if (!message.cancelled && message.point) { const p = pathGet(message.path); const previous=p?clone(p):null; if (p) for (const k of ['x', 'y', 'z', ...('heading' in p ? ['heading'] : [])]) pathSet(message.path+'.'+k,Math.round(message.point[k] * 100) / 100); if(message.point.placement)pathSet(message.path+'.placement',clone(message.point.placement)); if(previous && /^stores\.\d+\.safes\.\d+$/.test(message.path) && previous.interaction){const angle=((p.heading||0)-(previous.heading||0))*Math.PI/180,dx=previous.interaction.x-previous.x,dy=previous.interaction.y-previous.y;pathSet(message.path+'.interaction',{x:p.x+dx*Math.cos(angle)-dy*Math.sin(angle),y:p.y+dx*Math.sin(angle)+dy*Math.cos(angle),z:p.z+previous.interaction.z-previous.z});} if(message.point.radius && message.path.endsWith('.center'))pathSet(message.path.replace(/center$/, 'radius'),message.point.radius); if(message.path.endsWith('.visual'))pathSet(message.path+'.autoLocate',false); render(); status('Coordonnées du point validées. Enregistrez pour les appliquer.'); }
    else status('Prise de coordonnées annulée. Le brouillon est conservé.');
    if(placementContext){$('editor').scrollTop=placementContext.editorScroll;$('stores').scrollTop=placementContext.storesScroll;placementContext=null;}
  }
  if (message.type === 'safe') {
    $('admin').classList.add('hidden'); $('safe').classList.remove('hidden');
    safe = { ...message.data,game:message.data.game || {type:'dial',holdMs:650,speed:65}, angle: 0, step: 1, heat:0,depth:0,displayDepth:0,obstacle:null,lastMeasure:performance.now(),lastDirection: 0, waiting: false, stepStarted: performance.now(), deadline: performance.now() + (message.data.game?.duration ?? message.data.duration) * 1000 }; held = 0;
    updateSafeTimer(performance.now());
    const type=safe.game.type;
    if(type==='dial')showDialDirection();
    $('safe-title').textContent=type==='dial'?'Gardez la main sûre.':type==='drill'?'Gardez le contrôle.':'Trouvez la synchronisation.';
    $('safe-label').textContent=safe.label || 'Coffre';
    $('dial-area').classList.toggle('hidden',type!=='dial'); $('drill-game').classList.toggle('hidden',type!=='drill'); $('electronic-game').classList.toggle('hidden',type!=='electronic');
    $('dial-controls').classList.toggle('hidden',type==='drill'); $('dial-left').classList.toggle('hidden',type!=='dial'); $('dial-right').classList.toggle('hidden',type!=='dial');
    $('safe-help').textContent=type==='dial'?'← / → Tourner le cadran · Entrée Maintenir le cran · Échap Lâcher le coffre':type==='drill'?'Réglez la pression avec le curseur · Échap pour abandonner':'Réglez les deux curseurs · Entrée pour valider · Échap pour abandonner';
    $('drill-pressure').value=0; $('drill-alignment').value=0; $('signal-frequency').value=0; $('signal-phase').value=0; $('dial-validate').disabled=true;
    $('lock-layers').replaceChildren(...Array.from({length:safe.steps},(_,index)=>el('div',String(index+1).padStart(2,'0'),'lock-layer')));
    if(type!=='drill') $('dial-validate').focus(); else $('drill-pressure').focus();
  }
});

function appendLoot(parent,values){
  const list=Array.isArray(values)?values:Object.values(values||{});
  if(!list.length){parent.append(el('span','Aucun butin'));return parent;}
  list.forEach((v,index)=>{
    if(index)parent.append(el('span',' · '));
    parent.append(el('span',`${v.amount} ${v.name}`,undefined,false));
    if(v.status&&v.status!=='paid')parent.append(el('span',' ('),el('span',({unknown:'paiement à vérifier',failed:'échec de paiement'}[v.status]||v.status)),el('span',')'));
  });return parent;
}
function sessionDate(timestamp){
  try{return new Date(timestamp*1000).toLocaleString((globalThis.MarketLocale?.language||'fr').replaceAll('_','-'));}
  catch{return new Date(timestamp*1000).toLocaleString('fr');}
}
globalThis.MarketLocale?.onChange(()=>{if(config&&!$('admin').classList.contains('hidden'))render();});
function stateText(value) { return ({ready:'Disponible',busy:'En cours',looted:'Vidé',paid:'Réussi',payment_failed:'Paiement partiel ou échoué',payment_pending:'Paiement à vérifier',partial:'Butin partiellement récupéré',open:'Ouvert · butin restant',opened:'Coffre ouvert',reserved:'Lot en cours de récupération',completed:'Braquage terminé',reset:'Réinitialisé',interrupted:'Interrompu au redémarrage',expired_or_abandoned:'Terminé / abandonné',active:'En cours',intimidating:'Intimidation',intimidation_failed:'Intimidation échouée',intimidation_cancelled:'Intimidation annulée',clerk_refused:'Refus du commerçant'})[value]||value||'Disponible'; }
async function refreshStatistics() {
  if(statsPending || !config || $('admin').classList.contains('hidden'))return;
  statsPending=true; const result=await post('statistics'); statsPending=false;
  if(result.error)return;
  statistics=result.statistics||{};states=result.states||{};globalUntil=result.globalUntil||0;
  if(result.serverTime)serverOffset=result.serverTime-Math.floor(Date.now()/1000);
  if(tab==='home'||tab==='activity'){const scroll=$('editor').scrollTop;render();$('editor').scrollTop=scroll;}
}
let teleportPending=false;
async function teleportStore(id){
  if(teleportPending)return;
  if(!persistedStores.has(id)){status('Enregistrez cette supérette avant de vous y téléporter.',true);return;}
  teleportPending=true;status('Téléportation en cours…');
  const result=await post('teleportStore',{id});teleportPending=false;
  status(result.error||result.message,!!result.error);
}
async function resetFromDashboard(id) {
  if(pending||confirmResolve)return;
  if(!persistedStores.has(id)){status('Enregistrez cette nouvelle supérette avant de la réinitialiser.',true);return;}
  if(!await confirmAction('Réinitialiser cette supérette ?', 'Les caisses et coffres seront libérés. L’historique et le délai global sont conservés.'))return;
  if(pending)return;
  pending=true;
  const result=await post('reset',{id});pending=false;status(result.error||result.message,!!result.error);
  if(!result.error)await refreshStatistics();
}
async function deleteStore(id) {
  if(pending||confirmResolve)return;
  const target=config.stores.find(s=>s.id===id);if(!target)return;
  const expectedRevision=revision;
  if(!await confirmAction('Supprimer « '+target.label+' » ?', 'La supérette sera supprimée immédiatement après confirmation. Les actions en cours seront annulées. Les autres modifications du brouillon sont conservées.'))return;
  if(pending)return;
  let result={ok:true};
  if(persistedStores.has(id)){
    pending=true;result=await post('deleteStore',{id,revision:expectedRevision});pending=false;
    if(result.error){status(result.error,true);return;}
    revision=result.revision;persistedStores.delete(id);
  }
  config.stores=config.stores.filter(s=>s.id!==id);
  if(savedConfig)savedConfig.stores=savedConfig.stores.filter(s=>s.id!==id);
  if(wizard?.id===id)wizard=null;
  if(selected===id)selected=config.stores[0]?.id||'';
  if(result.states)states=result.states;else delete states[id];
  updateDirty();
  $('dirty').textContent=dirty?'Modifications non enregistrées':'Configuration enregistrée';
  render();status('Supérette supprimée. Aucun enregistrement supplémentaire nécessaire.');
}
function renderDashboard() {
  const top=section('Supervision des supérettes','États actuels, résultats et butins confirmés. Les statistiques sont conservées en SQL après les réinitialisations.');
  const actions=el('div',undefined,'actions');
  actions.append(button('+ Créer une supérette',startWizard,'accent'),button('Actualiser les états',refreshStatistics));
  if(wizard)actions.append(button('Reprendre la création',()=>{selected=wizard.id;tab='wizard';render();}));
  top.append(actions);
  const grid=el('div',undefined,'overview-grid');top.append(grid);
  const query=$('search').value.toLocaleLowerCase('fr');
  const visible=config.stores.filter(s=>`${s.label} ${s.id}`.toLocaleLowerCase('fr').includes(query));
  for(const s of visible){
    const st=states[s.id]||{},stats=statistics[s.id]||{};
    const card=el('article',undefined,'point-card dashboard-store');
    window.MarketConfigCards?.store(card);
    const title=el('div',undefined,'point-title');title.append(el('h3',s.label,undefined,false),el('span',s.enabled?(phaseLabels[st.phase]||'Disponible'):'Désactivée','badge'));card.append(title);
    card.append(el('p',s.id,'store-command'),el('p',`${stats.started||0} braquage(s) · ${stats.completed||0} terminé(s) · ${stats.resets||0} reset(s)`,'section-help'));
    card.append(el('p',s.location?.address||'Adresse non renseignée','overview-address'));
    card.append(el('p',`${s.registers.length} caisse(s) · ${s.safes.length} coffre(s) · Rayon ${s.radius} m`,'overview-details'));
    const now=Math.floor(Date.now()/1000)+serverOffset;
    const until=['cooldown','investigation'].includes(st.phase)?st.cooldownUntil:st.endsAt;
    if(until)card.append(el('p',`${st.phase==='cooldown'?'Recharge':'Temps restant'} : ${Math.max(0,until-now)} s`,'section-help'));
    const counts=(values)=>{const list=Object.values(values||{});return `${list.filter(v=>(v.status||v)==='looted').length}/${list.length}`;};
    card.append(el('p',`Caisses vidées : ${counts(st.registers)} · Coffres vidés : ${counts(st.safes)}`));
    const totals=el('p',undefined,'section-help');totals.append(el('span','Butin cumulé confirmé : '));card.append(appendLoot(totals,stats.totals));
    const controls=el('div',undefined,'actions');controls.append(button('Modifier',()=>{selected=s.id;tab='general';render();},'accent'),button('Se téléporter',()=>teleportStore(s.id)),button('Résultats détaillés',()=>{selected=s.id;tab='activity';render();}),button('Reset',()=>resetFromDashboard(s.id)),button(s.enabled?'Désactiver':'Activer',()=>{s.enabled=!s.enabled;markDirty();render();}),button('Supprimer',()=>deleteStore(s.id),'danger'));card.append(controls);grid.append(card);
  }
  if(!config.stores.length)top.append(el('p','Aucune supérette. Entre dans un intérieur, puis lance la création.','empty'));
  else if(!visible.length)top.append(el('p','Aucune supérette ne correspond à la recherche.','empty'));
}
function renderActivity() {
  const s=store();if(!s){renderDashboard();return;}
  const block=section('Historique · '+s.label,'30 derniers braquages conservés par supérette ; les totaux cumulés ne sont pas limités à ces 30 sessions. Un paiement à vérifier nécessite de consulter les journaux.');
  block.append(button('Réinitialiser cette supérette',()=>resetFromDashboard(s.id)));
  const stats=statistics[s.id]||{};
  const totals=el('p',undefined,'section-help');totals.append(el('span','Total confirmé : '));block.append(appendLoot(totals,stats.totals));
  for(const session of Object.values(stats.sessions||{})){
    const card=el('div',undefined,'point-card');
    card.append(el('h3',stateText(session.outcome)),el('p',sessionDate(session.startedAt)+' · '+session.id,'section-help',false));
    for(const point of Object.values(session.points||{})){
      const line=el('p',undefined,'point-summary');line.append(el('span',point.stage==='register'?'Caisse':'Coffre'),el('span',' '+point.point+' · ',undefined,false),el('span',point.player||'Joueur',undefined,!point.player),el('span',' · '),el('span',stateText(point.status)),el('span',' · '));card.append(appendLoot(line,point.loot));
    }
    if(!Object.keys(session.points||{}).length)card.append(el('p','Aucune caisse ni aucun coffre vidé.'));
    block.append(card);
  }
  if(!Object.values(stats.sessions||{}).length)block.append(el('p','Aucun braquage enregistré depuis l’installation du suivi.','empty'));
}
function overrideControl(parent,key,label) {
  const s=store(),wrap=el('label',undefined,'field');wrap.append(el('span',label));const select=document.createElement('select');
  for(const [value,text] of [['global','Utiliser les paramètres globaux'],['custom','Paramètres propres à cette supérette']]){const option=el('option',text);option.value=value;select.append(option);}
  select.dataset.path=storePath()+'.override.'+key;select.value=s.settings[key]===undefined?'global':'custom';
  select.onchange=()=>{if(select.value==='global')delete s.settings[key];else s.settings[key]=clone(config.defaults[key]);markDirty();render();};wrap.append(select);parent.append(wrap);
}
function applySafeInheritance(vault,s) {
  const inherited=vault.inherit||{};
  if(inherited.minigame)vault.minigame=clone(s.settings.safeMinigame||config.defaults.safeMinigame);
  if(inherited.loot)vault.loot=clone(s.settings.safeLoot||config.defaults.safeLoot);
  if(inherited.requiresRegisters)vault.requiresRegisters=s.settings.safeRequiresRegisters??config.defaults.safeRequiresRegisters;
}
function safeInheritance(parent,vault,path,key,label) {
  const wrap=el('label',undefined,'field');wrap.append(el('span',label));const select=document.createElement('select');
  for(const [value,text] of [['inherit','Hériter des paramètres de la supérette / globaux'],['custom','Réglage propre à ce coffre']]){const option=el('option',text);option.value=value;select.append(option);}
  select.value=vault.inherit?.[key]?'inherit':'custom';select.dataset.path=path+'.inherit.'+key;
  select.onchange=()=>{vault.inherit ||= {};vault.inherit[key]=select.value==='inherit';markDirty();render();};wrap.append(select);parent.append(wrap);
}
function renderGame(parent,path) {
  parent.append(el('p','Mini-jeu utilisé : Cadran mécanique','section-help'));
  const labels={easy:'Facile',normal:'Normal',hard:'Difficile',expert:'Expert'};
  const choices=Object.keys(safePresets).map(key=>[key,labels[key]||key]);
  const current=pathGet(path);
  if(current.difficulty==='custom')parent.append(el('p','Réglage personnalisé existant. Sélectionnez un niveau pour le remplacer.','section-help'));
  const g=grid(parent);
  field(g,'Force du coffre',path+'.difficulty',{choices,after:()=>{delete pathGet(path).custom;render();}});
  const preset=safePresets[current.difficulty];
  if(preset)parent.append(el('p',`${preset.steps} étapes · ${preset.duration} s · ${preset.attempts} tentative(s) · attente après échec ${preset.penalty} s`,'section-help'));
}

function renderLoot(parent,path) {
  const list=pathGet(path);
  list.forEach((reward,index)=>{
    const row=el('div',undefined,'point-card'),g=grid(row),root=path+'.'+index;
    field(g,'Type',root+'.kind',{choices:[['money','Argent / compte'],['item','Objet']]});field(g,'Compte ou objet',root+'.name');field(g,'Nom affiché (facultatif)',root+'.label',{parse:v=>v.trim()||undefined});
    field(g,'Minimum',root+'.min',{type:'number',min:1,max:100000});field(g,'Maximum',root+'.max',{type:'number',min:1,max:100000});field(g,'Probabilité (%)',root+'.chance',{type:'number',min:0,max:100});
    row.append(button('Retirer ce butin',()=>{const next=clone(pathGet(path));next.splice(index,1);pathSet(path,next);render();},'danger'));parent.append(row);
  });
  const add=button('+ Ligne de butin',()=>{const next=clone(pathGet(path));next.push({kind:'money',name:'cash',min:100,max:500,chance:100});pathSet(path,next);render();});add.disabled=list.length>=12;parent.append(add);
}
function renderSafeDefaults(defaults) {
  const game=section('Mini-jeu hérité par les coffres','Chaque coffre peut conserver cet héritage ou utiliser son propre réglage.');
  if(!defaults)overrideControl(game,'safeMinigame','Mini-jeu de la supérette');renderGame(game,settingsPath('safeMinigame',defaults));
  const loot=section('Butin hérité par les coffres','Chaque ligne est tirée indépendamment. Une liste vide donne un coffre vide.');
  if(!defaults)overrideControl(loot,'safeLoot','Butin de la supérette');renderLoot(loot,settingsPath('safeLoot',defaults));
}
const wizardSteps=['Zone','Commerçant','Détection des caisses','Choix des caisses','Caisses animées','Sacs et points de lancer','Coffres du décor','Placement des coffres','Force des coffres','Butins et règles'];
function currentFlow(){
  if(tab==='wizard' && wizard)return wizard;
  return editFlows[selected] ||= {id:selected,step:0,reached:12,scan:null,finished:true,editing:true};
}
async function startWizard() {
  if(wizard){selected=wizard.id;tab='wizard';render();return;}
  if(creationPending)return;creationPending=true;
  const context=await post('creationContext');creationPending=false;if(context.error){status(context.error,true);return;}
  const s={id:context.id,label:context.label,enabled:false,center:clone(context.center),radius:18,clerk:{...clone(context.center),heading:context.heading,model:'mp_m_shopkeep_01'},registers:[],safes:[],props:[],settings:{},location:{interiorHash:context.interiorHash,mapping:context.mapping,address:context.address}};
  config.stores.push(s);selected=s.id;wizard={id:s.id,step:0,reached:0,scan:null,finished:false};tab='wizard';markDirty();render();
}
function detectedKey(p){return [p.model,p.x.toFixed(2),p.y.toFixed(2),p.z.toFixed(2)].join(':');}
function nextPointId(list,prefix){let n=1;while(list.some(p=>p.id===prefix+n))n++;return prefix+n;}
async function scanWizard() {
  const draft=currentFlow(),s=store();if(!s||draft.scanning)return;draft.scanning=true;
  const result=await post('scanInterior',{center:clone(s.center),radius:s.radius,interiorHash:s.location?.interiorHash});draft.scanning=false;
  if(!config.stores.includes(s) || selected!==s.id || currentFlow()!==draft)return;
  if(result.error){status(result.error,true);return;}draft.scan=result;render();status(`${result.registers.length} caisse(s) et ${result.safes.length} coffre(s) détectés. Les coordonnées existantes ne sont pas écrasées sans votre choix.`);
}
function detectedMatches(found,list){
  const result=new Map(),used=new Set();
  for(const point of found){const match=list.find(p=>p.detectionKey===detectedKey(point));if(match){result.set(point,match);used.add(match);}}
  for(const point of found){
    if(result.has(point))continue;
    const candidates=list.filter(p=>!used.has(p)&&(p.original?.model||p.model||'prop_till_01')===point.model)
      .map(p=>({p,d:Math.hypot((p.original||p).x-point.x,(p.original||p).y-point.y,(p.original||p).z-point.z)})).filter(v=>v.d<=3).sort((a,b)=>a.d-b.d);
    if(candidates.length){result.set(point,candidates[0].p);used.add(candidates[0].p);}
  }
  return result;
}
function updateRegisterCoordinates(target,point){
  for(const key of ['x','y','z','heading','model'])target[key]=point[key];
  delete target.placement;
  target.original=clone(point.original||{x:point.x,y:point.y,z:point.z,heading:point.heading,model:point.model});
  target.replacementModel='p_till_01_s';target.detectionKey=detectedKey(point);
  target.visual={...registerVisual(target),x:point.x,y:point.y,z:point.z,heading:point.heading,autoLocate:false};
}
function refreshDetectedRegisters(){
  const s=store(),found=currentFlow().scan?.registers||[],matches=detectedMatches(found,s.registers);
  for(const [point,target] of matches)updateRegisterCoordinates(target,point);
  if(matches.size){markDirty();render();}
  status(`${matches.size} caisse(s) actualisée(s). Réglages et identifiants conservés. Enregistrez pour appliquer.`);
}
function chooseDetected(parent,kind) {
  const s=store(),list=kind==='register'?s.registers:s.safes,found=currentFlow().scan?.[kind==='register'?'registers':'safes']||[],matches=detectedMatches(found,list);
  for(const point of found){
    const key=detectedKey(point),wrap=el('label',undefined,'field'),input=document.createElement('input');input.type='checkbox';input.dataset.detectedKey=key;input.dataset.kind=kind;input.checked=matches.has(point);
    input.onchange=()=>{
      const index=list.indexOf(matches.get(point));
      if(!input.checked){if(index>=0)list.splice(index,1);}else if(index<0){
        if(list.length>=(kind==='register'?10:12)){input.checked=false;status('Nombre maximum de points atteint.',true);return;}
        const p={...clone(point),id:nextPointId(list,kind==='register'?'caisse_':'coffre_'),detectionKey:key};
        if(kind==='register')p.visual={...registerVisual(p),autoLocate:false};
        else Object.assign(p,{label:'Coffre '+(list.length+1),spawnProp:false,interaction:{x:p.x,y:p.y,z:p.z},requiresRegisters:true,loot:[],minigame:{type:'dial',difficulty:'normal'},inherit:{minigame:true,loot:true,requiresRegisters:true}});
        list.push(p);
      }
      markDirty();render();
    };
    wrap.append(input,el('span',`${point.model} · ${point.x.toFixed(2)}, ${point.y.toFixed(2)}, ${point.z.toFixed(2)} · orientation ${point.heading.toFixed(1)}°`));parent.append(wrap);
  }
  if(!found.length)parent.append(el('p','Aucun modèle compatible détecté. Relancez le scan dans la bonne zone ou utilisez le placement manuel.','section-help'));
}
function wizardError(step) {
  const s=store(),distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y,a.z-b.z);
  if(!s.label?.trim()||!Number.isFinite(s.radius)||s.radius<3||s.radius>80)return 'Renseignez le nom et un rayon entre 3 et 80 m.';
  if(step>=1 && distance(s.clerk,s.center)>s.radius)return 'Placez le commerçant dans la zone de la supérette.';
  if(step>=3 && !s.registers.length)return 'Sélectionnez au moins une caisse ou placez-la manuellement.';
  if(step>=4 && s.registers.some(p=>distance(p,s.center)>s.radius))return 'Une caisse est hors de la zone.';
  if(step>=7 && s.safes.some(p=>distance(p,s.center)>s.radius||distance(p.interaction,s.center)>s.radius||distance(p,p.interaction)>4))return 'Vérifiez les coffres et leurs interactions : dans la zone et à 4 m maximum l’un de l’autre.';
  if(step>=5 && s.registers.some(p=>!p.bag?.model?.trim()||!p.bag.drop||distance(p.bag.drop,s.center)>s.radius))return 'Définissez un prop et un point de dépôt dans la supérette pour chaque caisse.';
  return null;
}
function renderWizard(flow=wizard) {
  const s=store(),root=storePath();if(!s)return;
  $('store-id').textContent=s.id+(flow.editing?' · MODIFICATION PAR ÉTAPES':' · CRÉATION GUIDÉE');
  const header=section(`Étape ${flow.step+1} / ${wizardSteps.length} · ${wizardSteps[flow.step]}`,'Retour possible à chaque étape. Les valeurs et les choix restent dans votre brouillon jusqu’à l’enregistrement.');
  window.MarketConfigCards?.hero(header,flow.step);
  if(flow.step===0){renderGeneral(false);const b=section('Intérieur détecté');b.append(el('p',`${s.location?.mapping||'Mapping à préciser'} · ${s.location?.address||'Adresse à préciser'} · intérieur ${s.location?.interiorHash||'non renseigné'}`),el('p','Vous pouvez préciser le type de mapping dans le champ ci-dessus. Le nom a été construit à partir de l’intérieur et de la rue.','section-help'));}
  if(flow.step===1){pointCard(section('Position et orientation du commerçant','Placez le fantôme avec la boule verte. Flèches gauche/droite pour tourner, Entrée pour valider.'),'Commerçant',root+'.clerk',{model:true,heading:true});}
  if(flow.step===2){const b=section('Détecter les caisses compatibles','Placez-vous dans le mapping. Le scan retrouve les caisses du décor sans effacer vos choix ni vos réglages.');const scan=button(flow.scanning?'Détection en cours…':'Rescanner les caisses du mapping',scanWizard,'accent');scan.disabled=flow.scanning;b.append(scan);if(flow.scan){b.append(el('p',`${flow.scan.registers.length} caisse(s) compatible(s) détectée(s).`),button('Actualiser les coordonnées des caisses existantes',refreshDetectedRegisters));chooseDetected(b,'register');}}
  if(flow.step===3){const b=section('Caisses à braquer','Cochez les caisses que vous souhaitez rendre utilisables.');b.append(button('Relancer la détection',scanWizard));if(flow.scan)b.append(button('Actualiser les coordonnées des caisses existantes',refreshDetectedRegisters));chooseDetected(b,'register');b.append(button('Ajouter une caisse manuellement',async()=>{const p=await post('capture');if(p.error)return;s.registers.push({id:nextPointId(s.registers,'caisse_'),x:p.x,y:p.y,z:p.z,heading:p.heading,model:'prop_till_01',replacementModel:'p_till_01_s'});markDirty();render();}));}
  if(flow.step===4){const b=section('Coordonnées et remplacement animé','Les positions détectées sont conservées. Ajustez le point si nécessaire ; les caisses sélectionnées partageront l’état du braquage.');for(const p of s.registers)b.append(el('p',`${p.id} · ${p.model||'prop_till_01'} → p_till_01_s · ${p.x.toFixed(2)}, ${p.y.toFixed(2)}, ${p.z.toFixed(2)}`,'point-summary'));renderPoints();}
  if(flow.step===6){const b=section('Coffres du décor','Les coffres sélectionnés utilisent le prop déjà présent, sans en créer un second.');b.append(button('Détecter / actualiser les objets',scanWizard));chooseDetected(b,'safe');}
  if(flow.step===7){const b=section('Placement des coffres','Ajoutez un prop ou ajustez un coffre. Flèches gauche/droite : rotation. Entrée : valider. Échap : annuler.');
    s.safes.forEach((v,i)=>{const path=root+'.safes.'+i;pointCard(b,v.label,path,{model:true,heading:true,removable:()=>{s.safes.splice(i,1);markDirty();render();}});field(b,'Créer un prop pour '+v.id,path+'.spawnProp',{type:'checkbox'});renderSafeVisual(b,path);pointCard(b,'Interaction · '+v.id,path+'.interaction');b.append(button('Interaction sur '+v.id,()=>{v.interaction={x:v.x,y:v.y,z:v.z};markDirty();render();}));});
    b.append(button('+ Ajouter un coffre avec prévisualisation',async()=>{if(s.safes.length>=12)return;const p=await post('capture');if(p.error)return;const id=nextPointId(s.safes,'coffre_');s.safes.push({id,label:'Coffre '+id,model:'prop_ld_int_safe_01',spawnProp:true,x:p.x,y:p.y,z:p.z,heading:p.heading,interaction:{x:p.x,y:p.y,z:p.z},requiresRegisters:true,loot:[],minigame:{type:'dial',difficulty:'normal'},inherit:{minigame:true,loot:true,requiresRegisters:true}});markDirty();render();const path=root+'.safes.'+(s.safes.length-1);await post('place',{path,heading:p.heading,preview:{kind:'object',model:'bkr_prop_biker_safebody_01a'}});}));}
  if(flow.step===8){const settings=section('Force des coffres de la supérette');overrideControl(settings,'safeMinigame','Source des paramètres');renderGame(settings,settingsPath('safeMinigame',false));s.safes.forEach((v,i)=>{applySafeInheritance(v,s);const path=root+'.safes.'+i,b=section(v.label);safeInheritance(b,v,path,'minigame','Mini-jeu');renderGame(b,path+'.minigame');renderSafeItems(b,v,path);});}
  if(flow.step===9){renderSettings();renderRules();renderRewards();renderSafeDefaults(false);const b=section('Réglages par point');s.registers.forEach((r,i)=>{const path=root+'.registers.'+i,card=el('div',undefined,'point-card');card.append(el('h3',r.id));registerInheritance(card,r,path,'duration','Durée');registerInheritance(card,r,path,'reward','Butin');field(card,'Durée propre à cette caisse',path+'.duration',{type:'number',min:2,max:300});for(const [key,label] of [['kind','Type'],['name','Compte ou objet'],['min','Minimum'],['max','Maximum']])field(card,label,path+'.reward.'+key,key==='kind'?{choices:[['money','Argent / compte'],['item','Objet']]}:['min','max'].includes(key)?{type:'number',min:1,max:100000}:{});card.append(button('Hériter du temps et du gain de la supérette',()=>{delete r.duration;delete r.reward;markDirty();render();}));b.append(card);});s.safes.forEach((v,i)=>{applySafeInheritance(v,s);const card=el('div',undefined,'point-card'),path=root+'.safes.'+i;card.append(el('h3',v.label));safeInheritance(card,v,path,'loot','Butin');renderLoot(card,path+'.loot');safeInheritance(card,v,path,'requiresRegisters','Caisses requises');field(card,'Vider les caisses avant ce coffre',path+'.requiresRegisters',{type:'checkbox'});b.append(card);});field(b,'Activer cette supérette après enregistrement',root+'.enabled',{type:'checkbox'});}
  if(flow.step===5)renderRegisterBags();
  const footer=section('Navigation');const controls=el('div',undefined,'actions');const back=button('← Étape précédente',()=>{flow.step--;if(flow.editing)tab='step'+flow.step;render();});back.disabled=flow.step===0;controls.append(back);
  controls.append(button(flow.step===wizardSteps.length-1?(flow.editing?'Vérifier les modifications':'Terminer et vérifier'):'Étape suivante →',()=>{const error=wizardError(flow.step);if(error){status(error,true);return;}if(flow.step===wizardSteps.length-1){flow.finished=true;tab=flow.editing?'step0':'general';render();status(flow.editing?'Modifications prêtes. Enregistrez pour les appliquer.':'Création prête. Vérifiez puis enregistrez pour appliquer la supérette.');return;}flow.step++;flow.reached=Math.max(flow.reached,flow.step);if(flow.editing)tab='step'+flow.step;render();$('editor').scrollTop=0;},'accent'));
  controls.append(button('Accueil (conserver le brouillon)',()=>{tab='home';render();}));footer.append(controls);
}
setInterval(()=>{if(tab==='home'||tab==='activity')refreshStatistics();},5000);
function ensureRegisterBag(register){
  if(register.bag)return;
  const v=registerVisual(register),h=(v.heading||0)*Math.PI/180;
  register.bag={model:'prop_poly_bag_01',drop:{x:v.x+0.85*Math.sin(h),y:v.y-0.85*Math.cos(h),z:v.z,heading:0}};
}
function renderRegisterBags(){
  const s=store(),root=storePath();
  const block=section('Sacs et points de lancer','Pour chaque caisse, choisissez le prop et placez son point d’arrivée côté clients. Le sac et son point de ramassage utiliseront cette position.');
  for(let index=0;index<s.registers.length;index++){
    const register=s.registers[index],path=root+'.registers.'+index;
    ensureRegisterBag(register);
    const card=el('div',undefined,'point-card');card.append(el('h3','Sac · '+register.id));
    const input=field(card,'Prop à lancer',path+'.bag.model',{parse:v=>v.trim().toLowerCase(),help:'Par défaut : prop_poly_bag_01. Vous pouvez saisir un autre modèle d’objet GTA valide.'});
    const actions=el('div',undefined,'actions');
    actions.append(button('Sac standard',()=>{pathSet(path+'.bag.model','prop_poly_bag_01');input.value='prop_poly_bag_01';}),button('Placer le sac en jeu',()=>post('place',{path:path+'.bag.drop',heading:register.bag.drop.heading||0,preview:{kind:'object',model:register.bag.model}}),'accent'));
    card.append(actions);pointCard(card,'Point d’arrivée et de ramassage',path+'.bag.drop',{heading:true});block.append(card);
  }
  if(!s.registers.length)block.append(el('p','Ajoutez d’abord les caisses à l’étape « Choix des caisses ».','empty'));
}





function registerInheritance(parent,point,path,key,label){
  const wrap=el('label',undefined,'field');wrap.append(el('span',label));const select=document.createElement('select');
  for(const [value,text] of [['inherit','Hériter de la supérette / du global'],['custom','Réglage propre à cette caisse']]){const option=el('option',text);option.value=value;select.append(option);}
  select.dataset.path=path+'.inherit.'+key;select.value=point[key]===undefined?'inherit':'custom';
  select.onchange=()=>{if(select.value==='inherit')delete point[key];else point[key]=clone(pathGet(path+'.'+key));markDirty();render();};wrap.append(select);parent.append(wrap);
}

function renderSafeVisual() {}

let detectedModules=null,detectingModules=false,applyingModules=false;
$('detect-modules').onclick=scanModules;
async function scanModules(){
  if(detectingModules||applyingModules)return;
  tab='modules';detectingModules=true;render();
  const result=await post('modulesStatus');detectingModules=false;
  if(result.error){status(result.error,true);render();return;}
  detectedModules=result;render();
}
async function applyModules(){
  if(applyingModules||detectingModules)return;
  if(updateDirty()){status('Enregistrez vos modifications avant d’activer le module.',true);return;}
  applyingModules=true;render();
  const result=await post('applyModules');
  if(result.error){applyingModules=false;status(result.error,true);render();return;}
  status('Activation du module en cours. La configuration va se rouvrir automatiquement.');
}
function renderModules(){
  $('store-title').textContent='Modules';$('store-id').textContent='CDT MARKET ROBBERY';
  const block=section('Détection des modules','Démarrez le module sur le serveur, puis lancez la détection.');
  const scan=button(detectingModules?'Détection en cours…':'Détecter les modules',scanModules);scan.disabled=detectingModules||applyingModules;block.append(scan);
  if(!detectedModules)return;
  for(const module of detectedModules.modules||[]){
    const card=el('div',undefined,'point-card');card.append(el('h3',module.name),el('p',module.label));
    card.append(el('p','Otages, enquêtes et réglages avancés.'));
    block.append(card);
  }
  if(detectedModules.reason)block.append(el('p',detectedModules.reason,'section-help'));
  if(detectedModules.canApply){
    block.append(el('p','L’activation recharge brièvement la Light pour tous les joueurs, puis rouvre votre configuration.','section-help'));
    const apply=button(applyingModules?'Activation en cours…':'Activer le module maintenant',applyModules,'accent');
    apply.disabled=applyingModules||detectingModules||updateDirty();block.append(apply);
    if(dirty)block.append(el('p','Enregistrez vos modifications avant d’activer le module.','section-help'));
  }
}
