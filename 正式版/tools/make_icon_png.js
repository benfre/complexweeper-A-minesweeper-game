/* 从图集里抠出「图标」槽位导成 PNG，供 Linux 安装用。
   Windows 的 exe 图标是 set_icon.js 直接注入 PE .rsrc 的；Linux 没有这套机制，
   图标必须落成独立 PNG，再由 .desktop 文件的 Icon= 引用（装进 hicolor 图标主题）。
   源是图集里的 icon 槽位（32×32，带 alpha），放大一律用最近邻（像素画硬边更清楚）。
   用法: node tools/make_icon_png.js [输出目录] [尺寸...]
   默认: 输出 build/icons/complexweeper-<size>.png，尺寸 32 48 64 128 256。 */
const fs = require('fs');
const path = require('path');
const { writePNG } = require(path.join(__dirname, 'png.js'));

function fail(m) { console.error(m); process.exit(2); }

const args = process.argv.slice(2);
const outDir = path.resolve(args[0] || path.join(__dirname, '..', 'build', 'icons'));
const sizes = (args.length > 1 ? args.slice(1) : ['32', '48', '64', '128', '256']).map((s) => {
  const n = parseInt(s, 10);
  if (!n || n < 1) fail('尺寸应是正整数：' + s);
  return n;
});

const root = path.resolve(__dirname, '..'); // 正式版/
const atlas = fs.readFileSync(path.join(root, 'src', 'atlas.bin'));
if (atlas.toString('ascii', 0, 4) !== 'CSAT') fail('atlas.bin 格式不对');
const count = atlas.readUInt16LE(6);
const AW = atlas.readUInt16LE(8);
const pixOff = 12 + count * 8;

// 槽位号从生成的 assets.zig 里解析，别写死（和 set_icon.js 一致）
const assetsZig = fs.readFileSync(path.join(root, 'src', 'assets.zig'), 'utf8');
const m = /pub const icon: u16 = (\d+);/.exec(assetsZig);
if (!m) fail('assets.zig 里找不到 icon 槽位（先跑 node tools/gen_atlas.js）');
const idx = parseInt(m[1], 10);
const rx = atlas.readUInt16LE(12 + idx * 8);
const ry = atlas.readUInt16LE(12 + idx * 8 + 2);
const SW = atlas.readUInt16LE(12 + idx * 8 + 4);
const SH = atlas.readUInt16LE(12 + idx * 8 + 6);
if (SW !== SH) fail(`图标应为正方形，实际 ${SW}×${SH}`);

// 图集是 BGRA，转成 RGBA
const src = Buffer.alloc(SW * SH * 4);
for (let y = 0; y < SH; y++) {
  for (let x = 0; x < SW; x++) {
    const o = pixOff + ((ry + y) * AW + (rx + x)) * 4;
    const d = (y * SW + x) * 4;
    src[d] = atlas[o + 2];       // B -> R
    src[d + 1] = atlas[o + 1];   // G
    src[d + 2] = atlas[o];       // R -> B
    src[d + 3] = atlas[o + 3];   // A
  }
}

function nearest(w) {
  const out = Buffer.alloc(w * w * 4);
  for (let y = 0; y < w; y++) {
    for (let x = 0; x < w; x++) {
      const sx = Math.min(SW - 1, Math.floor(x * SW / w));
      const sy = Math.min(SH - 1, Math.floor(y * SH / w));
      src.copy(out, (y * w + x) * 4, (sy * SW + sx) * 4, (sy * SW + sx) * 4 + 4);
    }
  }
  return out;
}

fs.mkdirSync(outDir, { recursive: true });
const written = [];
for (const s of sizes) {
  const file = path.join(outDir, `complexweeper-${s}.png`);
  writePNG(file, s, s, s === SW ? src : nearest(s));
  written.push(`${path.basename(outDir)}/complexweeper-${s}.png`);
}
console.log('-> ' + written.join('  ') + `（源 icon 槽位 ${SW}×${SH}）`);