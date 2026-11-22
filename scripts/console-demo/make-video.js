// Usage: node make-video.js <out-full dir> <video.mp4>
// Renders each caption as a 1440x84 strip and stacks the strips under the recording, so captions never cover the console.
const {chromium} = require('playwright');
const fs = require('fs'); const path = require('path'); const {execFileSync} = require('child_process');
const dir = path.resolve(process.argv[2]); const out = path.resolve(process.argv[3]);
const {tStart, tEnd, caps} = JSON.parse(fs.readFileSync(dir + '/captions.json'));
const webm = fs.readdirSync(dir).find(f => f.endsWith('.webm'));
const cd = dir + '/caps'; fs.rmSync(cd, {recursive: true, force: true}); fs.mkdirSync(cd);
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({viewport: {width: 1440, height: 84}});
  const render = async (file, text) => {
    await p.setContent(`<html><body style="margin:0;width:1440px;height:84px;background:#0f1729;display:flex;align-items:center;justify-content:center;font:500 23px/1.3 -apple-system,'Segoe UI',Helvetica,Arial,sans-serif;color:#f4f6fb;">
      <div style="max-width:1340px;text-align:center">${esc(text)}</div></body></html>`);
    await p.screenshot({path: file});
  };
  await render(cd + '/blank.png', '');
  const start = Math.max(0, tStart - 0.4), end = tEnd + 0.6;
  let list = 'ffconcat version 1.0\n';
  let at = start;
  for (let i = 0; i < caps.length; i++) {
    const f = `${cd}/c${String(i).padStart(2, '0')}.png`;
    await render(f, caps[i].text);
    const from = Math.max(caps[i].t, start), to = i + 1 < caps.length ? caps[i + 1].t : end;
    if (from > at + 0.01) list += `file '${cd}/blank.png'\nduration ${(from - at).toFixed(3)}\n`;
    list += `file '${f}'\nduration ${(to - from).toFixed(3)}\n`;
    at = to;
  }
  list += `file '${cd}/blank.png'\nduration 0.5\nfile '${cd}/blank.png'\n`;
  fs.writeFileSync(cd + '/list.txt', list);
  await b.close();
  execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error',
    '-ss', start.toFixed(3), '-to', end.toFixed(3), '-i', `${dir}/${webm}`,
    '-f', 'concat', '-safe', '0', '-i', cd + '/list.txt',
    '-filter_complex', '[0:v]fps=30,setpts=PTS-STARTPTS,format=yuv420p[v];[1:v]fps=30,setpts=PTS-STARTPTS,scale=1440:84,format=yuv420p[c];[v][c]vstack=inputs=2:shortest=1[o]',
    '-map', '[o]', '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', out], {stdio: 'inherit'});
  console.log('wrote', out);
})();
