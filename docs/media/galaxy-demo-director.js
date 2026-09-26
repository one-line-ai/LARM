const puppeteer=require('puppeteer-core');const fs=require('fs');const path=require('path');
const S=__dirname; const FPS=30; const DT=1000/FPS;
const T=[]; const at=(s,fn)=>T.push([s,fn]);
(async()=>{
  const browser=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:'new',args:['--allow-file-access-from-files','--hide-scrollbars','--font-render-hinting=none']});
  const VERT=!!process.env.VERT; const page=await browser.newPage(); await page.setViewport(VERT?{width:640,height:1138,deviceScaleFactor:1.6875}:{width:1280,height:800,deviceScaleFactor:1});
  await page.goto('file://'+path.join(S,'a/b/web/director.html'),{waitUntil:'load'});
  page.on('pageerror',e=>console.log('PAGEERR',e.message)); await page.waitForFunction(()=>typeof G!=='undefined'&&G&&G.nodes.length>0);
  await page.evaluate(()=>{document.fonts&&document.fonts.ready; document.getElementById('ds-real').style.display='none';document.getElementById('ds-demo').style.display='none';document.querySelector('#top .sub').style.display='none';document.querySelector('#top h1').style.display='none'; setPaused(true);});
  if(VERT){await page.evaluate(()=>{const st=document.createElement('style');st.textContent=`#cap{bottom:auto !important;top:140px !important;font-size:23px;padding:14px 20px;max-width:90vw;border-radius:12px} #card h1{font-size:40px} #card p{font-size:19px;max-width:86vw} #top{max-width:96vw} #panel{max-height:42vh} #crumb{display:none !important}`;document.body.appendChild(st);});}
  await new Promise(r=>setTimeout(r,800));
  const ev=(fn,...a)=>page.evaluate(fn,...a);
  const cursorNode=id=>ev(id=>{const p=__nodePos(id); if(p){__cur.tx=p[0];__cur.ty=p[1];}},id);
  const cursorEl=sel=>ev(sel=>{const p=__elPos(sel);__cur.tx=p[0];__cur.ty=p[1];},sel);
  const clickNode=id=>ev(id=>{__cur.click=220;focusNode(G.idx.get(id));},id);
  const cap=t=>ev(t=>__caption(t),t);
  const FIND_HIGH=await ev(()=>G.nodes.find(n=>n.type==='Finding'&&n.severity==='high'&&n.label.startsWith('R01'))?.id||G.nodes.find(n=>n.type==='Finding'&&n.severity==='high').id);
  const PROJ=await ev(()=>G.nodes.filter(n=>n.type==='Project').sort((a,b)=>G.deg[G.idx.get(b.id)]-G.deg[G.idx.get(a.id)])[0].id);
  // 대본
  at(0.0,()=>ev(()=>__card('내 AI 코딩 도구,','지금 어떤 권한을 갖고 있는지 알고 계신가요?',1)));
  at(3.2,()=>ev(()=>{document.getElementById('card').style.transition='opacity .6s';__card(null,null,0);}));
  at(3.6,()=>cap('LARM은 Claude Code, Codex, Cursor의 설정을 별자리로 보여 줍니다.'));
  at(3.0,()=>ev(()=>setPaused(false)));
  at(7.0,()=>cap('궁금한 별을 누르면 그곳으로 날아갑니다. 연결된 것들이 함께 밝아집니다.'));
  at(7.2,()=>cursorNode('agent:claude-code'));
  at(8.4,()=>clickNode('agent:claude-code'));
  at(12.0,()=>cap("'이웃만'을 누르면 관련 없는 별은 잠시 숨깁니다."));
  at(12.2,()=>cursorEl('#nb'));
  at(13.3,()=>ev(()=>{__cur.click=220;toggleNeighbor(true);}));
  at(16.5,()=>cap('프로젝트를 누르면 연결된 파일이 한눈에 들어옵니다.'));
  at(16.6,()=>ev(()=>{toggleNeighbor();}));
  at(16.8,()=>cursorNode(PROJ));
  at(18.0,()=>clickNode(PROJ));
  at(22.0,()=>cap('아무리 확대해도 끝에 있는 별은 놓치지 않습니다.'));
  at(22.2,()=>ev(()=>flyTo(cam.target,13,2600)));
  at(27.0,()=>ev(()=>flyTo(cam.target,fitDistFor(G.focus),1400)));
  at(29.0,()=>cap('위험한 설정은 붉게 숨 쉬는 별로 알려 줍니다. 클릭 한 번이면 됩니다.'));
  at(29.2,()=>ev(()=>home()));
  at(30.4,()=>cursorNode(FIND_HIGH));
  at(31.6,()=>clickNode(FIND_HIGH));
  at(35.5,()=>cap("검색창에 'MCP'만 쳐도 외부 연결만 남습니다."));
  at(35.6,()=>cursorEl('#q'));
  at(36.4,()=>ev(()=>{home();}));
  ['M','MC','MCP'].forEach((s,i)=>at(36.8+i*0.35,()=>ev(s=>{const q=document.getElementById('q');q.value=s;q.dispatchEvent(new Event('input'));},s)));
  at(40.5,()=>cap('지금 일하고 있는 AI 도구와 프로젝트는 금빛으로 빛납니다.'));
  at(40.6,()=>ev(id=>{const q=document.getElementById('q');q.value='';q.dispatchEvent(new Event('input'));home();larmSetActive(['agent:claude-code',id]);},PROJ));
  at(45.5,()=>ev(()=>{__caption('');document.getElementById('card').style.transition='opacity .8s';__card('LARM','설치부터 첫 점검까지 1분. 무료입니다.  github.com/one-line-ai/LARM',1);}));
  const END=49.0; const N=Math.round(END*FPS);
  T.sort((a,b)=>a[0]-b[0]); let ti=0;
  for(let f=0;f<N;f++){const t=f/FPS; while(ti<T.length&&T[ti][0]<=t){await T[ti][1]();ti++;}
    await ev(dt=>__step(dt),DT);
    if(process.env.DIAG){ if(f%30===0){console.log('t',t.toFixed(1),await ev(()=>JSON.stringify({raf:__raf.length,d:Math.round(cam.dist),f:G.focus,tw:!!cam.tween,cw:canvas.width,ga:ctx.globalAlpha,err:(()=>{try{draw(__t);return ''}catch(e){return e.stack.slice(0,300)}})()})));} if(f>1100)break; continue; }
    await page.screenshot({path:path.join(S,process.env.VERT?'frames_v':'frames',`f${String(f).padStart(5,'0')}.jpg`),type:'jpeg',quality:92});
    if(f===900||f===1000){console.log('px',f,await ev(()=>{const d=ctx.getImageData(300,300,200,200).data;let s=0;for(let i=0;i<d.length;i+=4)s+=d[i]+d[i+1]+d[i+2];let derr='';try{draw(__t)}catch(e){derr=e.stack.slice(0,300)}let terr='';try{stepTween()}catch(e){terr=e.message}const d2=ctx.getImageData(300,300,200,200).data;let s2=0;for(let i=0;i<d2.length;i+=4)s2+=d2[i]+d2[i+1]+d2[i+2];return JSON.stringify({derr,terr,after:(s2/(d2.length/4*3)).toFixed(1),raf:__raf.length,errs:window.__errs,mean:(s/(d.length/4*3)).toFixed(1),ga:ctx.globalAlpha,comp:ctx.globalCompositeOperation,cs:document.getElementById('c').style.cssText,vis:getComputedStyle(document.getElementById('c')).opacity});}));}
    if(process.env.PXONLY&&f>1000)break;
    if(f%150===0)console.log('frame',f,'/',N);}
  await browser.close(); console.log('DONE',N);
})().catch(e=>{console.error(e);process.exit(1);});
