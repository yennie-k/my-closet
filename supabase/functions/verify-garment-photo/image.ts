import { fail, type ImageInfo } from './core.ts';

// The runtime and tests inject the same pinned magick-wasm module.
// Deliberately accept only a narrow API shape, without SDK/framework dependencies.
export function magickDecoder(m: any) {
  m.ResourceLimits.width = 4096n;
  m.ResourceLimits.height = 4096n;
  m.ResourceLimits.memory = 64n*1024n*1024n;
  m.ResourceLimits.disk = 0n;
  m.ResourceLimits.area = 4_000_000n;
  // Magick's decoder uses temporary images too; 1 rejects even a single static image.
  // Animated PNG/WebP containers are separately rejected before decoder invocation.
  m.ResourceLimits.listLength = 4n;
  return async (bytes: Uint8Array, mime: string): Promise<ImageInfo> => {
    const formats:Record<string,string> = {'image/jpeg':m.MagickFormat.Jpeg,'image/png':m.MagickFormat.Png,'image/webp':m.MagickFormat.WebP};
    const format=formats[mime];
    if (!format) return fail('invalid_image');
    try {
      return m.ImageMagick.read(new m.MagickColor('#ffffff'),1,1,(img: any) => {
        let warned=false;img.onWarning=()=>{warned=true;return 0;};
        const settings=new m.MagickReadSettings({format});
        img.ping(bytes,settings);
        if (img.width*img.height > 4_000_000) return fail('invalid_image');
        img.read(bytes,settings);
        img.getPixels((pixels:any)=>pixels.getPixel(0,0));
        if(warned)return fail('invalid_image');
        return {mime,width:img.width,height:img.height};
      });
    } catch { return fail('invalid_image'); }
  };
}
