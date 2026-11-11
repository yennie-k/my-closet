// Fresh synthetic samples only; no input file or photo data.
import fs from 'node:fs';
import path from 'node:path';
import * as m from '../build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/index.js';
const root=path.resolve(import.meta.dirname,'..'),folder=path.join(root,'build/jpeg-restart-20261109');
fs.mkdirSync(folder,{recursive:true});
await m.initializeImageMagick(fs.readFileSync(path.join(root,'build/photo-worker-tools/node_modules/@imagemagick/magick-wasm/dist/x86/magick.wasm')));
const w=257,h=193,rgb=Buffer.alloc(w*h*3);
for(let y=0;y<h;y++)for(let x=0;x<w;x++){const k=(y*w+x)*3;rgb[k]=Math.floor(255*x/w);rgb[k+1]=Math.floor(255*y/h);rgb[k+2]=(Math.floor(x/11)%2)*150+40;}
const source=Buffer.concat([Buffer.from(`P6\n${w} ${h}\n255\n`),rgb]);
const manifest=[];
for(const interval of [1,7,16,17,128,129]) {
  const bytes=m.ImageMagick.read(source,i=>{i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','2x2');i.settings.setDefine(m.MagickFormat.Jpeg,'restart-interval',interval);i.quality=60;return i.write(m.MagickFormat.Jpeg,b=>Uint8Array.from(b));});
  const b=Buffer.from(bytes),offset=b.indexOf(Buffer.from([255,221]));
  if(offset<0)throw Error('Installed ImageMagick does not support requested restart-interval; do not claim fixture support');
  const actual=b.readUInt16BE(offset+4);if(actual!==interval)throw Error('Restart interval not applied');
  const file=`restart-${interval}.jpg`;fs.writeFileSync(path.join(folder,file),bytes);manifest.push({file,interval,bytes:bytes.length});
}
fs.writeFileSync(path.join(folder,'manifest.json'),JSON.stringify(manifest));console.log(`Generated ${manifest.length} verified DRI fixtures`);
if(process.argv.includes('--write-regression-fixture')) {
  const destination=path.join(root,'test/fixtures/synthetic_restart_422.jpg');
  if(fs.existsSync(destination))throw Error('Existing fixture is preserved; refusing overwrite');
  const bytes=m.ImageMagick.read(source,i=>{i.settings.setDefine(m.MagickFormat.Jpeg,'sampling-factor','2x1');i.settings.setDefine(m.MagickFormat.Jpeg,'restart-interval',17);i.quality=60;return i.write(m.MagickFormat.Jpeg,b=>Uint8Array.from(b));});
  fs.mkdirSync(path.dirname(destination),{recursive:true});fs.writeFileSync(destination,bytes);
  console.log('Wrote original-code synthetic 4:2:2 restart fixture (no user input).');
}
