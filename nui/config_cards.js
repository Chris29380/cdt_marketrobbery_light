'use strict';
// Illustrations locales : aucune requête externe et aucune mutation du brouillon.
window.MarketConfigCards=(()=>{
  const steps=[
    ['zone','Délimitez le magasin et sa zone de jeu.'],
    ['clerk','Choisissez le commerçant et sa position.'],
    ['scan','Repérez les caisses présentes dans le décor.'],
    ['register','Choisissez les caisses à rendre utilisables.'],
    ['animation','Ajustez les caisses et leurs animations.'],
    ['bag','Choisissez le sac et son point de réception.'],
    ['safe','Sélectionnez les coffres déjà présents.'],
    ['placement','Placez les coffres et leurs interactions.'],
    ['minigame','Réglez la difficulté du cadran mécanique.'],
    ['loot','Réglez les gains, les conditions et les délais.']
  ];
  function node(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n;}
  function picture(kind,cls){const n=node('img',cls);n.src='illustrations/'+kind+'.svg';n.alt='';n.setAttribute('aria-hidden','true');n.width=160;n.height=112;return n;}
  function kindFor(text){
    const t=text.toLocaleLowerCase('fr');
    if(/safe(point)|sécurité|otage/.test(t))return 'security';
    if(/spawn|emplacement.*client/.test(t))return 'positions';
    if(/hostage|client|population/.test(t))return 'people';
    if(/bag|sac|lancer/.test(t))return 'bag';
    if(/minigame|mini-jeu|difficult|tolérance|mécanisme/.test(t))return 'minigame';
    if(/reward|loot|butin|gain|récompense/.test(t))return 'loot';
    if(/cooldown|duration|delay|durée|délai|temps|recharge/.test(t))return 'time';
    if(/police|alarm|alerte|refus/.test(t))return 'security';
    if(/requirement|condition|règle|arme|objet requis/.test(t))return 'rules';
    if(/clerk|commerçant/.test(t))return 'clerk';
    if(/scan|détect/.test(t))return 'scan';
    if(/register|caisse/.test(t))return 'register';
    if(/safe|coffre/.test(t))return 'safe';
    if(/center|radius|location|zone|intérieur|adresse|identité/.test(t))return 'zone';
    if(/position|coordonn|orientation|placement/.test(t))return 'placement';
    return 'settings';
  }
  function section(block,heading,title){
    if(title==='Navigation')return;
    const kind=kindFor(title);block.classList.add('illustrated-section');block.dataset.illustration=kind;
    heading.append(picture(kind,'section-illustration'));
  }
  function field(wrap,path,label){wrap.classList.add('config-field-card');wrap.append(picture(kindFor(label+' '+path),'field-illustration'));}
  function step(button,index,label){
    const entry=steps[index];if(!entry)return;
    button.textContent='';button.classList.add('config-step-card');
    button.append(picture(entry[0],'step-illustration'),node('span','step-number',String(index+1).padStart(2,'0')),node('span','step-name',label));
    button.setAttribute('aria-label',(index+1)+' · '+label);
  }
  function hero(header,index){
    const entry=steps[index];if(!entry)return;
    header.classList.add('config-step-hero');header.append(picture(entry[0],'hero-illustration'),node('p','step-description',entry[1]));
  }
  function store(card){card.append(picture('zone','store-illustration'));}
  function choices(parent,path,current,options,onSelect){
    const group=node('div','illustrated-choices');group.setAttribute('role','group');
    for(const [value,label,kind]of options){const b=node('button','illustrated-choice');b.type='button';b.dataset.choice=value;b.dataset.path=path;b.setAttribute('aria-pressed',String(current===value));b.classList.toggle('selected',current===value);b.append(picture(kind,'choice-illustration'),node('strong',null,label));b.addEventListener('click',()=>onSelect(value));group.append(b);}
    parent.append(group);
  }
  return {section,field,step,hero,store,choices,steps};
})();
