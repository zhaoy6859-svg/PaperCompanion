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
function clock(seconds){const date=new Date((seconds||Date.now()/1000)*1000);return date.toLocaleString('zh-CN',{year:'numeric',month:'long',day:'numeric',weekday:'short',hour:'2-digit',minute:'2-digit'});}
function userRow(text,quote){const row=document.createElement('div');row.className='mine';const bubble=document.createElement('div');bubble.className='bubble question';if(quote){const q=document.createElement('div');q.className='quote';q.textContent=quote;bubble.append(q);}bubble.append(document.createTextNode(text||''));const face=document.createElement('img');face.className='me';face.src='../Companion/user-avatar.jpg';face.alt='';row.append(bubble,face);return row;}
function answer(text,page,pending=false,error=false){const row=document.createElement('section');row.className='them';const who=document.createElement('div');who.className='who';const avatar=document.createElement('img');avatar.src='../Companion/companion-avatar.png';avatar.alt='';who.append(avatar,document.createTextNode('论文伴侣'));
 if(Number.isInteger(page)&&page>=0){const b=document.createElement('button');b.textContent=`原文 p.${page+1}`;b.onclick=()=>native('page',page);who.append(b);}
 const bubble=document.createElement('div');bubble.className='bubble reply';
 if(pending&&!text){const dots=document.createElement('div');dots.className='dots';dots.innerHTML='<i></i><i></i><i></i>';bubble.append(dots);}else{const body=markdown(text);if(error)body.classList.add('error');bubble.append(body);}
 if(!pending&&text){const actions=document.createElement('div');actions.className='actions';const copy=document.createElement('button');copy.textContent='复制回答';copy.onclick=()=>{native('copy',text);copy.textContent='已复制'};actions.append(copy);bubble.append(actions);}
 row.append(who,bubble);return row;
}
let lastSignature='';
window.renderMessages=function(payload){payload=payload||{};const threads=Array.isArray(payload.threads)?payload.threads:[];
 const signature=JSON.stringify(payload);if(signature===lastSignature)return;lastSignature=signature;
 const bottom=document.documentElement.scrollHeight-innerHeight-scrollY<85;const oldY=scrollY;
 main.replaceChildren();
 if(!threads.length&&!payload.pending){const welcome=document.createElement('section');welcome.className='welcome';welcome.innerHTML='<img src="../Companion/poses/sparkle.png" alt="论文伴侣"><h2>读之前、读之后，<br>都可以先聊聊。</h2><p>还没打开论文时，就在下面跟我随便说。<br>从书库选一篇，对话会转到那篇上。</p>';main.append(welcome);}
 let lastClock='';
 function addStamp(parent,seconds){const label=clock(seconds);if(label===lastClock)return;lastClock=label;const stamp=document.createElement('div');stamp.className='day';stamp.textContent=label;parent.append(stamp);}
 for(const t of threads){const turn=document.createElement('article');turn.className='turn';addStamp(turn,t.created);if(t.question)turn.append(userRow(t.question,t.quote));turn.append(answer(t.answer,t.page));main.append(turn);}
 if(payload.pending){const turn=document.createElement('article');turn.className='turn';addStamp(turn,Date.now()/1000);if(payload.question)turn.append(userRow(payload.question,''));turn.append(answer(payload.draft,payload.page,payload.streaming,payload.error));main.append(turn);}
 requestAnimationFrame(()=>{if(bottom)scrollTo(0,document.documentElement.scrollHeight);else scrollTo(0,oldY);latest.hidden=bottom;});
};
latest.onclick=()=>{scrollTo({top:document.documentElement.scrollHeight,behavior:'smooth'});latest.hidden=true;};
addEventListener('scroll',()=>{latest.hidden=document.documentElement.scrollHeight-innerHeight-scrollY<85;},{passive:true});
