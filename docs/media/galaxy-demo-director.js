const puppeteer=require('puppeteer-core');const fs=require('fs');const path=require('path');
const S=__dirname; const FPS=30; const DT=1000/FPS;
const T=[]; const at=(s,fn)=>T.push([s,fn]);
(async()=>{
  const browser=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:'new',args:['--allow-file-access-from-files','--hide-scrollbars','--font-render-hinting=none']});
  const page=await browser.newPage(); await page.setViewport({width:1280,height:800,deviceScaleFactor:1});
  await page.goto('file://'+path.join(S,'a/b/web/director.html'),{waitUntil:'load'});
  page.on('pageerror',e=>console.log('PAGEERR',e.message)); await page.waitForFunction(()=>typeof G!=='undefined'&&G&&G.nodes.length>0);
  await page.evaluate(()=>{document.fonts&&document.fonts.ready; document.getElementById('ds-real').style.display='none';document.getElementById('ds-demo').style.display='none';document.querySelector('#top .sub').style.display='none';document.querySelector('#top h1').style.display='none'; setPaused(true);});
  await new Promise(r=>setTimeout(r,800));
  const ev=(fn,...a)=>page.evaluate(fn,...a);
  const cursorNode=id=>ev(id=>{const p=__nodePos(id); if(p){__cur.tx=p[0];__cur.ty=p[1];}},id);
  const cursorEl=sel=>ev(sel=>{const p=__elPos(sel);__cur.tx=p[0];__cur.ty=p[1];},sel);
  const clickNode=id=>ev(id=>{__cur.click=220;focusNode(G.idx.get(id));},id);
  const cap=t=>ev(t=>__caption(t),t);
  const FIND_HIGH=await ev(()=>G.nodes.find(n=>n.type==='Finding'&&n.severity==='high'&&n.label.startsWith('R01'))?.id||G.nodes.find(n=>n.type==='Finding'&&n.severity==='high').id);
  const PROJ=await ev(()=>G.nodes.filter(n=>n.type==='Project').sort((a,b)=>G.deg[G.idx.get(b.id)]-G.deg[G.idx.get(a.id)])[0].id);
  // 대본
  at(0.0,()=>ev(()=>__card('LARM','AI 도구 설정을 별자리처럼 살펴보기',1)));
  at(2.6,()=>ev(()=>{document.getElementById('card').style.transition='opacity .6s';__card(null,null,0);}));
  at(3.0,()=>cap('설정 파일, 허용 규칙, 외부 연결, 발견 사항이 별 하나씩'));
  at(3.0,()=>ev(()=>setPaused(false)));
  at(7.0,()=>cap('별을 누르면 그 별로 날아가고 이웃이 밝아짐'));
  at(7.2,()=>cursorNode('agent:claude-code'));
  at(8.4,()=>clickNode('agent:claude-code'));
  at(12.0,()=>cap("'이웃만'을 누르면 연결된 것만 남음"));
  at(12.2,()=>cursorEl('#nb'));
  at(13.3,()=>ev(()=>{__cur.click=220;toggleNeighbor(true);}));
  at(16.5,()=>cap('프로젝트를 누르면 연결된 파일이 모두 화면에 들어옴'));
  at(16.6,()=>ev(()=>{toggleNeighbor();}));
  at(16.8,()=>cursorNode(PROJ));
  at(18.0,()=>clickNode(PROJ));
  at(22.0,()=>cap('확대해도 끝 별은 사라지지 않고 가장자리 표시로 남음'));
  at(22.2,()=>ev(()=>flyTo(cam.target,13,2600)));
  at(27.0,()=>ev(()=>flyTo(cam.target,fitDistFor(G.focus),1400)));
  at(29.0,()=>cap('높은 위험 발견 사항은 붉게 숨 쉬는 별'));
  at(29.2,()=>ev(()=>home()));
  at(30.4,()=>cursorNode(FIND_HIGH));
  at(31.6,()=>clickNode(FIND_HIGH));
  at(35.5,()=>cap("검색창에 'MCP'를 치면 외부 도구 연결만 남음"));
  at(35.6,()=>cursorEl('#q'));
  at(36.4,()=>ev(()=>{home();}));
  ['M','MC','MCP'].forEach((s,i)=>at(36.8+i*0.35,()=>ev(s=>{const q=document.getElementById('q');q.value=s;q.dispatchEvent(new Event('input'));},s)));
  at(40.5,()=>cap('지금 활동 중인 AI 도구와 프로젝트는 금빛으로 빛남'));
  at(40.6,()=>ev(id=>{const q=document.getElementById('q');q.value='';q.dispatchEvent(new Event('input'));home();larmSetActive(['agent:claude-code',id]);},PROJ));
  at(45.5,()=>ev(()=>{__caption('');document.getElementById('card').style.transition='opacity .8s';__card('LARM 0.7.0','Mac 한 대의 AI 도구 안전, 무료 · github.com/one-line-ai/LARM',1);}));
  const END=49.0; const N=Math.round(END*FPS);
  T.sort((a,b)=>a[0]-b[0]); let ti=0;
  for(let f=0;f<N;f++){const t=f/FPS; while(ti<T.length&&T[ti][0]<=t){await T[ti][1]();ti++;}
    await ev(dt=>__step(dt),DT);
    if(process.env.DIAG){ if(f%30===0){console.log('t',t.toFixed(1),await ev(()=>JSON.stringify({raf:__raf.length,d:Math.round(cam.dist),f:G.focus,tw:!!cam.tween,cw:canvas.width,ga:ctx.globalAlpha,err:(()=>{try{draw(__t);return ''}catch(e){return e.stack.slice(0,300)}})()})));} if(f>1100)break; continue; }
    await page.screenshot({path:path.join(S,'frames',`f${String(f).padStart(5,'0')}.jpg`),type:'jpeg',quality:92});
    if(f===900||f===1000){console.log('px',f,await ev(()=>{const d=ctx.getImageData(300,300,200,200).data;let s=0;for(let i=0;i<d.length;i+=4)s+=d[i]+d[i+1]+d[i+2];let derr='';try{draw(__t)}catch(e){derr=e.stack.slice(0,300)}let terr='';try{stepTween()}catch(e){terr=e.message}const d2=ctx.getImageData(300,300,200,200).data;let s2=0;for(let i=0;i<d2.length;i+=4)s2+=d2[i]+d2[i+1]+d2[i+2];return JSON.stringify({derr,terr,after:(s2/(d2.length/4*3)).toFixed(1),raf:__raf.length,errs:window.__errs,mean:(s/(d.length/4*3)).toFixed(1),ga:ctx.globalAlpha,comp:ctx.globalCompositeOperation,cs:document.getElementById('c').style.cssText,vis:getComputedStyle(document.getElementById('c')).opacity});}));}
    if(process.env.PXONLY&&f>1000)break;
    if(f%150===0)console.log('frame',f,'/',N);}
  await browser.close(); console.log('DONE',N);
})().catch(e=>{console.error(e);process.exit(1);});
