const main=document.getElementById('conversation'), latest=document.getElementById('latest');
function native(action,value){window.webkit.messageHandlers.chat.postMessage({action,value});}
function markdown(text){
 const math=[];
 const protectedText=text.replace(/(```[\s\S]*?(?:```|$)|`[^`\n]*`)|\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\]|\\\(([\s\S]*?)\\\)|(?<!\\)\$([^$\n]+?)(?<!\\)\$/g,(all,code,display,bracket,inline,small)=>{
  if(code)return code;
  const key=`PCMATHPLACEHOLDER${math.length}END`;
  const value=display??bracket??inline??small;
  math.push({key,value,display:display!==undefined||bracket!==undefined});return key;
 });
 let html=DOMPurify.sanitize(marked.parse(protectedText,{gfm:true,breaks:false}),{FORBID_TAGS:['img','svg','style','iframe','form','input','button'],FORBID_ATTR:['style']});
 for(const item of math){let rendered;try{rendered=katex.renderToString(item.value,{displayMode:item.display,throwOnError:false,trust:false,strict:'ignore',maxExpand:300,maxSize:20});}catch{const safe=document.createElement('span');safe.textContent=item.value;rendered=safe.innerHTML;}
  html=html.replace(item.key,item.display?`<div class="math-block">${rendered}</div>`:rendered);
 }
 const element=document.createElement('div');element.className='answer';element.innerHTML=html;
 element.querySelectorAll('table').forEach(t=>{const wrap=document.createElement('div');wrap.className='table-scroll';t.replaceWith(wrap);wrap.append(t);});
 element.querySelectorAll('pre').forEach(pre=>{const wrap=document.createElement('div');wrap.className='code-wrap';pre.replaceWith(wrap);wrap.append(pre);const code=pre.querySelector('code');if(code){hljs.highlightElement(code);const b=document.createElement('button');b.className='code-copy';b.textContent='复制代码';b.onclick=()=>{native('copy',code.textContent);b.textContent='已复制'};wrap.append(b);}});
 return element;
}
function answer(text,page,pending=false,error=false){const box=document.createElement('section');const by=document.createElement('div');by.className='byline';const avatar=document.createElement('img');avatar.src='../Companion/companion-avatar.png';avatar.alt='';by.append(avatar,document.createTextNode('论文伴侣'));
 if(Number.isInteger(page)){const b=document.createElement('button');b.textContent=`定位原文 p.${page+1}`;b.onclick=()=>native('page',page);by.append(b);}
 box.append(by);
 if(pending&&!text){const dots=document.createElement('div');dots.className='dots';dots.innerHTML='<i></i><i></i><i></i>';box.append(dots);}else{const body=markdown(text);if(error)body.classList.add('error');box.append(body);}
 if(!pending&&text){const actions=document.createElement('div');actions.className='actions';const copy=document.createElement('button');copy.textContent='复制回答';copy.onclick=()=>{native('copy',text);copy.textContent='已复制'};actions.append(copy);box.append(actions);}return box;
}
let lastSignature='';
window.renderMessages=function(payload){payload=payload||{};const threads=Array.isArray(payload.threads)?payload.threads:[];
 const signature=JSON.stringify(payload);if(signature===lastSignature)return;lastSignature=signature;
 const bottom=document.documentElement.scrollHeight-innerHeight-scrollY<85;const oldY=scrollY;
 main.replaceChildren();
 if(!threads.length&&!payload.pending){const welcome=document.createElement('section');welcome.className='welcome';welcome.innerHTML='<img src="../Companion/poses/sparkle.png" alt="论文伴侣"><h2>读不懂的地方，<br>我们一起拆开看。</h2><p>选中一句话，或直接在下面提问。<br>公式、方法、证据，都可以慢慢聊。</p>';main.append(welcome);}
 for(const t of threads){const turn=document.createElement('article');turn.className='turn';const q=document.createElement('div');q.className='question';if(t.quote){const quote=document.createElement('div');quote.className='quote';quote.textContent=t.quote;q.append(quote);}q.append(document.createTextNode(t.question));turn.append(q,answer(t.answer,t.page));main.append(turn);}
 if(payload.pending){const turn=document.createElement('article');turn.className='turn';if(payload.question){const q=document.createElement('div');q.className='question';q.textContent=payload.question;turn.append(q);}turn.append(answer(payload.draft,payload.page,payload.streaming,payload.error));main.append(turn);}
 requestAnimationFrame(()=>{if(bottom)scrollTo(0,document.documentElement.scrollHeight);else scrollTo(0,oldY);latest.hidden=bottom;});
};
latest.onclick=()=>{scrollTo({top:document.documentElement.scrollHeight,behavior:'smooth'});latest.hidden=true;};
addEventListener('scroll',()=>{latest.hidden=document.documentElement.scrollHeight-innerHeight-scrollY<85;},{passive:true});
