'use strict';
// Les clés sont les textes français. Les paramètres {0}, {1} conservent les données dynamiques.
(() => {
  let language='fr',messages={},patterns=[],parameters={},cache=new Map();
  const originals=new WeakMap();
  const listeners=new Set();
  const escape=value=>value.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  function t(source,depth=0){
    if(typeof source!=='string')return source;
    if(depth>6)return source;
    if(Object.prototype.hasOwnProperty.call(messages,source))return messages[source];
    if(cache.has(source))return cache.get(source);
    const trimmed=source.trim();if(trimmed!==source)return source.match(/^\s*/)[0]+t(trimmed,depth+1)+source.match(/\s*$/)[0];
    const multiple=/\n|\.\s+[A-ZÀ-Ÿ]/.test(source);
    for(const {pattern,target,key} of patterns){
      const match=source.match(pattern);
      if(match){const result=target.replace(/\{(\d+)\}/g,(_,i)=>{const value=match[Number(i)+1]??'';return parameters[key]?.includes(Number(i))?t(value,depth+1):value;});if(cache.size>2048)cache.clear();cache.set(source,result);return result;}
    }
    if(multiple){const separator=source.includes('\n')?/(\n+)/: /((?<=\.)\s+(?=[A-ZÀ-Ÿ]))/;const result=source.split(separator).map((part,index)=>index%2?part:t(part,depth+1)).join('');if(cache.size>2048)cache.clear();cache.set(source,result);return result;}
    // Une traduction manquante conserve le texte français.
    if(cache.size>2048)cache.clear();cache.set(source,source);return source;
  }
  function translateValue(node,key,get,set){
    const current=get();if(!current)return;
    let values=originals.get(node);if(!values){values={};originals.set(node,values);}
    const previous=values[key],source=previous && current===previous.output?previous.source:current;
    const output=t(source);
    values[key]={source,output};if(output!==current)set(output);
  }
  function walk(node){
    for(let parent=node.parentElement;parent;parent=parent.parentElement)if(['SCRIPT','STYLE','TEXTAREA'].includes(parent.tagName)||parent.hasAttribute('data-no-translate'))return;
    if(node.nodeType===3){translateValue(node,'text',()=>node.nodeValue,v=>{node.nodeValue=v;});return;}
    if(node.nodeType!==1 || ['SCRIPT','STYLE','TEXTAREA'].includes(node.tagName) || node.hasAttribute('data-no-translate'))return;
    for(const attr of ['placeholder','aria-label','title'])if(node.hasAttribute(attr))translateValue(node,attr,()=>node.getAttribute(attr),v=>node.setAttribute(attr,v));
    for(const child of node.childNodes)walk(child);
  }
  function apply(bundle){
    if(!bundle || typeof bundle.messages!=='object' || !bundle.messages)return;
    const previous=language;
    language=bundle.language||'fr';messages=bundle.messages;parameters=bundle.translateParameters||{};cache=new Map();patterns=[];
    for(const [source,target] of Object.entries(messages)){
      if(typeof target!=='string' || !source.includes('{0}'))continue;
      const parts=source.split(/\{\d+\}/);patterns.push({pattern:new RegExp('^'+parts.map(escape).join('([^\\n]*?)')+'$'),target,key:source,weight:parts.join('').length});
    }
    patterns.sort((a,b)=>b.weight-a.weight);
    if(previous!==language)for(const listener of listeners)listener(language);
    if(document.documentElement){document.documentElement.lang=language;walk(document.documentElement);}
  }
  globalThis.MarketLocale={t,apply,onChange(fn){listeners.add(fn);return ()=>listeners.delete(fn);},get language(){return language;}};
  window.addEventListener('message',event=>{if(event.data?.type==='localization')apply(event.data.data);});
  // Observe les changements des étapes, notifications et inventaires sans modifier leurs données.
  if(typeof MutationObserver==='function' && document.body)new MutationObserver(records=>{
    for(const record of records){
      if(record.type==='childList')for(const node of record.addedNodes)walk(node);
      else if(record.type==='characterData')walk(record.target);
      else walk(record.target);
    }
  }).observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['placeholder','aria-label','title']});
})();
