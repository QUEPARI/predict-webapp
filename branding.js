// Shared color derivation for the app and isolated account flows.
export const validAccent=value=>typeof value==='string'&&/^#[0-9a-f]{6}$/i.test(value);
const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16));
const luminance=channels=>channels.map(x=>{const v=x/255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);
const contrast=(a,b)=>{const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);};
const hexOf=channels=>'#'+channels.map(v=>Math.round(v).toString(16).padStart(2,'0')).join('');
export function accentPalette(hex,dark){
 const raw=rgb(hex),backgrounds=dark?['#1e1e1e','#101010']:['#ffffff','#f3f5f9'],toward=dark?255:0;let adjusted=raw;
 for(let i=0;i<=100;i++){adjusted=raw.map(v=>Math.round(v+(toward-v)*i/100));if(backgrounds.every(bg=>contrast(adjusted,rgb(bg))>=4.5))break;}
 const text=contrast(adjusted,[255,255,255])>=contrast(adjusted,[0,0,0])?'#ffffff':'#000000',panel=rgb(backgrounds[0]);
 return {accent:hexOf(adjusted),text,soft:hexOf(panel.map((v,i)=>v*.88+adjusted[i]*.12))};
}
export function applyAccent(color){
 const root=document.body;
 if(!validAccent(color)){['--accent','--accent-contrast','--soft'].forEach(k=>root.style.removeProperty(k));return;}
 const p=accentPalette(color,document.body.classList.contains('dark'));
 root.style.setProperty('--accent',p.accent);root.style.setProperty('--accent-contrast',p.text);root.style.setProperty('--soft',p.soft);
}
