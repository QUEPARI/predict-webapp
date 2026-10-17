// Public card artwork and a browser-compatible, accessible square crop editor.
export function showTournamentImage(host,client,id,alt=''){
 host.replaceChildren();const fallback=document.createElement('span');fallback.textContent='🏆';fallback.setAttribute('aria-hidden','true');host.append(fallback);
 const storage=client.storage?.from('tournament-images');if(!storage)return;
 const img=document.createElement('img');img.alt=alt;img.loading='lazy';let legacy=false;const stamp=Date.now();
 img.onerror=()=>{if(legacy){img.remove();return;}legacy=true;img.src=storage.getPublicUrl(id+'/cover.webp').data.publicUrl+'?v='+stamp;};
 img.src=storage.getPublicUrl(id+'/cover.jpg').data.publicUrl+'?v='+stamp;host.append(img);
}
export function createSquareCrop(host,{onChange=()=>{},onError=()=>{}}={}){
 const events=new AbortController();let image=null,sequence=0,url=null,drag=null;
 host.innerHTML=`<div class="image-crop" hidden><p class="hint">Verschuif de afbeelding of gebruik de schuifjes. Dit vierkant verschijnt op de spelkaart.</p><canvas width="320" height="320" aria-label="Voorbeeld van de vierkante uitsnede"></canvas><label>Zoomen<input data-crop-zoom type="range" min="100" max="300" step="1" value="100"></label><div class="two"><label>Horizontaal<input data-crop-x type="range" min="0" max="100" step="1" value="50"></label><label>Verticaal<input data-crop-y type="range" min="0" max="100" step="1" value="50"></label></div></div>`;
 const panel=host.firstElementChild,canvas=host.querySelector('canvas'),zoom=host.querySelector('[data-crop-zoom]'),x=host.querySelector('[data-crop-x]'),y=host.querySelector('[data-crop-y]');
 const geometry=()=>{const side=Math.min(image.naturalWidth,image.naturalHeight)/(Number(zoom.value)/100);return {side,sx:(image.naturalWidth-side)*Number(x.value)/100,sy:(image.naturalHeight-side)*Number(y.value)/100};};
 function draw(output=canvas){if(!image)return;const {side,sx,sy}=geometry(),c=output.getContext('2d');c.fillStyle='#ffffff';c.fillRect(0,0,output.width,output.height);c.drawImage(image,sx,sy,side,side,0,0,output.width,output.height);}
 function clear(){sequence++;image=null;drag=null;panel.hidden=true;if(url){URL.revokeObjectURL(url);url=null;}zoom.value='100';x.value=y.value='50';}
 for(const control of [zoom,x,y])control.addEventListener('input',()=>{draw();onChange();},{signal:events.signal});
 canvas.addEventListener('pointerdown',e=>{if(!image)return;drag={px:e.clientX,py:e.clientY,...geometry()};canvas.setPointerCapture(e.pointerId);},{signal:events.signal});
 canvas.addEventListener('pointermove',e=>{if(!drag||!image)return;const {width}=canvas.getBoundingClientRect(),scale=drag.side/width,dx=image.naturalWidth-drag.side,dy=image.naturalHeight-drag.side;x.value=String(dx?Math.max(0,Math.min(100,(drag.sx-(e.clientX-drag.px)*scale)/dx*100)):50);y.value=String(dy?Math.max(0,Math.min(100,(drag.sy-(e.clientY-drag.py)*scale)/dy*100)):50);draw();onChange();},{signal:events.signal});
 for(const type of ['pointerup','pointercancel','lostpointercapture'])canvas.addEventListener(type,()=>drag=null,{signal:events.signal});
 return {
  get ready(){return !!image;},
  async load(file){clear();const request=sequence;if(!file)return false;
   if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>10*1024*1024){onError('Kies een JPG, PNG of WebP van maximaal 10 MB.');return false;}
   try{const source=URL.createObjectURL(file);url=source;const img=new Image();await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(Error('Deze afbeelding kan niet worden gelezen. Kies een JPG, PNG of WebP.'));img.src=source;});if(request!==sequence||events.signal.aborted)return false;
    if(!img.naturalWidth||!img.naturalHeight)throw Error('De afbeelding heeft geen geldige afmetingen.');image=img;URL.revokeObjectURL(source);url=null;panel.hidden=false;draw();return true;
   }catch(error){if(request===sequence){clear();onError(error.message);}return false;}
  },
  async blob(){if(!image)throw Error('Kies eerst een afbeelding en stel de uitsnede in.');const output=document.createElement('canvas');output.width=output.height=Math.min(1000,Math.max(1,Math.round(geometry().side)));draw(output);
   const blob=await new Promise(resolve=>output.toBlob(resolve,'image/jpeg',.88));if(!blob||blob.type!=='image/jpeg'||blob.size>2097152)throw Error('De uitsnede kon niet worden opgeslagen. Kies een kleinere afbeelding.');return blob;
  },clear,destroy(){clear();events.abort();}
 };
}
