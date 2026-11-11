// Own synthetic patterns only. No user files, network or database access.
import fs from 'node:fs';
import path from 'node:path';
import * as m from '../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
const root=path.resolve(import.meta.dirname,'..'),folder=path.join(root,'build','photo-codec-20261105');
fs.mkdirSync(folder,{recursive:true});
await m.initializeImageMagick(fs.readFileSync(path.join(root,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')));
function ppm(w,h){const bytes=Buffer.alloc(w*h*3);for(let y=0;y<h;y++)for(let x=0;x<w;x++){const k=(y*w+x)*3;bytes[k]=20+Math.round(210*x/Math.max(1,w-1));bytes[k+1]=20+Math.round(210*y/Math.max(1,h-1));bytes[k+2]=x<w/2?55:190;}return Buffer.concat([Buffer.from(`P6\n${w} ${h}\n255\n`),bytes]);}
const variants=[
 ['jpeg-444','jpg',257,193,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','1x1')],
 ['jpeg-420','jpg',257,193,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','2x2')],
 ['jpeg-422','jpg',257,193,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','2x1')],
 ['jpeg-progressive','jpg',257,193,i=>i.settings.interlace=m.Interlace.Plane],
 ['jpeg-gray','jpg',257,193,i=>i.colorSpace=m.ColorSpace.Gray],
 ['jpeg-cmyk','jpg',257,193,i=>i.colorSpace=m.ColorSpace.CMYK],
 ['png-rgb','png',257,193,()=>{}],
 ['png-16bit','png',257,193,i=>{i.depth=16;i.settings.setDefine(m.MagickFormat.Png,'bit-depth','16');}],
 ['png-interlace','png',257,193,i=>i.settings.interlace=m.Interlace.Png],
 ['png-palette','png',257,193,i=>{i.quantize();i.settings.setDefine(m.MagickFormat.Png,'color-type','3');}],
 ['webp-lossy','webp',257,193,()=>{}],
 ['webp-lossless','webp',257,193,i=>i.settings.setDefine(m.MagickFormat.WebP,'lossless',true)],
 ['wide','png',1701,137,()=>{}],['tall','jpg',137,1701,()=>{}],
 ['large-odd','jpg',2001,1003,()=>{}],['narrow','png',1,1701,()=>{}],
 ['2048-420','jpg',2048,1536,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','2x2')],
 ['2048-422','jpg',2048,1536,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','2x1')],
 ['2048-vertical','jpg',2048,1536,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','1x2')],
 ['2048-411','jpg',2048,1536,i=>i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','4x1')],
 ['2048-progressive','jpg',2048,1536,i=>i.settings.interlace=m.Interlace.Plane],
];
for(let o=2;o<=8;o++)variants.push([`exif-${o}`,'jpg',257,193,()=>{},o]);
const cases=[];
for(const [name,ext,w,h,configure,orientation] of variants){
 let bytes=m.ImageMagick.read(ppm(w,h),i=>{configure(i);i.quality=95;return i.write(ext==='jpg'?m.MagickFormat.Jpeg:ext==='png'?m.MagickFormat.Png:m.MagickFormat.WebP,b=>Uint8Array.from(b));});
 // Minimal independent little-endian EXIF orientation APP1 segment.
 if(orientation){const exif=Buffer.from('45786966000049492a0008000000010012010300010000000100000000000000','hex');exif.writeUInt16LE(orientation,24);const length=Buffer.alloc(2);length.writeUInt16BE(exif.length+2);bytes=Buffer.concat([bytes.subarray(0,2),Buffer.from([255,225]),length,exif,bytes.subarray(2)]);}
 const file=`${name}.${ext}`;fs.writeFileSync(path.join(folder,file),bytes);
 const oracle=m.ImageMagick.read(bytes,i=>{i.autoOrient();i.colorSpace=m.ColorSpace.sRGB;return {width:i.width,height:i.height,samples:i.getPixels(p=>[.1,.3,.7,.9].flatMap(y=>[.1,.3,.7,.9].map(x=>Array.from(p.toByteArray(Math.floor(x*i.width),Math.floor(y*i.height),1,1,'RGB')))))};});
 cases.push({name,file,bytes:Buffer.from(bytes).toString('base64'),...oracle});
}
fs.writeFileSync(path.join(folder,'manifest.json'),JSON.stringify(cases));
console.log(`Generated ${cases.length} synthetic variants in ${folder}`);
