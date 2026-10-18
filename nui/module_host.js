'use strict';
(() => {
  const frame=document.getElementById('market-frame');
  const resource=typeof GetParentResourceName==='function'?GetParentResourceName():'cdt_marketrobbery_light';
  let ready=false,origin='',pending=[];
  window.addEventListener('message',event=>{
    if(event.source===frame.contentWindow){
      if(event.origin===origin&&event.data?.type==='cdt:frameReady'){
        ready=true;
        frame.focus();
        for(const message of pending)frame.contentWindow.postMessage(message,origin);
        pending=[];
      }
      return;
    }
    if(ready)frame.contentWindow.postMessage(event.data,origin);
    else {pending.push(event.data);if(pending.length>200)pending.shift();}
  });
  async function initialize(){
    try{
      const result=await(await fetch(`https://${resource}/moduleRuntime`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).json();
      if(result.apiVersion!==1)throw Error('Module API');
      origin=result.premium?'https://cfx-nui-cdt_marketrobbery_premium':`https://cfx-nui-${resource}`;
      frame.src=origin+(result.premium?'/nui/index.html':'/nui/free.html');
    }catch{setTimeout(initialize,250);}
  }
  initialize();
})();
