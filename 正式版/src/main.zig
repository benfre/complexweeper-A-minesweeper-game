// 复扫雷 正式版 · 主程序
// 纯 Win32 + GDI，无第三方库、无 libc、无运行时依赖，编译结果为单个 exe。
const std = @import("std");
const w = @import("ui.zig");
const g = @import("game.zig");
const A = @import("assets.zig");
const snd = @import("sounds.zig");

// ------------------------------------------------------------------ 常量
const CLASS_MAIN = "ComplexSweeperMain";
const CLASS_DLG = "ComplexSweeperDlg";
const TIMER_ID: usize = 1;
/// 定时器
const TIMER_FLASH: usize = 2;

const IDM_NEW: usize = 100;
const IDM_BEGINNER: usize = 101;
const IDM_INTERMEDIATE: usize = 102;
const IDM_EXPERT: usize = 103;
const IDM_CUSTOM: usize = 104;
const IDM_EXIT: usize = 105;
/// 闵可夫斯基模式的同一批命令（两个模式各占一段命令号，菜单里是两个并列的子菜单）
const IDM_HYPER_BEGINNER: usize = 120;
const IDM_HYPER_INTERMEDIATE: usize = 121;
const IDM_HYPER_EXPERT: usize = 122;
const IDM_HYPER_CUSTOM: usize = 123;
/// 闵可夫斯基模式的那份最高分纪录（两个模式各记一套，所以菜单里也是两条）
const IDM_HYPER_BEST: usize = 124;
const IDM_ZOOM1: usize = 110;
const IDM_ZOOM2: usize = 111;
const IDM_ZOOM3: usize = 112;
const IDM_HELP_HOW: usize = 200;
const IDM_BEST: usize = 106;
/// 「颜色」开关（默认开 = 彩色贴图；关掉用黑白贴图）
const IDM_COLOR: usize = 108;
/// 「声音」开关（默认开，勾选态就是开着）
const IDM_SOUND: usize = 107;
const IDM_HELP_ABOUT: usize = 202;

const IDC_EDIT_H: i32 = 1001;
const IDC_EDIT_W: i32 = 1002;
const IDC_EDIT_T1: i32 = 1003;
const IDC_EDIT_T2: i32 = 1004;
const IDC_EDIT_T3: i32 = 1005;
const IDC_EDIT_T4: i32 = 1006;
const IDC_BTN_OK: i32 = 1007;
const IDC_BTN_CANCEL: i32 = 1008;
const IDC_BTN_SPLIT: i32 = 1009;
const IDC_STATIC_ERR: i32 = 1010;

const C_BTNFACE = w.rgb(0xC0, 0xC0, 0xC0);
const C_HILIGHT = w.rgb(0xDF, 0xDF, 0xDF);
const C_SHADOW = w.rgb(0x80, 0x80, 0x80);
const C_BLACK = w.rgb(0, 0, 0);
const C_WHITE = w.rgb(0xFF, 0xFF, 0xFF);
const C_DARKGRAY = w.rgb(0x40, 0x40, 0x40);

// 全局
pub var game: g.Game = .{};
var zoom: i32 = 2;
/// 当前是不是闵可夫斯基模式。模式是"设置"而不是"局面"，所以存在 game.mode 里，
/// 新开一局、换难度都不会把它弄丢；菜单圆点、贴图查表、计雷器单位全靠它分派。
fn hyper() bool {
    return game.mode == .hyper;
}
/// 当前棋盘对应的档位下标（0/1/2 = 标准三档，-1 = 自定义或界面还没定过）
var cur_preset: i32 = -1;
var hwnd_main: w.HWND = null;
var mem_dc: w.HDC = null;
var mem_bmp: w.HBITMAP = null;
var mem_w: i32 = 0;
var mem_h: i32 = 0;
var atlas_dc: w.HDC = null;
var atlas_bmp: w.HBITMAP = null;
var atlas_old: w.HGDIOBJ = null;
var atlas_pixels: [*]u8 = undefined;
/// 黑白贴图（生成器压成灰度 1 字节/像素，这里展开成 32bpp DIB）
var atlas_bw_dc: w.HDC = null;
var atlas_bw_bmp: w.HBITMAP = null;
var atlas_bw_old: w.HGDIOBJ = null;
var face_down = false;
/// 这次左键按下是不是"落在人脸按钮上"的：只有按下与松开都在脸上才重开
var face_armed = false;
/// 「脸扫雷」闪到什么时候（GetTickCount 的时间戳）：翻格、插旗时闪一下
var face_flash_until: u32 = 0;
const FACE_FLASH_MS: u32 = 200;
/// 当前被"按住"的格子（传统扫雷的按下预览）：-1 = 没有。松开时只有落在这一格上才真翻开
var press_cell: i32 = -1;
/// 左右键同时按住（或中键按住）时准备展开的那一格：-1 = 没有。
/// 按住期间它周围"即将被展开"的格子会先显示空白贴图，松手才真展开。
var chord_cell: i32 = -1;
/// 鼠标键此刻是否按着（双击的第二下也算"左键按下"）
var l_down = false;
var r_down = false;
var m_down = false;
var mouse_cell: i32 = -1;
var mouse_in_board = false;
var dialog_hwnd: w.HWND = null;
var dialog_done = false;
var dialog_cancel = false;
var edit_handles: [6]w.HWND = .{ null, null, null, null, null, null };
var dlg_err_hwnd: w.HWND = null;
var dlg_font: w.HFONT = null;
/// 对话框
var dlg_bg_brush: w.HBRUSH = null;
var win_dc_scratch: w.HDC = null;
var done_flag = false;

// 布局
pub const Layout = struct {
    z: i32,
    frame: i32,
    pad: i32,
    header_h: i32,
    gap: i32,
    box: i32,
    inner_w: i32,
    client_w: i32,
    client_h: i32,
    board_x: i32,
    board_y: i32,
    cell: i32,
    header_x: i32,
    header_y: i32,
    header_w: i32,
};

/// 虚雷第四格是i
const REAL_DIGITS: i32 = 4;
const IMAG_DIGITS: i32 = 3;

/// 数值超出这个范围加一格
fn valueDigits(base: i32, v: ?i32) i32 {
    if (v == null) return base;
    const x = v.?;
    if (x >= 0) return if (x <= pow10i(base) - 1) base else base + 1;
    return if (x >= -(pow10i(base - 1) - 1)) base else base + 1;
}
/// 数值区占几格（实雷/计时器四格、虚雷三格）
fn panelValueDigits(imag: bool, v: ?i32) i32 {
    return valueDigits(if (imag) IMAG_DIGITS else REAL_DIGITS, v);
}
/// 一块面板占几格：数值区 + 虚雷那一格 `i` 单位（实雷与计时器没有这一格）
fn panelCells(imag: bool, v: ?i32) i32 {
    return panelValueDigits(imag, v) + (if (imag) @as(i32, 1) else 0);
}
/// 一个计雷器的宽度：图标 + 留白 + N 格 LED + 边框（内容刚好等于这个宽度，不溢出不裁切）
fn counterWidth(z: i32, digits: i32) i32 {
    return 16 * z + 2 * z + digits * 13 * z + 2 * z;
}
/// 计雷器上显示的是"这一类雷还剩几颗没标"，并且带上这一类雷自己的符号与单位：
///   正实雷 +k    → k（四格数字）      负实雷 −k    → −k（负号占一格，仍是四格）
///   正虚雷 +k·i  → 三格数字 + 一格 i   负虚雷 −k·i  → 负号 + 两格数字 + 一格 i（四格）
/// 于是标一颗负实旗帜会让那个负数朝零走，看起来就是"数字增加"。
fn counterValue(t: usize) i32 {
    const k = game.unmarked(t);
    return switch (t) {
        2, 4 => -k,
        else => k,
    };
}
/// 还没开局时计雷器画空格子（此时各类雷的颗数还没抽出来）
fn counterShown(t: usize) ?i32 {
    if (!game.started) return null;
    return counterValue(t);
}
/// 虚雷（正、负）的第四格是 i 单位，实雷的第四格是数字
fn counterImag(t: usize) bool {
    return t == 3 or t == 4;
}
/// 计雷器竖排那一列的整体宽度（绘制与人脸定位共用，保证两者一致）
fn countersWidth(L: Layout) i32 {
    var widest: i32 = 0;
    for (1..5) |t| {
        widest = @max(widest, counterWidth(L.z, panelCells(counterImag(t), counterShown(t))));
    }
    return widest;
}
/// 计时器面板宽度：四格 LED + 边框（没有图标那一块）
fn timerWidth(z: i32) i32 {
    return 4 * 13 * z + 2 * z;
}
/// 表头最小宽度：左侧一列计雷器 + 人脸 + 计时 + 留白。
/// 计雷器按常态四格算，数值溢出（≥10000 或 ≤−1000）时那一行自己变宽一丁点。
fn headerContentWidth(z: i32) i32 {
    const col = counterWidth(z, 4);
    return 4 * z + col + 8 * z + FACE_SIZE * z + 8 * z + timerWidth(z) + 4 * z;
}

fn layout() Layout {
    const z = zoom;
    const frame = 3 * z;
    const pad = 6 * z;
    const gap = 6 * z;
    const box = 3 * z;
    const cell = 16 * z;
    const board_w = @as(i32, game.w) * cell + 2 * box;
    const hw = headerContentWidth(z);
    const inner_w = @max(board_w, hw);
    const client_w = inner_w + 2 * (frame + pad);
    // 表头里四个计雷器竖着排：上下边框 2z×2 + 内边距 3z×2 + 四行 26z + 三个行距 2z
    const counters_h = 4 * (26 * z) + 3 * (2 * z);
    const header_h = 2 * (2 * z) + 2 * (3 * z) + counters_h;
    const client_h = 2 * (frame + pad) + header_h + gap + @as(i32, game.h) * cell + 2 * box;
    return .{
        .z = z,
        .frame = frame,
        .pad = pad,
        .header_h = header_h,
        .gap = gap,
        .box = box,
        .inner_w = inner_w,
        .client_w = client_w,
        .client_h = client_h,
        .board_x = frame + pad + @divTrunc(inner_w - board_w, 2) + box,
        .board_y = frame + pad + header_h + gap + box,
        .cell = cell,
        .header_x = frame + pad,
        .header_y = frame + pad,
        .header_w = inner_w,
    };
}

/// 计雷器那一列的起始坐标（四个竖排）
fn countersX(L: Layout) i32 {
    return L.header_x + 4 * L.z;
}
fn countersY(L: Layout) i32 {
    return L.header_y + 2 * L.z + 3 * L.z;
}
/// 人脸按钮就是那张 24×24 贴图本身：素材里已经把立体边画进去了
/// （上/左 2 像素白高光，下/右 2 像素 #808080 阴影；按下的那张是反过来画的），
/// 所以这里**不能再自己画一圈 3D 边框**，否则会套出双层边（就是看起来多出来的那层底图）。
const FACE_SIZE: i32 = 24;
/// 贴图里的脸在 24×24 里偏右下半个像素（左边距 5、右边距 4，上下同理），
/// 再加上手动微调，整体往左上挪这么多屏幕像素。
const FACE_NUDGE: i32 = 2;

/// 人脸按钮左上角：先在表头正中摆，再整体往左上挪 FACE_NUDGE
fn faceLeft(L: Layout) i32 {
    const size = FACE_SIZE * L.z;
    const counters_end = countersX(L) + countersWidth(L);
    const timer_start = timerX(L);
    const clearance = 6 * L.z;
    var fx = L.header_x + @divTrunc(L.header_w, 2) - @divTrunc(size, 2);
    if (fx < counters_end + clearance) fx = counters_end + clearance;
    if (fx + size > timer_start - clearance) fx = timer_start - clearance - size;
    if (fx < L.header_x) fx = L.header_x;
    return fx - FACE_NUDGE;
}

fn faceTop(L: Layout) i32 {
    return L.header_y + @divTrunc(L.header_h - FACE_SIZE * L.z, 2) - FACE_NUDGE;
}

fn timerX(L: Layout) i32 {
    return L.header_x + L.header_w - 4 * L.z - timerWidth(L.z);
}

fn timerY(L: Layout) i32 {
    return L.header_y + @divTrunc(L.header_h - 26 * L.z, 2);
}
// ------------------------------------------------------------------ 绘图小工具
fn fill(dc: w.HDC, x: i32, y: i32, cw: i32, ch: i32, color: w.DWORD) void {
    if (cw <= 0 or ch <= 0) return;
    var r = w.RECT{ .left = x, .top = y, .right = x + cw, .bottom = y + ch };
    const br = w.CreateSolidBrush(color);
    _ = w.FillRect(dc, &r, br);
    _ = w.DeleteObject(br);
}

/// 经典立体边框：raised = 左上亮、右下暗；sunken 反过来
fn draw3d(dc: w.HDC, x: i32, y: i32, cw: i32, ch: i32, t: i32, raised: bool) void {
    const a = if (raised) C_HILIGHT else C_SHADOW;
    const b = if (raised) C_SHADOW else C_HILIGHT;
    fill(dc, x, y, cw, t, a); // 上
    fill(dc, x, y, t, ch, a); // 左
    fill(dc, x, y + ch - t, cw, t, b); // 下
    fill(dc, x + cw - t, y, t, ch, b); // 右
}

/// 方形贴图（格子 16×16、图标 16×16、人脸 24×24）的简写
/// 当前该用哪份图集：颜色关掉就用黑白那份（没加载成功就退回彩色）
fn activeAtlas() w.HDC {
    if (color_off and atlas_bw_dc != null) return atlas_bw_dc;
    return atlas_dc;
}

fn blitSpriteSq(dc: w.HDC, sprite: u16, x: i32, y: i32, size: i32) void {
    blitSprite(dc, sprite, x, y, size, size);
}
/// 贴一张图集里的图。宽高必须分开传：素材里 LED 数字是 13×23，不是方的。
/// 早先这里只收一个 size 并同时当宽高用，数字就被纵向压扁成 13z×13z（看起来像"纵向没放大"）。
fn blitSprite(dc: w.HDC, sprite: u16, x: i32, y: i32, dw: i32, dh: i32) void {
    const r = A.rect(sprite);
    if (dw == r.w and dh == r.h) {
        _ = w.BitBlt(dc, x, y, dw, dh, activeAtlas(), r.x, r.y, w.SRCCOPY);
    } else {
        _ = w.StretchBlt(dc, x, y, dw, dh, activeAtlas(), r.x, r.y, r.w, r.h, w.SRCCOPY);
    }
}

/// 画一个 LED 数字串；返回宽度。v = null 表示空
fn drawLed(dc: w.HDC, x: i32, y: i32, v: ?i32, digits: i32, z: i32) i32 {
    const lw = 13 * z;
    const lh = 23 * z;
    var cx = x;
    if (v == null) {
        var i: i32 = 0;
        while (i < digits) : (i += 1) {
            blitSprite(dc, A.led_blank, cx, y, lw, lh);
            cx += lw;
        }
        return cx - x;
    }
    const val = v.?;
    if (val < 0) {
        blitSprite(dc, A.led_minus, cx, y, lw, lh);
        cx += lw;
        var m = -val;
        const lim = pow10i(digits - 1) - 1;
        if (m > lim) m = lim;
        var buf: [4]u8 = undefined;
        const n = fmtDigits(&buf, @intCast(m), @intCast(digits - 1));
        for (buf[0..n]) |ch| {
            blitSprite(dc, digitSprite(ch), cx, y, lw, lh);
            cx += lw;
        }
    } else {
        var m = val;
        const lim = pow10i(digits) - 1;
        if (m > lim) m = lim;
        var buf: [4]u8 = undefined;
        const n = fmtDigits(&buf, @intCast(m), @intCast(digits));
        for (buf[0..n]) |ch| {
            blitSprite(dc, digitSprite(ch), cx, y, lw, lh);
            cx += lw;
        }
    }
    return cx - x;
}

fn pow10i(n: i32) i32 {
    var r: i32 = 1;
    var i: i32 = 0;
    while (i < n) : (i += 1) r *= 10;
    return r;
}

fn fmtDigits(buf: []u8, v: u32, digits: u32) usize {
    var i: usize = digits;
    var x = v;
    while (i > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (x % 10));
        x /= 10;
    }
    return digits;
}

fn digitSprite(ch: u8) u16 {
    return switch (ch) {
        '0' => A.led_0,
        '1' => A.led_1,
        '2' => A.led_2,
        '3' => A.led_3,
        '4' => A.led_4,
        '5' => A.led_5,
        '6' => A.led_6,
        '7' => A.led_7,
        '8' => A.led_8,
        else => A.led_9,
    };
}

fn faceSprite() u16 {
    // 按住人脸按钮 → 按下脸（结束后按也算：那是"准备重开"的手势）
    if (face_down) return A.face_down;
    if (game.over) return if (game.win) A.face_win else A.face_dead;
    // 棋盘上按着键（准备翻开 / 准备展开 / 插旗）→ 脸扫雷
    if (boardHeld()) return A.face_scan;
    // 动作刚做完的那 200ms 也保持脸扫雷（由 TIMER_FLASH 收回）
    if (nowMs() < face_flash_until) return A.face_scan;
    return A.face_normal;
}
/// 棋盘上是否有键按着：左键（不是按在人脸上）、右键、中键都算
fn boardHeld() bool {
    return r_down or m_down or (l_down and !face_down);
}
/// 展开一格邻域（左右键同时点击 / 中键松手时走这条）：真展开了就让脸闪一下，
/// 结束时（踩雷/通关）不闪，直接交给死亡脸/胜利脸。
fn doExpand(hwnd: w.HWND, c: usize) void {
    const m0 = game.moves;
    game.tryExpand(c);
    afterGameAction(hwnd);
    if (game.moves != m0 and !game.over) flashFace(hwnd);
    _ = w.InvalidateRect(hwnd, null, 0);
}

// ------------------------------------------------------------------ 音效
// 六段音效全都编在 exe 里（sounds.bin，见 tools/gen_sounds.js），运行时用
// PlaySound(SND_MEMORY | SND_ASYNC) 播：不阻塞消息循环，也不读磁盘。
// 三种时机：踩雷按那一格的雷型播、通关播 win、计时从 1 秒起每整秒一下 tick。
/// 每个槽位播过几次（自检用；ReleaseSmall 下没人读也不会有人写，代价可以忽略）
var sound_log: [snd.count]u32 = [_]u32{0} ** snd.count;
/// 一盘只播一次结束音（踩雷/通关），重开时复位
var over_sound_done: bool = false;
/// 上一次播 tick 的秒数（-1 = 还没播过）
var tick_second: i32 = -1;
/// 命令行里除了 exe 路径之外的参数个数（0 = 用户双击运行 → 要出声）
var arg_count: usize = 0;
/// 用户在「游戏 → 颜色」里关掉颜色了吗（默认开着 = 用彩色贴图；关掉 = 用黑白贴图）
var color_off: bool = false;
/// 强制静音：自检/抓图/导出这些非交互模式一律静音（逻辑照跑、计数照记，只是不真的放音）
var sound_muted: bool = false;
/// 用户在「游戏 → 声音」里关掉的（默认开着）。它和 sound_muted 是两回事：
/// 前者是用户的选择（写进注册表，下次还关着），后者是非交互模式的强制静音。
var sound_off: bool = false;

/// 用户是不是"双击运行"（没带任何开关）
fn interactive() bool {
    return arg_count == 0;
}

/// 这一下到不到耳朵里：非交互模式静音、或者用户把声音关了，都不放音。
/// 注意计数（sound_log）不受影响——自检验的是"什么时候该播哪一段"。
fn audible() bool {
    return !sound_muted and !sound_off;
}

fn playSound(s: snd.Sounds) void {
    const i = @intFromEnum(s);
    sound_log[i] +%= 1;
    if (!audible()) return;
    const bytes = snd.wav(i);
    _ = w.PlaySoundW(@ptrCast(bytes.ptr), null, w.SND_MEMORY | w.SND_ASYNC | w.SND_NODEFAULT);
}

/// 声音偏好写在和纪录同一个注册表键下（Sound = 1 开 / 0 关；没这一项就是默认开）。
/// 自检模式整个不碰注册表，和纪录一样（见 scores_persist 的说明）。
fn loadSoundPref() void {
    if (!scores_persist) return;
    var hkey: usize = 0;
    if (w.RegOpenKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, w.KEY_READ, &hkey) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    var data: u32 = 1;
    var size: u32 = @sizeOf(u32);
    var kind: u32 = 0;
    if (w.RegQueryValueExW(hkey, w.wstr("Sound"), null, &kind, @ptrCast(&data), &size) == w.ERROR_SUCCESS) {
        sound_off = (data == 0);
    }
}

/// 颜色偏好（Color = 1 彩色 / 0 黑白；没这一项就是 1）
fn loadColorPref() void {
    if (!scores_persist) return;
    var hkey: usize = 0;
    if (w.RegOpenKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, w.KEY_READ, &hkey) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    var data: u32 = 1;
    var size: u32 = @sizeOf(u32);
    var kind: u32 = 0;
    if (w.RegQueryValueExW(hkey, w.wstr("Color"), null, &kind, @ptrCast(&data), &size) == w.ERROR_SUCCESS) {
        color_off = (data == 0);
    }
}

fn saveColorPref() void {
    if (!scores_persist) return;
    var hkey: usize = 0;
    if (w.RegCreateKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, null, w.REG_OPTION_NON_VOLATILE, w.KEY_WRITE, null, &hkey, null) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    const v: u32 = if (color_off) 0 else 1;
    _ = w.RegSetValueExW(hkey, w.wstr("Color"), 0, w.REG_DWORD, @ptrCast(&v), @sizeOf(u32));
}

/// 菜单里点一下「颜色」：彩色 ↔ 黑白
fn toggleColor(hwnd: w.HWND) void {
    color_off = !color_off;
    saveColorPref();
    checkMenu();
    _ = w.InvalidateRect(hwnd, null, 0);
}

fn saveSoundPref() void {
    if (!scores_persist) return;
    var hkey: usize = 0;
    if (w.RegCreateKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, null, w.REG_OPTION_NON_VOLATILE, w.KEY_WRITE, null, &hkey, null) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    const v: u32 = if (sound_off) 0 else 1;
    _ = w.RegSetValueExW(hkey, w.wstr("Sound"), 0, w.REG_DWORD, @ptrCast(&v), @sizeOf(u32));
}

/// 菜单里点一下「声音」：开→关、关→开。关掉时顺手把正在响的那一段掐掉
/// （PlaySoundW 传空指针就是停止播放）。
fn toggleSound(hwnd: w.HWND) void {
    sound_off = !sound_off;
    if (sound_off) _ = w.PlaySoundW(null, null, 0);
    saveSoundPref();
    checkMenu();
    _ = hwnd;
}

/// 计时走到 1 秒之后，每过一整秒播一下 tick。没开局、已结束、或者还在同一秒里都不播——
/// 消息循环被卡住导致一次跳过好几秒时也只补一下，不会连着炸一串。
fn maybePlayTick() void {
    if (!game.started or game.over) return;
    const sec = timerSeconds();
    if (sec < 1 or sec == tick_second) return;
    tick_second = sec;
    playSound(.tick);
}

/// 触发一次「脸扫雷」闪动（翻格/插旗时调用）
fn flashFace(hwnd: w.HWND) void {
    face_flash_until = nowMs() +% FACE_FLASH_MS;
    _ = w.SetTimer(hwnd, TIMER_FLASH, FACE_FLASH_MS, null);
}

fn timerSeconds() i32 {
    if (!game.started) return 0;
    return @intCast(@min(@as(u32, 9999), game.elapsed_ms / 1000));
}

fn nowMs() u32 {
    return w.GetTickCount();
}

// ------------------------------------------------------------------ 绘制
fn paint(dc: w.HDC, L: Layout) void {
    // 背景
    fill(dc, 0, 0, L.client_w, L.client_h, C_BTNFACE);
    // 外框（凸起）
    draw3d(dc, 0, 0, L.client_w, L.client_h, L.frame, true);

    // 凸起面板（计雷器 + 人脸 + 计时）
    const hx = L.header_x;
    const hy = L.header_y;
    const hh = L.header_h;
    const hw2 = L.header_w;
    draw3d(dc, hx, hy, hw2, hh, 2 * L.z, false);

    // 四个计雷器：竖排一列。实雷四格数字，虚雷三格数字 + 一格 i，五块面板因此等宽。
    const col_x = countersX(L);
    var cy = countersY(L);
    for (1..5) |t| {
        const val = counterShown(t);
        const imag = counterImag(t);
        const cw2 = counterWidth(L.z, panelCells(imag, val));
        draw3d(dc, col_x, cy, cw2, 26 * L.z, 1 * L.z, false);
        blitSpriteSq(dc, flagSprite(@intCast(t)), col_x + L.z + L.z, cy + @divTrunc(26 * L.z - 16 * L.z, 2), 16 * L.z);
        const led_x = col_x + L.z + 2 * L.z + 16 * L.z;
        const led_y = cy + @divTrunc(26 * L.z - 23 * L.z, 2);
        const vw = drawLed(dc, led_x, led_y, val, panelValueDigits(imag, val), L.z);
        // 单位雷还有第四格单位记号（没开局时那一格也画成空格子，不留白）：
        // 圆复数模式是 i，闵可夫斯基模式是 j
        if (imag) blitSprite(dc, if (val == null) A.led_blank else if (hyper()) A.led_j else A.led_i, led_x + vw, led_y, 13 * L.z, 23 * L.z);
        cy += 26 * L.z + 2 * L.z;
    }
    // 计时（右对齐，垂直居中；同样是四格数字）
    const tx = timerX(L);
    const ty = timerY(L);
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    draw3d(dc, tx, ty, timerWidth(L.z), 26 * L.z, 1 * L.z, false);
    _ = drawLed(dc, tx + L.z, ty + @divTrunc(26 * L.z - 23 * L.z, 2), tv, panelValueDigits(false, tv), L.z);

    // 人脸：贴图自带立体边，直接贴，不再画边框
    blitSpriteSq(dc, faceSprite(), faceLeft(L), faceTop(L), FACE_SIZE * L.z);

    // 棋盘凹槽
    const bx = L.board_x - L.box;
    const by = L.board_y - L.box;
    const bw = @as(i32, game.w) * L.cell + 2 * L.box;
    const bh = @as(i32, game.h) * L.cell + 2 * L.box;
    draw3d(dc, bx, by, bw, bh, L.box, false);

    // 格子
    var i: usize = 0;
    while (i < game.n) : (i += 1) {
        const r: i32 = @intCast(i / game.w);
        const c: i32 = @intCast(i % game.w);
        const x = L.board_x + c * L.cell;
        const y = L.board_y + r * L.cell;
        blitSpriteSq(dc, cellSprite(i), x, y, L.cell);
    }
    // 没有状态行：原版扫雷底部就是空的（判据不通过时不作任何提示，只留状态枚举给自检）
}

/// 贴图按"雷的类型"查表（1 正实雷·正类空雷 / 2 负实雷·负类空雷 / 3 正虚雷·正双曲虚雷 / 4 负虚雷·负双曲虚雷）。
/// 1、2 两种实雷（闵可夫斯基模式下叫类空雷）两个模式共用贴图；
/// 3、4 在闵可夫斯基模式下换成 h 前缀那几张（±j 的画法不同，那边叫类时雷）。
/// 表由 tools/gen_atlas.js 生成，缺哪张会自动退回上一档，见 src/assets.zig。
fn mineSprite(t: u8) u16 {
    return (if (hyper()) A.hmine_T else A.mine_T)[@min(@as(usize, t), 4)];
}
fn flagSprite(t: u8) u16 {
    return (if (hyper()) A.hflag_T else A.flag_T)[@min(@as(usize, t), 4)];
}
fn boomSprite(t: u8) u16 {
    return (if (hyper()) A.hboom_T else A.boom_T)[@min(@as(usize, t), 4)];
}
/// 标错雷：这一格插错了旗，按**真实雷型**出图，提醒玩家正确答案
fn wrongSprite(t: u8) u16 {
    return (if (hyper()) A.hwrong_T else A.wrong_T)[@min(@as(usize, t), 4)];
}
/// 标对雷：这一格插对了（失败后显示，让玩家看出自己判断对的地方）
fn rightSprite(t: u8) u16 {
    return (if (hyper()) A.hright_T else A.right_T)[@min(@as(usize, t), 4)];
}
/// 标对旗：胜利后显示"这一格的旗插对了"
fn rightFlagSprite(t: u8) u16 {
    return (if (hyper()) A.hrightflag_T else A.rightflag_T)[@min(@as(usize, t), 4)];
}
/// 标错旗：胜利后显示"这一格的旗插错了"，同样按真实雷型出图
fn wrongFlagSprite(t: u8) u16 {
    return (if (hyper()) A.hwrongflag_T else A.wrongflag_T)[@min(@as(usize, t), 4)];
}

/// 这一格能不能作为展开的起点（门槛和 Game.tryExpand 一致：已翻开的非雷格，且还有未插旗的邻格）
fn chordable(c: usize) bool {
    if (c >= game.n) return false;
    if (game.over or game.open[c] == 0 or game.mine[c] != 0) return false;
    var buf: [8]usize = undefined;
    const k = game.nbrs(c, &buf);
    for (buf[0..k]) |j| {
        if (game.open[j] == 0 and game.flag[j] == 0) return true;
    }
    return false;
}

/// 这一格是不是"按住期间即将被展开"的：chord_cell 的未翻开、未插旗邻格。
/// 注意只看"这个手势会碰哪些格子"，不看判据——判据不通过时棋盘上不给任何提示。
fn chordTarget(i: usize) bool {
    if (chord_cell < 0) return false;
    const c: usize = @intCast(chord_cell);
    if (!chordable(c)) return false;
    if (game.open[i] != 0 or game.flag[i] != 0) return false;
    var buf: [8]usize = undefined;
    const k = game.nbrs(c, &buf);
    for (buf[0..k]) |j| {
        if (j == i) return true;
    }
    return false;
}

fn cellSprite(i: usize) u16 {
    // 按住不放的那一格：画成已翻开的空白（传统扫雷的按下预览），松手才真翻开
    if (press_cell >= 0 and @as(usize, @intCast(press_cell)) == i and game.open[i] == 0) return A.blank;
    // 左右键同时按住 / 中键按住：这一格待会儿会被展开，先画成空白（松开才真展开）
    if (chordTarget(i)) return A.blank;
    const revealed = game.over and !game.win;
    if (game.open[i] != 0) {
        if (game.mine[i] != 0) {
            if (game.boom == @as(i32, @intCast(i))) return boomSprite(game.mine[i]);
            return mineSprite(game.mine[i]);
        }
        const D = game.clue[i];
        if (D == 0 and game.nbrMineCount(i) == 0) return A.blank;
        // 两个模式各查各的表：圆复数模式 a²+b²（0…64），闵可夫斯基模式 a²−b²（−64…64，下标 +64）
        const s = if (hyper())
            A.hnum_by_D[@intCast(D + 64)]
        else
            A.num_by_D[@intCast(D)];
        return if (s == 0xFFFF) A.blank else s;
    }
    if (game.flag[i] != 0) {
        const t = game.mine[i]; // 0 = 这里其实不是雷
        const f = game.flag[i]; // 玩家插的旗的类型
        if (revealed) {
            // 失败后的复盘：给空格子插了旗 → 标错空格子；插错了 → 标错雷（按真实雷型）；
            // 插对了 → 标对雷（让玩家看见自己判断对的地方）
            if (t == 0) return A.wrongblank_sprite;
            if (f == t) return rightSprite(t);
            return wrongSprite(t);
        }
        if (game.win) {
            // 胜利后的复盘：胜利时所有非雷格都已经翻开，所以这里的旗都在雷上。
            // 插对了 → 标对旗；插错了 → 标错旗（同样按真实雷型出图）
            if (t != 0 and f == t) return rightFlagSprite(t);
            return wrongFlagSprite(if (t != 0) t else f);
        }
        return flagSprite(f);
    }
    if (revealed and game.mine[i] != 0) return mineSprite(game.mine[i]);
    return A.closed;
}

const Msg = g.Msg;

/// 自定义对话框的校验错误
const DlgErr = enum(u8) { none = 0, height, width, sum_zero, sum_big };
fn dlgErrText(e: DlgErr) [*:0]const u16 {
    return switch (e) {
        .none => w.wstr(""),
        .height => w.wstr("高度要在 9 – 30 之间。"),
        .width => w.wstr("宽度要在 9 – 40 之间。"),
        .sum_zero => w.wstr("四种雷合计至少 1 颗。"),
        .sum_big => w.wstr("合计超过上限（格数 − 9）。"),
    };
}

// ------------------------------------------------------------------ 双缓冲
fn ensureMemDc(hwnd: w.HWND, L: Layout) void {
    if (mem_dc != null and mem_w == L.client_w and mem_h == L.client_h) return;
    const dc = w.GetDC(hwnd);
    if (mem_bmp != null) {
        _ = w.SelectObject(mem_dc, w.GetStockObject(0));
        _ = w.DeleteObject(mem_bmp);
        _ = w.DeleteDC(mem_dc);
    }
    mem_dc = w.CreateCompatibleDC(dc);
    mem_bmp = w.CreateCompatibleBitmap(dc, L.client_w, L.client_h);
    _ = w.SelectObject(mem_dc, mem_bmp);
    mem_w = L.client_w;
    mem_h = L.client_h;
    _ = w.SetStretchBltMode(mem_dc, 3); // COLORONCOLOR = 最近邻
    _ = w.ReleaseDC(hwnd, dc);
}

fn repaint(hwnd: w.HWND) void {
    const L = layout();
    ensureMemDc(hwnd, L);
    paint(mem_dc, L);
    const dc = w.GetDC(hwnd);
    _ = w.BitBlt(dc, 0, 0, L.client_w, L.client_h, mem_dc, 0, 0, w.SRCCOPY);
    _ = w.ReleaseDC(hwnd, dc);
}

/// 窗口标题固定不变（难度、局面信息都不往标题里塞）
const APP_TITLE = "复扫雷 Complexweeper";
/// 版本号：**只有这一处**。以后每次改动都顺手把它 +1，关于对话框与两个自检报告的抬头都读它。
const APP_VERSION = "1.3.0";

// ------------------------------------------------------------------ 棋盘交互
fn cellAt(L: Layout, px: i32, py: i32) i32 {
    const cx = px - L.board_x;
    const cy = py - L.board_y;
    if (cx < 0 or cy < 0) return -1;
    const c = @divTrunc(cx, L.cell);
    const r = @divTrunc(cy, L.cell);
    if (c < 0 or r < 0 or c >= game.w or r >= game.h) return -1;
    return @intCast(@as(usize, @intCast(r)) * game.w + @as(usize, @intCast(c)));
}

fn inFace(L: Layout, px: i32, py: i32) bool {
    const fw = FACE_SIZE * L.z;
    const fx = faceLeft(L);
    const fy = faceTop(L);
    return px >= fx and py >= fy and px < fx + fw and py < fy + fw;
}

fn startNewGame(seed_override: ?u32) void {
    const seed = seed_override orelse @as(u32, @intCast(w.GetTickCount()));
    game.newGame(seed);
    // 重开时把"按住/按下"的临时状态一起清掉（可能从菜单或人脸按钮进来）
    press_cell = -1;
    chord_cell = -1;
    l_down = false;
    r_down = false;
    m_down = false;
    face_down = false;
    face_armed = false;
    face_flash_until = 0;
    // 音效也要复位：结束音重新允许播，计时的"上一个整秒"清掉
    over_sound_done = false;
    tick_second = -1;
    _ = w.KillTimer(hwnd_main, TIMER_FLASH);
    _ = w.InvalidateRect(hwnd_main, null, 0);
}

fn setPreset(idx: i32, m: g.Mode) void {
    if (idx >= 0 and idx < g.PRESETS.len) {
        const p = g.PRESETS[@intCast(idx)];
        game.w = p.w;
        game.h = p.h;
        game.mines = p.mines;
        game.type_count = [_]u16{0} ** 5;
    }
    game.mode = m;
    cur_preset = idx;
    syncMode();
    resizeWindowForBoard();
    startNewGame(null);
}

/// 模式或难度换了之后要跟着走的：菜单圆点、当前模式的那套纪录。
/// 换模式要重新读纪录（两个模式各记一套），所以这里顺手 loadScores。
/// 标题栏不跟着模式变——两个模式共用同一个标题（当前模式看菜单里的圆点）。
fn syncMode() void {
    // 换模式要换一整套纪录（两个模式各记三档）。自检模式下整个不碰纪录表，
    // 否则会把自检自己注入的分数擦掉。
    if (scores_persist) loadScores();
    checkMenu();
}

fn resizeWindowForBoard() void {
    const L = layout();
    var r = w.RECT{ .left = 0, .top = 0, .right = L.client_w, .bottom = L.client_h };
    const style: w.DWORD = w.WS.OVERLAPPED | w.WS.CAPTION | w.WS.SYSMENU | w.WS.MINIMIZEBOX;
    _ = w.AdjustWindowRect(&r, style, w.TRUE);
    _ = w.SetWindowPos(hwnd_main, null, 0, 0, r.right - r.left, r.bottom - r.top, 0x0002 | 0x0004 | 0x0010); // NOMOVE|NOZORDER|NOACTIVATE
}

// ------------------------------------------------------------------ 自定义对话框
var dlg_state: struct {
    h: i32 = 16,
    w: i32 = 30,
    t: [5]i32 = .{ 0, 25, 25, 25, 24 },
    err: DlgErr = .none,
} = .{};

fn getEditInt(h: w.HWND, fallback: i32) i32 {
    var buf: [16]u16 = undefined;
    const n = w.GetWindowTextW(h, &buf, 16);
    if (n <= 0) return fallback;
    var v: i32 = 0;
    var any = false;
    for (buf[0..@intCast(n)]) |ch| {
        if (ch < '0' or ch > '9') continue;
        v = v * 10 + @as(i32, @intCast(ch - '0'));
        any = true;
        if (v > 100000) v = 100000;
    }
    return if (any) v else fallback;
}

fn setEditInt(h: w.HWND, v: i32) void {
    var buf: [16]u16 = undefined;
    const s = w.u32ToW(&buf, @intCast(v));
    _ = w.SetWindowTextW(h, s.ptr);
}

/// 读四个「每种雷颗数」编辑框（edit_handles[2..5]）。
/// 别写成 edit_handles[1..4]——那会把宽度框当成第一种雷（这个 bug 被 uitest 抓过一次）。
fn readDlgCounts() [5]i32 {
    var t = [5]i32{ 0, 0, 0, 0, 0 };
    for (1..5) |k| t[k] = getEditInt(edit_handles[k + 1], 0);
    return t;
}

fn dlgWndProc(hwnd: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.c) w.LRESULT {
    switch (msg) {
        // 整个对话框是白的：静态标签用白刷子当背景（不返回刷子的话，空白标签会画出一条
        // 白条——就是"按合计均分右边那个奇怪的白条"，其实是错误提示那格 STATIC）。
        w.WM.CTLCOLORSTATIC => {
            const dc: w.HDC = @ptrFromInt(wp);
            _ = w.SetBkMode(dc, 1); // TRANSPARENT
            _ = w.SetTextColor(dc, C_BLACK);
            return @bitCast(@intFromPtr(dlg_bg_brush));
        },
        w.WM.CTLCOLOREDIT => return @bitCast(@intFromPtr(dlg_bg_brush)),
        w.WM.ERASEBKGND => {
            var rc: w.RECT = undefined;
            _ = w.GetClientRect(hwnd, &rc);
            const dc: w.HDC = @ptrFromInt(wp);
            _ = w.FillRect(dc, &rc, dlg_bg_brush);
            return 1;
        },
        w.WM.COMMAND => {
            const id = @as(i32, @intCast(@as(u16, @truncate(wp))));
            if (id == IDC_BTN_OK) {
                dlgApply();
                return 0;
            } else if (id == IDC_BTN_CANCEL) {
                dialog_cancel = true;
                dialog_done = true;
                return 0;
            } else if (id == IDC_BTN_SPLIT) {
                var sum: i32 = 0;
                const cur = readDlgCounts();
                for (1..5) |t| sum += cur[t];
                if (sum <= 0) sum = 99;
                const sp = g.splitEvenly(@intCast(@min(sum, 999)));
                for (1..5) |t| setEditInt(edit_handles[t + 1], sp[t]);
                return 0;
            }
            return 0;
        },
        w.WM.KEYDOWN => {
            const vk = wp;
            if (vk == 0x0D) { // Enter
                dlgApply();
                return 0;
            } else if (vk == 0x1B) { // Esc
                dialog_cancel = true;
                dialog_done = true;
                return 0;
            } else if (vk == 0x09) { // Tab：在编辑框之间轮换
                const cur = w.GetFocus();
                var idx: usize = 0;
                for (0..6) |i| {
                    if (edit_handles[i] == cur) idx = i;
                }
                idx = (idx + 1) % 6;
                _ = w.SetFocus(edit_handles[idx]);
                return 0;
            }
            return 0;
        },
        w.WM.CLOSE => {
            dialog_cancel = true;
            dialog_done = true;
            return 0;
        },
        else => return w.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

fn dlgApply() void {
    const h = getEditInt(edit_handles[0], 16);
    const ww = getEditInt(edit_handles[1], 30);
    const t = readDlgCounts();
    var sum: i32 = 0;
    for (1..5) |k| sum += t[k];
    if (h < 9 or h > 30) {
        dlg_state.err = .height;
        setErrText();
        return;
    }
    if (ww < 9 or ww > 40) {
        dlg_state.err = .width;
        setErrText();
        return;
    }
    if (sum < 1) {
        dlg_state.err = .sum_zero;
        setErrText();
        return;
    }
    const maxm = ww * h - 9;
    if (sum > maxm) {
        dlg_state.err = .sum_big;
        setErrText();
        return;
    }
    dlg_state.err = .none;
    setErrText();
    game.w = @intCast(ww);
    game.h = @intCast(h);
    game.mines = @intCast(sum);
    game.type_count = .{ 0, @intCast(t[1]), @intCast(t[2]), @intCast(t[3]), @intCast(t[4]) };

    dialog_done = true;
}

fn setErrText() void {
    _ = w.SetWindowTextW(dlg_err_hwnd, dlgErrText(dlg_state.err));
}

/// 建对话框窗口与控件。与模态循环分开，便于自检直接驱动。
fn createCustomWindow() bool {
    dialog_done = false;
    dialog_cancel = false;
    if (dlg_bg_brush == null) dlg_bg_brush = w.CreateSolidBrush(C_WHITE);
    var wc: w.WNDCLASSEXW = std.mem.zeroes(w.WNDCLASSEXW);
    wc.cbSize = @sizeOf(w.WNDCLASSEXW);
    wc.lpfnWndProc = dlgWndProc;
    wc.hInstance = w.GetModuleHandleW(null);
    wc.hCursor = w.LoadCursorW(null, @ptrFromInt(w.IDC.ARROW));
    wc.hbrBackground = dlg_bg_brush; // 白底
    wc.lpszClassName = w.wstr(CLASS_DLG);
    _ = w.RegisterClassExW(&wc);

    const dw: i32 = 330;
    const dh: i32 = 308; // 去掉"四种雷各自的颗数"那一行之后，高度跟着收 22
    const scr_w = w.GetSystemMetrics(w.SM.CXSCREEN);
    const scr_h = w.GetSystemMetrics(w.SM.CYSCREEN);
    var r = w.RECT{ .left = 0, .top = 0, .right = dw, .bottom = dh };
    _ = w.AdjustWindowRect(&r, w.WS.CAPTION | w.WS.SYSMENU, w.FALSE);
    const win_w = r.right - r.left;
    const win_h = r.bottom - r.top;

    dlg_state.h = game.h;
    dlg_state.w = game.w;
    var tc = game.type_count;
    var any: u16 = 0;
    for (1..5) |t| any += tc[t];
    if (any == 0) tc = g.splitEvenly(game.mines);
    for (1..5) |t| dlg_state.t[t] = tc[t];

    var mr: w.RECT = undefined;
    _ = w.GetWindowRect(hwnd_main, &mr);
    var px = mr.left + 40;
    var py = mr.top + 60;
    if (px + win_w > scr_w) px = scr_w - win_w - 8;
    if (py + win_h > scr_h) py = scr_h - win_h - 8;

    dialog_hwnd = w.CreateWindowExW(0, w.wstr(CLASS_DLG), w.wstr("自定义雷区"), w.WS.CAPTION | w.WS.SYSMENU | w.WS.POPUP, px, py, win_w, win_h, hwnd_main, null, w.GetModuleHandleW(null), null);
    if (dialog_hwnd == null) return false;

    if (dlg_font == null) dlg_font = w.CreateFontW(-12, 0, 0, 0, 400, 0, 0, 0, 134, 0, 0, 0, 0, w.wstr("Microsoft YaHei UI"));
    const font = dlg_font;
    const hinst = w.GetModuleHandleW(null);

    const label = struct {
        fn make(hp: w.HWND, hi: w.HINSTANCE, x: i32, y: i32, cw: i32, ch: i32, font2: w.HFONT, text: [*:0]const u16) w.HWND {
            const h = w.CreateWindowExW(0, w.wstr("STATIC"), text, w.WS.CHILD | w.WS.VISIBLE, x, y, cw, ch, hp, null, hi, null);
            _ = w.SendMessageW(h, 0x0030, @intFromPtr(font2), w.TRUE); // WM_SETFONT
            return h;
        }
    }.make;

    var y: i32 = 12;
    _ = label(dialog_hwnd, hinst, 12, y + 3, 60, 18, font, w.wstr("高度(H)："));
    edit_handles[0] = w.CreateWindowExW(w.WS.EX_CLIENTEDGE, w.wstr("EDIT"), w.wstr(""), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x2000, 78, y, 70, 22, dialog_hwnd, @ptrFromInt(@as(usize, IDC_EDIT_H)), hinst, null);
    _ = w.SendMessageW(edit_handles[0], 0x0030, @intFromPtr(font), w.TRUE);
    _ = label(dialog_hwnd, hinst, 156, y + 3, 150, 18, font, w.wstr("9 – 30 行"));
    y += 30;
    _ = label(dialog_hwnd, hinst, 12, y + 3, 60, 18, font, w.wstr("宽度(W)："));
    edit_handles[1] = w.CreateWindowExW(w.WS.EX_CLIENTEDGE, w.wstr("EDIT"), w.wstr(""), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x2000, 78, y, 70, 22, dialog_hwnd, @ptrFromInt(@as(usize, IDC_EDIT_W)), hinst, null);
    _ = w.SendMessageW(edit_handles[1], 0x0030, @intFromPtr(font), w.TRUE);
    _ = label(dialog_hwnd, hinst, 156, y + 3, 150, 18, font, w.wstr("9 – 40 列"));
    y += 34;

    // 四种雷的名字随模式。双曲（闵可夫斯基）模式下写全名「正实雷（正类空雷）」这种格式，
    // 标签长得多，所以四种雷改成一行一种竖着排，编辑框统一右移到 x=196。
    const names = if (hyper())
        [4][*:0]const u16{
            w.wstr("正实雷（正类空雷）："),       w.wstr("负实雷（负类空雷）："),
            w.wstr("正双曲虚雷（正类时雷）："), w.wstr("负双曲虚雷（负类时雷）："),
        }
    else
        [4][*:0]const u16{ w.wstr("正实雷："), w.wstr("负实雷："), w.wstr("正虚雷："), w.wstr("负虚雷：") };
    var k: usize = 0;
    while (k < 4) : (k += 1) {
        const yy = y + @as(i32, @intCast(k)) * 28;
        _ = label(dialog_hwnd, hinst, 12, yy + 3, 200, 18, font, names[k]);
        edit_handles[k + 2] = w.CreateWindowExW(w.WS.EX_CLIENTEDGE, w.wstr("EDIT"), w.wstr(""), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x2000, 220, yy, 62, 22, dialog_hwnd, @ptrFromInt(@as(usize, @intCast(IDC_EDIT_T1 + @as(i32, @intCast(k))))), hinst, null);
        _ = w.SendMessageW(edit_handles[k + 2], 0x0030, @intFromPtr(font), w.TRUE);
        setEditInt(edit_handles[k + 2], dlg_state.t[k + 1]);
    }
    y += 4 * 28 + 6;
    const split_btn = w.CreateWindowExW(0, w.wstr("BUTTON"), w.wstr("按合计均分"), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP, 12, y, 100, 24, dialog_hwnd, @ptrFromInt(@as(usize, IDC_BTN_SPLIT)), hinst, null);
    _ = w.SendMessageW(split_btn, 0x0030, @intFromPtr(font), w.TRUE);
    dlg_err_hwnd = label(dialog_hwnd, hinst, 120, y + 3, 200, 18, font, w.wstr(""));
    y += 34;
    const ok_btn = w.CreateWindowExW(0, w.wstr("BUTTON"), w.wstr("确定"), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x0001, 122, y, 88, 26, dialog_hwnd, @ptrFromInt(@as(usize, IDC_BTN_OK)), hinst, null);
    _ = w.SendMessageW(ok_btn, 0x0030, @intFromPtr(font), w.TRUE);
    const cancel_btn = w.CreateWindowExW(0, w.wstr("BUTTON"), w.wstr("取消"), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP, 218, y, 88, 26, dialog_hwnd, @ptrFromInt(@as(usize, IDC_BTN_CANCEL)), hinst, null);
    _ = w.SendMessageW(cancel_btn, 0x0030, @intFromPtr(font), w.TRUE);

    setEditInt(edit_handles[0], dlg_state.h);
    setEditInt(edit_handles[1], dlg_state.w);
    setErrText();
    _ = w.ShowWindow(dialog_hwnd, w.SW.SHOW);
    _ = w.SetFocus(edit_handles[0]);
    return true;
}

fn closeCustomWindow() void {
    if (dialog_hwnd != null) {
        _ = w.DestroyWindow(dialog_hwnd);
        dialog_hwnd = null;
    }
}

fn runCustomDialog() bool {
    if (!createCustomWindow()) return false;
    var msg: w.MSG = undefined;
    while (!dialog_done) {
        const r2 = w.GetMessageW(&msg, null, 0, 0);
        if (r2 <= 0) break;
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }
    closeCustomWindow();
    return !dialog_cancel;
}

// ------------------------------------------------------------------ 最高分纪录
// 三档标准难度各记一个最快通关用时（秒），写在 HKCU\Software\Complexweeper 下，
// 和原版扫雷一样用注册表，所以分发仍然只有一个 exe、不会多出存档文件。
// 自定义棋盘不计入（尺寸/雷数任意，比时间没有意义）。
const REG_PATH = "Software\\Complexweeper";
/// 纪录键名按模式分开：圆复数模式沿用原来那三个键（老纪录还在），闵可夫斯基模式另起一套。
/// 两个模式的难度档位虽然同名同尺寸，但盘面数值规则不同，混在一张表里比时间没有意义。
const SCORE_VALUES_CPLX = [3][*:0]const u16{ w.wstr("Beginner"), w.wstr("Intermediate"), w.wstr("Expert") };
const SCORE_VALUES_HYPER = [3][*:0]const u16{ w.wstr("HyperBeginner"), w.wstr("HyperIntermediate"), w.wstr("HyperExpert") };
fn scoreKeys(m: g.Mode) [3][*:0]const u16 {
    return if (m == .hyper) SCORE_VALUES_HYPER else SCORE_VALUES_CPLX;
}
/// 纪录窗里只出现这三行：难度名 + 用时。棋盘尺寸不写（"游戏"菜单里有），
/// 名字统一两字，等宽字体下三行的用时正好对齐一列。
const SCORE_LABEL = [3][*:0]const u16{
    w.wstr("初级"),
    w.wstr("中级"),
    w.wstr("高级"),
};
/// 下标 0/1/2 = 初级/中级/高级；0 表示还没有纪录
var best_scores = [3]i32{ 0, 0, 0 };
/// 自检里关掉：既不写注册表（纪录、声音偏好都算），也不弹结算窗
var scores_persist = true;
var scores_quiet = false;

/// 当前棋盘是不是标准三档之一；是就返回档位下标，自定义返回 -1
fn presetIndex() i32 {
    for (g.PRESETS, 0..) |p, i| {
        if (game.w == p.w and game.h == p.h and game.mines == p.mines) return @intCast(i);
    }
    return -1;
}

/// 读某个模式的整套纪录（三档）。菜单里两个模式各有一条「最高分纪录」，
/// 点哪条看哪套，所以这里不认"当前模式"，按传进来的模式读。
/// 自检模式整个不碰纪录表：既不写、也不读（否则本机真玩出来的纪录会串进自检的预期里）。
fn readScores(m: g.Mode) [3]i32 {
    var out = [3]i32{ 0, 0, 0 };
    if (!scores_persist) return out;
    var hkey: usize = 0;
    if (w.RegOpenKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, w.KEY_READ, &hkey) != w.ERROR_SUCCESS) return out;
    defer _ = w.RegCloseKey(hkey);
    const keys = scoreKeys(m);
    for (0..3) |i| {
        var data: u32 = 0;
        var size: u32 = @sizeOf(u32);
        var kind: u32 = 0;
        if (w.RegQueryValueExW(hkey, keys[i], null, &kind, @ptrCast(&data), &size) == w.ERROR_SUCCESS) {
            out[i] = @intCast(data);
        }
    }
    return out;
}

/// 当前模式那套纪录（结算时用）
fn loadScores() void {
    best_scores = readScores(game.mode);
}

fn saveScores() void {
    if (!scores_persist) return;
    var hkey: usize = 0;
    if (w.RegCreateKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, null, w.REG_OPTION_NON_VOLATILE, w.KEY_WRITE, null, &hkey, null) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    const keys = scoreKeys(game.mode);
    for (0..3) |i| {
        if (best_scores[i] <= 0) continue;
        const v: u32 = @intCast(best_scores[i]);
        _ = w.RegSetValueExW(hkey, keys[i], 0, w.REG_DWORD, @ptrCast(&v), @sizeOf(u32));
    }
}

// 运行时拼宽字符串（模板是编译期字面量，数字是运行时值）
fn appendW(buf: []u16, n: *usize, src: [*:0]const u16) void {
    var i: usize = 0;
    while (src[i] != 0 and n.* + 1 < buf.len) : (i += 1) {
        buf[n.*] = src[i];
        n.* += 1;
    }
}
fn appendDigits(buf: []u16, n: *usize, v: i32) void {
    if (v <= 0) {
        appendW(buf, n, w.wstr("———"));
        return;
    }
    var tmp: [12]u16 = undefined;
    var k: usize = 0;
    var x: u32 = @intCast(v);
    while (x > 0) : (x /= 10) {
        tmp[k] = @intCast('0' + x % 10);
        k += 1;
    }
    while (k > 0) {
        k -= 1;
        if (n.* + 1 < buf.len) {
            buf[n.*] = tmp[k];
            n.* += 1;
        }
    }
}
fn appendNL(buf: []u16, n: *usize) void {
    appendW(buf, n, w.wstr("\r\n"));
}

/// 装配「最高分纪录」的正文：只有三档纪录本身（没纪录的档给占位符）。对话框与自检共用这一段。
fn buildScoresText(buf: []u16, scores: [3]i32) usize {
    var n: usize = 0;
    for (0..3) |i| {
        appendW(buf, &n, SCORE_LABEL[i]);
        appendW(buf, &n, w.wstr("      "));
        appendDigits(buf, &n, scores[i]);
        if (scores[i] > 0) appendW(buf, &n, w.wstr(" 秒"));
        appendNL(buf, &n);
    }
    return n;
}

/// 弹出"最高分纪录"：只有三档的纪录本身，别的都不写。标题带上模式名
/// —— 两个模式各记一套，不写清楚会以为混在一起。刚破纪录时标题换成"新纪录！"。
fn showBestScores(highlight: bool, m: g.Mode) void {
    var buf: [512]u16 = undefined;
    const n = buildScoresText(&buf, readScores(m));
    buf[n] = 0;
    var tb: [64]u16 = undefined;
    var k: usize = 0;
    appendW(&tb, &k, if (highlight) w.wstr("新纪录！") else w.wstr("最高分纪录"));
    appendW(&tb, &k, if (m == .hyper) w.wstr(" · 双曲复数模式（闵可夫斯基模式）") else w.wstr(" · 圆复数模式"));
    tb[k] = 0;
    _ = w.MessageBoxW(hwnd_main, @ptrCast(&buf), @ptrCast(&tb), w.MB.OK | w.MB.ICONINFORMATION);
}

// ------------------------------------------------------------------ 主窗口
/// 一盘结束后统一处理：结束音效、停表、冻结用时，胜利且进标准三档时结算纪录
fn afterGameAction(hwnd: w.HWND) void {
    if (!game.over) return;
    // 结束音只播一次：这里被翻格/展开等多条路径调用，靠 over_sound_done 兜住
    if (!over_sound_done) {
        over_sound_done = true;
        if (game.win) {
            playSound(.win);
        } else {
            // 踩中的是哪一格 → 按那一格的雷型选音（1..4 与 Game.mine 的编号一致）
            const t: u8 = if (game.boom >= 0) game.mine[@intCast(game.boom)] else 1;
            playSound(snd.Sounds.mineOf(t));
        }
    }
    _ = w.KillTimer(hwnd, TIMER_ID);
    if (game.t0 != 0) game.elapsed_ms = nowMs() -% game.t0;
    if (!game.win) return;
    const idx = presetIndex();
    if (idx < 0) return;
    const sec: i32 = @max(1, @as(i32, @intCast(game.elapsed_ms / 1000)));
    const u: usize = @intCast(idx);
    if (best_scores[u] != 0 and sec >= best_scores[u]) return; // 没破纪录
    best_scores[u] = sec;
    saveScores();
    if (!scores_quiet) showBestScores(true, game.mode);
}
fn mainWndProc(hwnd: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.c) w.LRESULT {
    switch (msg) {
        w.WM.PAINT => {
            var ps: w.PAINTSTRUCT = undefined;
            const dc = w.BeginPaint(hwnd, &ps);
            const L = layout();
            ensureMemDc(hwnd, L);
            paint(mem_dc, L);
            _ = w.BitBlt(dc, 0, 0, L.client_w, L.client_h, mem_dc, 0, 0, w.SRCCOPY);
            _ = w.EndPaint(hwnd, &ps);
            return 0;
        },
        w.WM.ERASEBKGND => return 1,
        // 抓图靠这两条：WM_PRINT 的 HDC 从 wParam 来，客户区自己画、非客户区交回系统；
        // 不接这两条消息的话，PrintWindow 拿到的客户区是空白（无 DWM 合成时尤其明显）。
        w.WM.PRINT => {
            const dc: w.HDC = @ptrFromInt(wp);
            const flags: usize = @bitCast(lp);
            if (dc != null and (flags & 0x04) != 0) paint(dc, layout()); // PRF_CLIENT
            return w.DefWindowProcW(hwnd, msg, wp, lp); // 标题栏/菜单由系统画
        },
        w.WM.PRINTCLIENT => {
            const dc: w.HDC = @ptrFromInt(wp);
            if (dc != null) paint(dc, layout());
            return 0;
        },
        w.WM.TIMER => return onTimer(hwnd, wp),
        w.WM.COMMAND => {
            const id = @as(usize, @intCast(@as(u16, @truncate(wp))));
            return onCommand(hwnd, id);
        },
        w.WM.KEYDOWN => return onKeyDown(wp),
        // 左键按下（含双击的第二下）：只"压住"不翻开，松手才真翻。
        // 「脸按下」**只属于人脸按钮本身**：按棋盘（翻格/展开/插旗）一律不播它，
        // 那时候该出现的是「脸扫雷」——翻格、插旗、展开成功各闪一下。
        w.WM.LBUTTONDOWN, w.WM.LBUTTONDBLCLK => return onLeftDown(hwnd, w.loWord(lp), w.hiWord(lp)),
        w.WM.MOUSEMOVE => return onMouseMove(hwnd, w.loWord(lp), w.hiWord(lp)),
        w.WM.LBUTTONUP => return onLeftUp(hwnd, w.loWord(lp), w.hiWord(lp)),
        w.WM.RBUTTONDOWN, w.WM.RBUTTONDBLCLK => return onRightDown(hwnd, w.loWord(lp), w.hiWord(lp)),
        w.WM.RBUTTONUP => return onRightUp(hwnd, w.loWord(lp), w.hiWord(lp)),
        // 中键：按住时先预览周围即将展开的格子，松手才真展开（不再是按下就展开）。
        // 按住期间人脸播「脸扫雷」（跟按住左键准备翻开一样）。
        w.WM.MBUTTONDOWN, w.WM.MBUTTONDBLCLK => return onMiddleDown(hwnd, w.loWord(lp), w.hiWord(lp)),
        w.WM.MBUTTONUP => return onMiddleUp(hwnd, w.loWord(lp), w.hiWord(lp)),
        w.WM.CAPTURECHANGED => return onCaptureChanged(hwnd),
        w.WM.CLOSE => return onClose(hwnd),
        w.WM.DESTROY => return onDestroy(hwnd),
        else => return w.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

// ------------------------------------------------------------------ 事件处理器
// WndProc 里各条消息的 body 抽成平台无关函数：Win32 的 wndProc 与 GTK 的信号回调
// 都调用这同一批（Phase 1），交互逻辑只写一份。
fn onTimer(hwnd: w.HWND, wp: w.WPARAM) w.LRESULT {
    if (wp == TIMER_FLASH) {
        // 「脸扫雷」那段一闪而过：到点就把脸收回普通状态
        _ = w.KillTimer(hwnd, TIMER_FLASH);
        _ = w.InvalidateRect(hwnd, null, 0);
        return 0;
    }
    if (game.started and !game.over) {
        game.elapsed_ms = w.GetTickCount() -% game.t0;
        maybePlayTick();
    }
    _ = w.InvalidateRect(hwnd, null, 0);
    return 0;
}

fn onCommand(hwnd: w.HWND, id: usize) w.LRESULT {
    handleCommand(hwnd, id);
    return 0;
}

fn onKeyDown(vk: w.WPARAM) w.LRESULT {
    if (vk == 0x72) { // F3
        startNewGame(null);
        return 0;
    }
    return 0;
}

/// 左键按下（含双击的第二下）：只"压住"不翻开，松手才真翻。
fn onLeftDown(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    const L = layout();
    const on_face = inFace(L, x, y);
    l_down = true;
    face_armed = on_face;
    face_down = on_face;
    _ = w.SetCapture(hwnd);
    const c = cellAt(L, x, y);
    if (r_down) {
        // 右键已经按着 → 这是"左右键同时点击"，进入展开预览（松手才真展开）
        chord_cell = c;
        press_cell = -1;
    } else {
        // 传统扫雷：按下不翻开，只把那一格"压住"（画成已翻开的空白），松手才真翻。
        // 拖到别的格子上，按住的格子跟着走；拖出棋盘就取消。
        press_cell = if (c >= 0 and !on_face and !game.over and game.open[@intCast(c)] == 0) c else -1;
    }
    _ = w.InvalidateRect(hwnd, null, 0);
    return 0;
}

fn onMouseMove(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    const L = layout();
    const c = cellAt(L, x, y);
    // 展开预览跟着鼠标走（拖出棋盘就取消）
    if (chord_cell >= 0) {
        const next: i32 = if (c >= 0) c else -1;
        if (next != chord_cell) {
            chord_cell = next;
            _ = w.InvalidateRect(hwnd, null, 0);
        }
        return 0;
    }
    if (press_cell < 0) return 0;
    const next: i32 = if (c >= 0 and game.open[@intCast(c)] == 0) c else -1;
    if (next != press_cell) {
        press_cell = next;
        _ = w.InvalidateRect(hwnd, null, 0);
    }
    return 0;
}

fn onLeftUp(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    const L = layout();
    // 先把这次按下的状态读进局部量：ReleaseCapture() 会**同步**发 WM_CAPTURECHANGED，
    // 而那条消息会把 press_cell / face_armed 清掉（踩过一次：先 ReleaseCapture 再判断，
    // 结果人脸永远重开不了）。
    const held = press_cell;
    const chord = chord_cell;
    const was_face = face_armed;
    l_down = false;
    press_cell = -1;
    chord_cell = -1;
    face_down = false; // 按下脸到此结束——和"正式翻开/展开"同一时刻
    face_armed = false;
    _ = w.ReleaseCapture();
    // 人脸按钮：按下与松开都必须在脸上才算重开（从棋盘拖到脸上松手不算）
    if (was_face and inFace(L, x, y)) {
        _ = w.KillTimer(hwnd, TIMER_ID);
        startNewGame(null);
        return 0;
    }
    // 左右键同时点击：在按住的那一格上松手才真展开
    if (chord >= 0) {
        if (cellAt(L, x, y) == chord) doExpand(hwnd, @intCast(chord));
        _ = w.InvalidateRect(hwnd, null, 0);
        return 0;
    }
    // 只在"按住的那一格"上松手才生效；插了旗的格子左键打不开（传统扫雷：旗子保护它，
    // 要翻开得先用右键把旗循环回"空"）
    if (held >= 0 and cellAt(L, x, y) == held and !game.over and game.flag[@intCast(held)] == 0) {
        const c: usize = @intCast(held);
        const covered = game.open[c] == 0;
        if (!game.started) {
            game.startAt(c, nowMs());
            game.setMsg(.started);
            _ = w.SetTimer(hwnd, TIMER_ID, 250, null);
        } else {
            game.reveal(c, nowMs());
            afterGameAction(hwnd);
        }
        // 真翻开了（或开局连片了）就让脸闪一下；局面已结束时不闪（那时是胜利/死亡脸）
        if (covered and !game.over) flashFace(hwnd);
    }
    _ = w.InvalidateRect(hwnd, null, 0);
    return 0;
}

fn onRightDown(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    // 连点两下时，第二下收到的是 DBLCLK 而不是 DOWN —— 不一起处理的话
    // 快速连点会丢一次按键（实测：连点两下只走一步）。开局前也允许插旗
    // （传统扫雷就是这样，旗帜会保留到开局之后）。
    r_down = true;
    const L = layout();
    const c = cellAt(L, x, y);
    if (l_down) {
        // 左键已经按着 → 这是"左右键同时点击"，进入展开预览（松手才真展开）
        chord_cell = c;
        press_cell = -1;
        _ = w.InvalidateRect(hwnd, null, 0);
        return 0;
    }
    if (c >= 0 and !game.over and game.open[@intCast(c)] == 0) {
        if (game.cycleFlag(@intCast(c))) {
            flashFace(hwnd); // 插旗也算"动手扫雷"，脸闪一下
            _ = w.InvalidateRect(hwnd, null, 0);
        }
    }
    return 0;
}

fn onRightUp(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    r_down = false;
    // 左右键同时点击：先松右键也算数（传统扫雷是"先松哪个都展开"）
    const chord = chord_cell;
    if (chord >= 0) {
        const L = layout();
        chord_cell = -1;
        press_cell = -1;
        face_down = false;
        if (cellAt(L, x, y) == chord) doExpand(hwnd, @intCast(chord));
        _ = w.ReleaseCapture();
        _ = w.InvalidateRect(hwnd, null, 0);
    }
    return 0;
}

fn onMiddleDown(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    const L = layout();
    const c = cellAt(L, x, y);
    m_down = true;
    chord_cell = c;
    press_cell = -1;
    _ = w.SetCapture(hwnd);
    _ = w.InvalidateRect(hwnd, null, 0);
    return 0;
}

fn onMiddleUp(hwnd: w.HWND, x: i32, y: i32) w.LRESULT {
    const L = layout();
    const chord = chord_cell;
    m_down = false;
    chord_cell = -1;
    face_down = false;
    _ = w.ReleaseCapture();
    if (chord >= 0 and cellAt(L, x, y) == chord) doExpand(hwnd, @intCast(chord));
    _ = w.InvalidateRect(hwnd, null, 0);
    return 0;
}

fn onCaptureChanged(hwnd: w.HWND) w.LRESULT {
    if (face_down or face_armed or press_cell >= 0 or chord_cell >= 0 or l_down or r_down or m_down) {
        face_down = false;
        face_armed = false;
        press_cell = -1;
        chord_cell = -1;
        l_down = false;
        r_down = false;
        m_down = false;
        _ = w.InvalidateRect(hwnd, null, 0);
    }
    return 0;
}

fn onClose(hwnd: w.HWND) w.LRESULT {
    _ = w.DestroyWindow(hwnd);
    return 0;
}

fn onDestroy(hwnd: w.HWND) w.LRESULT {
    _ = w.KillTimer(hwnd, TIMER_ID);
    if (mem_dc != null) {
        _ = w.DeleteObject(mem_bmp);
        _ = w.DeleteDC(mem_dc);
        mem_dc = null;
    }
    w.PostQuitMessage(0);
    return 0;
}

/// 自定义对话框点「确定」之后的收尾：菜单与自检走同一条路（顺手把窗口尺寸与局面重排）
fn applyCustomFromDialog() void {
    cur_preset = -1; // 自定义棋盘没有档位，菜单圆点全部落空
    checkMenu();
    resizeWindowForBoard();
    startNewGame(null);
}

fn handleCommand(hwnd: w.HWND, id: usize) void {
    switch (id) {
        IDM_NEW => startNewGame(null),
        IDM_BEGINNER => setPreset(0, .complex),
        IDM_INTERMEDIATE => setPreset(1, .complex),
        IDM_EXPERT => setPreset(2, .complex),
        IDM_CUSTOM => {
            if (runCustomDialog()) applyCustomFromDialog();
        },
        IDM_HYPER_BEGINNER => setPreset(0, .hyper),
        IDM_HYPER_INTERMEDIATE => setPreset(1, .hyper),
        IDM_HYPER_EXPERT => setPreset(2, .hyper),
        IDM_HYPER_CUSTOM => {
            if (runCustomDialog()) applyCustomFromDialog();
        },
        IDM_BEST => showBestScores(false, .complex),
        IDM_SOUND => toggleSound(hwnd),
        IDM_COLOR => toggleColor(hwnd),
        IDM_HYPER_BEST => showBestScores(false, .hyper),
        IDM_EXIT => _ = w.DestroyWindow(hwnd),
        IDM_ZOOM1, IDM_ZOOM2, IDM_ZOOM3 => {
            zoom = switch (id) {
                IDM_ZOOM1 => 1,
                IDM_ZOOM2 => 2,
                else => 3,
            };
            mem_w = 0; // 强制重建后备位图
            resizeWindowForBoard();
            _ = w.InvalidateRect(hwnd, null, 0);
        },
        IDM_HELP_HOW => showHelp(),
        IDM_HELP_ABOUT => showAbout(),
        else => {},
    }
}

/// 「关于」按"克隆作品"的经典署名格式排：产品名（中文名 + 英文名）与版本 → 基于什么
/// （附原版作者）→ 素材与代码的归属 → 授权状态 → 与微软无隶属关系。
/// 第一行直接由 APP_TITLE 拼出来，所以这里的英文名永远和窗口标题一致。
/// 用 MessageBoxIndirect 而不是 MessageBox：只有前者能把**程序自己的图标**放进弹窗
/// （MessageBox 的 dwStyle 只能挑那几个系统预设图标）。
const ABOUT_TEXT = APP_TITLE ++ " " ++ APP_VERSION ++ "\r\n" ++
    "基于 Microsoft® 扫雷(原版作者：Robert Donner、Curt Johnson)\r\n" ++
    "\r\n" ++
    "图像素材来源：Microsoft(扫雷原始图像素材)；青月晓(新增图像素材)。\r\n" ++
    "Copyright © 2026 青月晓\r\n" ++
    "本程序为免费软件\r\n" ++
    "与 Microsoft 公司无隶属关系";

fn showAbout() void {
    const hinst = w.GetModuleHandleW(null);
    if (w.LoadIconW(hinst, w.resId(ICON_RES_ID)) == null) {
        // 中间产物（build\cs.exe）还没注入 .rsrc：退回系统信息图标，弹窗本身照常
        _ = w.MessageBoxW(hwnd_main, w.wstr(ABOUT_TEXT), w.wstr("关于复扫雷"), w.MB.OK | w.MB.ICONINFORMATION);
        return;
    }
    var mp: w.MSGBOXPARAMS = std.mem.zeroes(w.MSGBOXPARAMS);
    mp.cbSize = @sizeOf(w.MSGBOXPARAMS);
    mp.hwndOwner = hwnd_main;
    mp.hInstance = hinst;
    mp.lpszText = w.wstr(ABOUT_TEXT);
    mp.lpszCaption = w.wstr("关于复扫雷");
    mp.dwStyle = w.MB.OK | w.MB.USERICON; // USERICON 这一位才是"用 lpszIcon 那个图标"
    mp.lpszIcon = w.resId(ICON_RES_ID);
    _ = w.MessageBoxIndirectW(&mp);
}

/// 「玩法与操作」正文：一篇文案讲两个模式（开头通用操作，下面两个模式各自写雷名、数字、判据）。
/// 文案由作者定稿，改的时候连分行一起改——弹窗里一行就是这里一行。
const HELP_TEXT = "雷区里有四种雷。\r\n" ++
    "鼠标左键翻开格子，右键插旗，中键或左右键同时点击展开格子。\r\n" ++
    "点击人脸或者按F3 开局。\r\n" ++
    "\r\n" ++
    "圆复数模式：\r\n" ++
    "四种雷分别是正实雷、负实雷、正虚雷、负虚雷。\r\n" ++
    "数字代表该格周围所有雷的加和之模长，均被写为整数或最简根式。\r\n" ++
    "当旗帜数量等于周围真实雷数，且实虚比例符合真实比例或其倒数的时候，可以展开。\r\n" ++
    "\r\n" ++
    "双曲复数模式（闵可夫斯基模式）：\r\n" ++
    "四种雷分别是正实雷（正类空雷）、负实雷（负类空雷）、正双曲虚雷（正类时雷）、负双曲虚雷（负类时雷）。\r\n" ++
    "定义双曲虚数单位（类时单位）j²=1，形式模长（时空间隔）S=√(a²-b²)，所以，可以出现虚数。\r\n" ++
    "（本模式只是从闵可夫斯基时空度规得来的灵感，跟广义相对论没有多大关系。）\r\n" ++
    "数字是该格周围所有雷之加和的形式模长（时空间隔），均被写为整数或最简根式。\r\n" ++
    "当旗帜数量等于周围真实雷数，且实部（类空部）、j部（类时部）的数量等于真实数量时，可以展开。";

fn showHelp() void {
    _ = w.MessageBoxW(hwnd_main, w.wstr(HELP_TEXT), w.wstr("玩法与操作"), w.MB.OK | w.MB.ICONINFORMATION);
}

// ------------------------------------------------------------------ 菜单
// 可移植菜单模型：label 存 UTF-8（含 & 加速键与 tab 提示），id 是命令号或子菜单的 key，
// items 非空即子菜单。Win32 在本文件里按它建 HMENU，GTK 后端照同一棵树建 GtkMenuBar。
const MENU_GAME: usize = 301;
const MENU_CMPLX: usize = 302;
const MENU_HYPER: usize = 303;
const MENU_HELP: usize = 304;

const MENU_MODEL = [_]w.MenuItem{
    .{ .label = "游戏(&G)", .id = MENU_GAME, .items = &[_]w.MenuItem{
        .{ .label = "开局(&N)\tF2", .id = IDM_NEW },
        .{ .label = "", .id = 0 },
        .{ .label = "圆复数模式(&C)", .id = MENU_CMPLX, .items = &[_]w.MenuItem{
            .{ .label = "初级(&B)\t9×9 · 10 雷", .id = IDM_BEGINNER },
            .{ .label = "中级(&I)\t16×16 · 40 雷", .id = IDM_INTERMEDIATE },
            .{ .label = "高级(&E)\t30×16 · 99 雷", .id = IDM_EXPERT },
            .{ .label = "", .id = 0 },
            .{ .label = "最高分纪录(&R)…", .id = IDM_BEST },
            .{ .label = "自定义雷区(&C)…", .id = IDM_CUSTOM },
        } },
        .{ .label = "双曲复数模式（闵可夫斯基模式）(&M)", .id = MENU_HYPER, .items = &[_]w.MenuItem{
            .{ .label = "初级(&B)\t9×9 · 10 雷", .id = IDM_HYPER_BEGINNER },
            .{ .label = "中级(&I)\t16×16 · 40 雷", .id = IDM_HYPER_INTERMEDIATE },
            .{ .label = "高级(&E)\t30×16 · 99 雷", .id = IDM_HYPER_EXPERT },
            .{ .label = "", .id = 0 },
            .{ .label = "最高分纪录(&R)…", .id = IDM_HYPER_BEST },
            .{ .label = "自定义雷区(&C)…", .id = IDM_HYPER_CUSTOM },
        } },
        .{ .label = "", .id = 0 },
        .{ .label = "颜色(&Y)", .id = IDM_COLOR },
        .{ .label = "声音(&S)", .id = IDM_SOUND },
        .{ .label = "缩放 100%", .id = IDM_ZOOM1 },
        .{ .label = "缩放 200%", .id = IDM_ZOOM2 },
        .{ .label = "缩放 300%", .id = IDM_ZOOM3 },
        .{ .label = "", .id = 0 },
        .{ .label = "退出(&X)", .id = IDM_EXIT },
    } },
    .{ .label = "帮助(&H)", .id = MENU_HELP, .items = &[_]w.MenuItem{
        .{ .label = "玩法与操作(&H)", .id = IDM_HELP_HOW },
        .{ .label = "", .id = 0 },
        .{ .label = "关于复扫雷(&A)…", .id = IDM_HELP_ABOUT },
    } },
};

/// buildMenu 建菜单时按 MENU_* key 记住子菜单句柄，checkMenu 再按 key 取回画单选点。
/// 两个平台各自实现：Win32 存 HMENU，GTK 存自己的菜单对象。
const MenuHandles = struct {
    game: w.HMENU = null,
    cplx: w.HMENU = null,
    hyper: w.HMENU = null,
    help: w.HMENU = null,
};
var menu_handles: MenuHandles = .{};

fn recordSubmenu(id: usize, menu: w.HMENU) void {
    switch (id) {
        MENU_GAME => menu_handles.game = menu,
        MENU_CMPLX => menu_handles.cplx = menu,
        MENU_HYPER => menu_handles.hyper = menu,
        MENU_HELP => menu_handles.help = menu,
        else => {},
    }
}

fn appendMenuTree(menu: w.HMENU, items: []const w.MenuItem) void {
    var lb: [160]u16 = undefined;
    for (items) |it| {
        if (it.items.len > 0) {
            const sub = w.CreatePopupMenu();
            recordSubmenu(it.id, sub);
            appendMenuTree(sub, it.items);
            _ = w.AppendMenuW(menu, w.MF.POPUP, @intFromPtr(sub), w.utf8ToW(&lb, it.label).ptr);
        } else if (it.label.len == 0) {
            _ = w.AppendMenuW(menu, w.MF.SEPARATOR, 0, null);
        } else {
            _ = w.AppendMenuW(menu, w.MF.STRING, it.id, w.utf8ToW(&lb, it.label).ptr);
        }
    }
}

fn buildMenu() w.HMENU {
    const bar = w.CreateMenu();
    var lb: [160]u16 = undefined;
    for (MENU_MODEL) |top| {
        const sub = w.CreatePopupMenu();
        recordSubmenu(top.id, sub);
        appendMenuTree(sub, top.items);
        _ = w.AppendMenuW(bar, w.MF.POPUP, @intFromPtr(sub), w.utf8ToW(&lb, top.label).ptr);
    }
    return bar;
}

/// 菜单圆点：只有"当前模式 + 当前难度"那一项是选中态（另一个模式的同名档位不勾），
/// 自定义棋盘或者界面还没定过档位时三档全部落空。
/// 用 CheckMenuRadioItem 画出来的是圆点（原版扫雷那样），不是对勾。
fn radioCheck(menu: w.HMENU, id: usize, on: bool) void {
    if (on) {
        _ = w.CheckMenuRadioItem(menu, @intCast(id), @intCast(id), @intCast(id), w.MF.BYCOMMAND);
    } else {
        _ = w.CheckMenuItem(menu, @intCast(id), w.MF.BYCOMMAND);
    }
}

fn checkMenu() void {
    const game_menu = menu_handles.game orelse return;
    const cur_mode: i32 = if (hyper()) 1 else 0;
    const mode_subs = [_]w.HMENU{ menu_handles.cplx, menu_handles.hyper };
    for (mode_subs, 0..) |sub, k| {
        if (sub == null) continue;
        const pick: i32 = if (cur_mode == @as(i32, @intCast(k))) cur_preset else -1;
        if (pick >= 0 and pick < 3) {
            _ = w.CheckMenuRadioItem(sub, 0, 2, @intCast(pick), w.MF.BYPOSITION);
        } else {
            var i: i32 = 0;
            while (i < 3) : (i += 1) _ = w.CheckMenuItem(sub, @intCast(i), w.MF.BYPOSITION);
        }
    }
    // 颜色/声音两个开关：开着就用单选点画成 XP 那种"被选中的圆点"，关掉整个清掉（圆点消失）。
    // 注意 CheckMenuItem 画的是对勾，CheckMenuRadioItem 画的才是圆点，这里要圆点。
    radioCheck(game_menu, IDM_COLOR, !color_off);
    radioCheck(game_menu, IDM_SOUND, !sound_off);
}

// ------------------------------------------------------------------ 图集
/// exe 里 .rsrc 图标资源的 ID（tools/set_icon.js 写的 RT_GROUP_ICON，里面是 16/32/48 三档）
const ICON_RES_ID: usize = 1;

/// 程序图标 = 素材/图标.png。优先直接用 exe 里注入的那份资源（尺寸齐全、alpha 原样），
/// 拿不到时（例如还没注入 .rsrc 的中间产物 build\cs.exe）才用图集里那张 32×32 现场造一个。
fn makeIcon() w.HICON {
    const hinst = w.GetModuleHandleW(null);
    const from_res = w.LoadIconW(hinst, w.resId(ICON_RES_ID));
    if (from_res != null) return from_res;
    return makeIconFromSprite();
}

/// 从图集里的 icon 贴图造 HICON：32×32 原样拷贝像素（不缩放、不丢 alpha）。
/// 注意不能用 StretchBlt——那会把透明像素当成黑色画上去（图标里 404 个像素是全透明的）。
fn makeIconFromSprite() w.HICON {
    const ic = A.rect(A.icon);
    if (ic.w != 32 or ic.h != 32) return null;
    const dc = w.GetDC(null);
    defer _ = w.ReleaseDC(null, dc);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = 32;
    bi.bmiHeader.biHeight = -32; // 自顶向下，和图集一致
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var cbits: ?*anyopaque = null;
    const color = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &cbits, null, 0);
    var mbits: ?*anyopaque = null;
    const mask = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &mbits, null, 0);
    if (color == null or mask == null or cbits == null or mbits == null) return null;
    const dst: [*]u8 = @ptrCast(cbits.?);
    @memset(dst[0 .. 32 * 32 * 4], 0);
    @memset(@as([*]u8, @ptrCast(mbits.?))[0 .. 32 * 32 * 4], 0);
    // 图集一定已经加载（loadAtlas 在 makeIcon 之前，失败就直接退出了）
    var y: u32 = 0;
    while (y < 32) : (y += 1) {
        const srow = (@as(usize, ic.y + y) * A.atlas_w + ic.x) * 4;
        @memcpy(dst[@as(usize, y) * 32 * 4 ..][0 .. 32 * 4], atlas_pixels[srow..][0 .. 32 * 4]);
    }
    var ii = w.ICONINFO{ .fIcon = w.TRUE, .xHotspot = 0, .yHotspot = 0, .hbmMask = mask, .hbmColor = color };
    return w.CreateIconIndirect(&ii);
}

fn loadAtlas() bool {
    const blob = A.blob;
    if (blob.len < 12) return false;
    if (!(blob[0] == 'C' and blob[1] == 'S' and blob[2] == 'A' and blob[3] == 'T')) return false;
    const bmp_w: i32 = A.atlas_w;
    const bmp_h: i32 = A.atlas_h;
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = bmp_w;
    bi.bmiHeader.biHeight = -bmp_h; // 自顶向下
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const scr = w.GetDC(null);
    atlas_bmp = w.CreateDIBSection(scr, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, scr);
    if (atlas_bmp == null or bits == null) return false;
    atlas_pixels = @ptrCast(bits.?);
    const pix_off: usize = 12 + @as(usize, A.count) * 8;
    const need: usize = @as(usize, @intCast(bmp_w)) * @as(usize, @intCast(bmp_h)) * 4;
    if (blob.len < pix_off + need) return false;
    @memcpy(atlas_pixels[0..need], blob[pix_off .. pix_off + need]);
    atlas_dc = w.CreateCompatibleDC(null);
    atlas_old = w.SelectObject(atlas_dc, atlas_bmp);
    return loadBwAtlas();
}

/// 黑白贴图：blob_bw 是"CSBW"容器里的灰度平面（1 字节/像素），展开成同样尺寸的 32bpp DIB。
/// 没这份素材时就当没有黑白贴图（颜色开关仍然在，只是关掉后还是彩色）。
fn loadBwAtlas() bool {
    const bw = A.blob_bw;
    if (bw.len < 12) return true;
    if (!(bw[0] == 'C' and bw[1] == 'S' and bw[2] == 'B' and bw[3] == 'W')) return true;
    const g_w: i32 = @intCast(@as(u16, bw[6]) | (@as(u16, bw[7]) << 8));
    const g_h: i32 = @intCast(@as(u16, bw[8]) | (@as(u16, bw[9]) << 8));
    if (g_w != @as(i32, A.atlas_w) or g_h != @as(i32, A.atlas_h)) return true;
    const need: usize = @as(usize, @intCast(g_w)) * @as(usize, @intCast(g_h));
    if (bw.len < 12 + need) return true;
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = g_w;
    bi.bmiHeader.biHeight = -g_h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const scr = w.GetDC(null);
    atlas_bw_bmp = w.CreateDIBSection(scr, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, scr);
    if (atlas_bw_bmp == null or bits == null) return true;
    const px: [*]u8 = @ptrCast(bits.?);
    var i: usize = 0;
    while (i < need) : (i += 1) {
        const v = bw[12 + i];
        px[i * 4] = v;
        px[i * 4 + 1] = v;
        px[i * 4 + 2] = v;
        px[i * 4 + 3] = 255;
    }
    atlas_bw_dc = w.CreateCompatibleDC(null);
    atlas_bw_old = w.SelectObject(atlas_bw_dc, atlas_bw_bmp);
    return true;
}

// ------------------------------------------------------------------ 截图 / 自检
fn saveBmp(path: []const u8, pixels: [*]u8, cw: i32, ch: i32) bool {
    const row_bytes: usize = @as(usize, @intCast(cw)) * 4;
    const img_size = row_bytes * @as(usize, @intCast(ch));
    const file_size = 14 + 40 + img_size;
    const f = std.fs.cwd().createFile(path, .{}) catch return false;
    defer f.close();
    var hdr: [54]u8 = [_]u8{0} ** 54;
    hdr[0] = 'B';
    hdr[1] = 'M';
    std.mem.writeInt(u32, hdr[2..6], @intCast(file_size), .little);
    std.mem.writeInt(u32, hdr[10..14], 54, .little);
    std.mem.writeInt(u32, hdr[14..18], 40, .little);
    std.mem.writeInt(i32, hdr[18..22], cw, .little);
    std.mem.writeInt(i32, hdr[22..26], ch, .little);
    std.mem.writeInt(u16, hdr[26..28], 1, .little);
    std.mem.writeInt(u16, hdr[28..30], 32, .little);
    std.mem.writeInt(u32, hdr[34..38], @intCast(img_size), .little);
    f.writeAll(&hdr) catch return false;
    // 从 DIB 里取像素，按 BMP 要求自底向上写
    var row: [4096 * 4]u8 = undefined;
    var y: i32 = ch - 1;
    while (y >= 0) : (y -= 1) {
        const n: usize = @intCast(cw * 4);
        const src = pixels + @as(usize, @intCast(y)) * @as(usize, @intCast(cw * 4));
        @memcpy(row[0..n], src[0..n]);
        f.writeAll(row[0..n]) catch return false;
    }
    return true;
}

// ------------------------------------------------------------------ 入口
var shot_path_buf: [260]u8 = undefined;
var shot_path_len: usize = 0;
var selftest_path_buf: [260]u8 = undefined;
var selftest_path_len: usize = 0;

fn copyPath(dst: []u8, src: []const u8) usize {
    const n = @min(src.len, dst.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

fn shotPath() ?[]const u8 {
    if (shot_path_len == 0) return null;
    return shot_path_buf[0..shot_path_len];
}
fn selftestPath() ?[]const u8 {
    if (selftest_path_len == 0) return null;
    return selftest_path_buf[0..selftest_path_len];
}
var uitest_path_buf: [260]u8 = undefined;
var uitest_path_len: usize = 0;
fn uitestPath() ?[]const u8 {
    if (uitest_path_len == 0) return null;
    return uitest_path_buf[0..uitest_path_len];
}
var dump_path_buf: [260]u8 = undefined;
var dump_path_len: usize = 0;
fn dumpPath() ?[]const u8 {
    if (dump_path_len == 0) return null;
    return dump_path_buf[0..dump_path_len];
}

/// 把当前局面写成文本，用于核对计数器数值等方法：--dump out.txt
fn parseArgs() void {
    var it = std.process.argsWithAllocator(std.heap.page_allocator) catch return;
    defer it.deinit();
    var expect: enum { none, shot, selftest, dump, uitest } = .none;
    var first = true;
    _ = &window_shot;
    while (it.next()) |arg| {
        // 第一个参数是 exe 自己的路径，不算开关
        if (first) {
            first = false;
            continue;
        }
        arg_count += 1;
        switch (expect) {
            .shot => {
                shot_path_len = copyPath(&shot_path_buf, arg);
                expect = .none;
                continue;
            },
            .selftest => {
                selftest_path_len = copyPath(&selftest_path_buf, arg);
                expect = .none;
                continue;
            },
            .dump => {
                dump_path_len = copyPath(&dump_path_buf, arg);
                expect = .none;
                continue;
            },
            .uitest => {
                uitest_path_len = copyPath(&uitest_path_buf, arg);
                expect = .none;
                continue;
            },
            .none => {},
        }
        if (std.mem.eql(u8, arg, "--shot")) expect = .shot;
        if (std.mem.eql(u8, arg, "--selftest")) expect = .selftest;
        if (std.mem.eql(u8, arg, "--dump")) expect = .dump;
        if (std.mem.eql(u8, arg, "--uitest")) expect = .uitest;
        if (std.mem.eql(u8, arg, "--demo")) demo_mode = .mid;
        if (std.mem.eql(u8, arg, "--demo-lose")) demo_mode = .lose;
        if (std.mem.eql(u8, arg, "--demo-win")) demo_mode = .win;
        if (std.mem.eql(u8, arg, "--custom")) demo_mode = .custom;
        if (std.mem.eql(u8, arg, "--demo-hyper")) demo_mode = .hyper;
        if (std.mem.eql(u8, arg, "--demo-judge")) demo_mode = .judge_lose;
        if (std.mem.eql(u8, arg, "--demo-judge-win")) demo_mode = .judge_win;
        if (std.mem.eql(u8, arg, "--zoom1")) zoom = 1;
        if (std.mem.eql(u8, arg, "--zoom2")) zoom = 2;
        if (std.mem.eql(u8, arg, "--zoom3")) zoom = 3;
        // 这两个开关既能写成 `--shot 路径 --sheet`，也能写成 `--sheet 路径`。
        // 所以只有在还没拿到输出路径时才去"期待下一个参数是路径"——否则会把后面的
        // `--quiet` 之类的开关当成文件名（踩过：渲染出的图被存成了名为 `--quiet` 的文件）。
        if (std.mem.eql(u8, arg, "--shot-window")) {
            window_shot = true;
            if (shot_path_len == 0) expect = .shot;
        }
        if (std.mem.eql(u8, arg, "--sheet")) {
            sheet_mode = true;
            if (shot_path_len == 0) expect = .shot;
        }
        if (std.mem.eql(u8, arg, "--quiet")) scores_quiet = true;
    }
}

var window_shot = false;
var sheet_mode = false;

const DemoMode = enum { none, mid, lose, win, custom, hyper, judge_lose, judge_win };
var demo_mode: DemoMode = .none;

/// 造一个可复现的局面用于截图核对
fn setupDemo() void {
    switch (demo_mode) {
        .none => return,
        // 失败后的复盘现场：找一块已翻开的数字格，把它的邻域做成
        // "一颗插对 + 一颗插错 + 一个空格子插旗"，最后再踩一颗没标过的雷结束
        .judge_lose => {
            game.mode = .complex;
            game.w = 16;
            game.h = 16;
            game.mines = 40;
            game.newGame(20260101);
            game.startAt(8 * 16 + 8, 0);
            game.setMsg(.started);
            game.elapsed_ms = 61_000;
            syncMode();
            var host: usize = 0;
            var found = false;
            for (0..game.n) |i| {
                if (game.open[i] == 0 or game.mine[i] != 0) continue;
                var buf: [8]usize = undefined;
                const k = game.nbrs(i, &buf);
                var mi: u32 = 0;
                var fr: u32 = 0;
                for (buf[0..k]) |j| {
                    if (game.mine[j] != 0) {
                        mi += 1;
                    } else if (game.open[j] == 0) {
                        fr += 1;
                    }
                }
                if (mi >= 2 and fr >= 1) {
                    host = i;
                    found = true;
                    break;
                }
            }
            if (found) {
                var buf: [8]usize = undefined;
                const k = game.nbrs(host, &buf);
                var mi: u32 = 0;
                var fr: u32 = 0;
                for (buf[0..k]) |j| {
                    if (game.mine[j] != 0) {
                        mi += 1;
                        // 第一颗插对，第二颗插错
                        const f: u8 = if (mi == 1) game.mine[j] else @as(u8, if (game.mine[j] == 1) 2 else 1);
                        _ = game.setFlag(j, f);
                    } else if (game.open[j] == 0 and fr == 0) {
                        _ = game.setFlag(j, 3);
                        fr += 1;
                    }
                }
            }
            for (0..game.n) |i| {
                if (game.mine[i] != 0 and game.flag[i] == 0) {
                    game.reveal(i, 0);
                    break;
                }
            }
            return;
        },
        // 胜利后的复盘现场：初级盘，雷上隔一颗插对、隔一颗插错，再翻开全部非雷格
        .judge_win => {
            game.mode = .complex;
            game.w = 9;
            game.h = 9;
            game.mines = 10;
            game.newGame(20260101);
            game.startAt(40, 0);
            game.setMsg(.started);
            game.elapsed_ms = 27_000;
            syncMode();
            var mi: u32 = 0;
            for (0..game.n) |i| {
                if (game.mine[i] == 0) continue;
                mi += 1;
                const f: u8 = if (mi % 2 == 1) game.mine[i] else @as(u8, if (game.mine[i] == 1) 2 else 1);
                _ = game.setFlag(i, f);
            }
            for (0..game.n) |i| {
                if (game.mine[i] == 0 and game.open[i] == 0) game.reveal(i, 0);
            }
            afterGameAction(hwnd_main);
            return;
        },
        .hyper => {
            // 闵可夫斯基模式的截图盘：中间开一片，边上一排旗（四种雷各几面），
            // 用来核对负数显示、i 单位、计雷器第四格的 j。
            game.mode = .hyper;
            game.w = 16;
            game.h = 16;
            game.mines = 40;
            game.newGame(20260101);
            game.startAt(8 * 16 + 8, 0);
            game.setMsg(.started);
            game.elapsed_ms = 83_000;
            syncMode();
            var i: usize = 0;
            var opened: u32 = 0;
            while (i < game.n and opened < 24) : (i += 1) {
                if (game.mine[i] != 0 or game.open[i] != 0) continue;
                game.reveal(i, 0);
                opened += 1;
                if (game.over) break;
            }
            var flagged: u32 = 0;
            i = 0;
            while (i < game.n and flagged < 8) : (i += 1) {
                if (game.open[i] != 0) continue;
                _ = game.setFlag(i, @intCast(1 + (flagged % 4)));
                flagged += 1;
            }
            return;
        },
        .custom => {
            game.w = 12;
            game.h = 12;
            game.mines = 14;
            game.type_count = .{ 0, 0, 7, 0, 7 };

            game.newGame(20260101);
            game.startAt(6 * 12 + 6, 0);
            game.setMsg(.started);
            game.elapsed_ms = 42_000;
            return;
        },
        else => {},
    }
    game.w = 16;
    game.h = 16;
    game.mines = 40;

    game.newGame(20260101);
    game.startAt(8 * 16 + 8, 0);
    game.setMsg(.started);
    game.elapsed_ms = 83_000;

    if (demo_mode == .mid) {
        var i: usize = 0;
        var opened: u32 = 0;
        while (i < game.n and opened < 14) : (i += 1) {
            if (game.mine[i] != 0 or game.open[i] != 0) continue;
            game.reveal(i, 0);
            opened += 1;
        }
        var flagged: u32 = 0;
        i = 0;
        while (i < game.n and flagged < 6) : (i += 1) {
            if (game.open[i] != 0) continue;
            _ = game.setFlag(i, @intCast(1 + (flagged % 4)));
            flagged += 1;
        }
    } else if (demo_mode == .win) {
        for (0..game.n) |i| {
            if (game.mine[i] == 0 and game.open[i] == 0) game.reveal(i, 0);
        }
        // 走真实的结算路径：冻结用时 + 结算最高分纪录
        afterGameAction(hwnd_main);
    } else if (demo_mode == .lose) {
        var i: usize = 0;
        var flagged: u32 = 0;
        while (i < game.n and flagged < 4) : (i += 1) {
            if (game.open[i] != 0 or game.mine[i] != 0) continue;
            _ = game.setFlag(i, @intCast(1 + (flagged % 4)));
            flagged += 1;
        }
        i = 0;
        while (i < game.n) : (i += 1) {
            if (game.mine[i] == 2) {
                game.reveal(i, 0);
                break;
            }
        }
    }
}

pub fn main() void {
    parseArgs();
    // 非交互模式（自检、抓图、导出）一律静音：逻辑照跑、计数照记，但别在跑测试时真的炸四声。
    // 真人双击运行时 game_mode 才为 true。
    sound_muted = !interactive();
    if (selftestPath()) |p| {
        const code = runSelftest(p);
        w.ExitProcess(@intCast(code));
    }
    _ = w.SetProcessDPIAware();
    if (!loadAtlas()) {
        _ = w.MessageBoxW(null, w.wstr("内置图集损坏，无法启动。"), w.wstr("错误"), w.MB.OK);
        return;
    }
    game.w = g.PRESETS[2].w;
    game.h = g.PRESETS[2].h;
    game.mines = g.PRESETS[2].mines;

    game.newGame(1);

    const hinst = w.GetModuleHandleW(null);
    var wc: w.WNDCLASSEXW = std.mem.zeroes(w.WNDCLASSEXW);
    wc.cbSize = @sizeOf(w.WNDCLASSEXW);
    wc.style = w.WNDCLASS_STYLES.CS_DBLCLKS;
    wc.lpfnWndProc = mainWndProc;
    wc.hInstance = hinst;
    wc.hCursor = w.LoadCursorW(null, @ptrFromInt(w.IDC.ARROW));
    wc.hbrBackground = null;
    wc.hIcon = makeIcon();
    // 小图标单独按 16×16 取：图标资源里有 16 这一档，直接取比让系统缩 32 的清楚
    const icon16 = w.LoadImageW(hinst, w.resId(ICON_RES_ID), w.IMAGE_ICON, 16, 16, w.LR_DEFAULTCOLOR);
    wc.hIconSm = if (icon16 != null) @ptrCast(icon16) else wc.hIcon;
    wc.lpszClassName = w.wstr(CLASS_MAIN);
    _ = w.RegisterClassExW(&wc);

    const L = layout();
    var r = w.RECT{ .left = 0, .top = 0, .right = L.client_w, .bottom = L.client_h };
    const style: w.DWORD = w.WS.OVERLAPPED | w.WS.CAPTION | w.WS.SYSMENU | w.WS.MINIMIZEBOX;
    _ = w.AdjustWindowRect(&r, style, w.TRUE);
    hwnd_main = w.CreateWindowExW(0, w.wstr(CLASS_MAIN), w.wstr(APP_TITLE), style, 80, 60, r.right - r.left, r.bottom - r.top, null, buildMenu(), hinst, null);
    if (hwnd_main == null) return;
    loadScores();
    loadSoundPref();
    loadColorPref();
    checkMenu();

    if (uitestPath()) |p| {
        const code = runUiTest(p);
        w.ExitProcess(@intCast(code));
    }
    if (shotPath()) |p| {
        setupDemo();
        if (dumpPath()) |dp| dumpState(dp);
        resizeWindowForBoard();
        if (sheet_mode) {
            renderSheet(p);
        } else if (window_shot) captureWindow(p) else renderToFile(p);
        return;
    }

    _ = w.ShowWindow(hwnd_main, w.SW.SHOW);
    _ = w.UpdateWindow(hwnd_main);
    var msg: w.MSG = undefined;
    while (w.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }
}

/// 抓整窗（含标题栏、菜单栏），用 PrintWindow，不需要窗口可见/前台
fn captureWindow(path: []const u8) void {
    _ = w.ShowWindow(hwnd_main, 8); // SW_SHOWNA：显示但不激活，否则 PrintWindow 抓到全黑
    _ = w.UpdateWindow(hwnd_main);
    var r: w.RECT = undefined;
    _ = w.GetWindowRect(hwnd_main, &r);
    const cw = r.right - r.left;
    const ch = r.bottom - r.top;
    const dc = w.GetDC(null);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = cw;
    bi.bmiHeader.biHeight = -ch;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const bmp = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, dc);
    if (bmp == null or bits == null) return;
    const odc = w.CreateCompatibleDC(null);
    _ = w.SelectObject(odc, bmp);
    // flag=0：走 WM_PRINT/WM_PRINTCLIENT 这条老路，任何会话里都稳（flag=2 要 DWM 合成）
    _ = w.PrintWindow(hwnd_main, odc, 0);
    _ = saveBmp(path, @ptrCast(bits.?), cw, ch);
}

/// 素材对照表：把 24 个显示值贴图 + 旗帜/雷/踩中/标错 + LED + 人脸 全画出来核对映射。
/// 用 --sheet 输出，配合 bmp2png.js 看。
fn renderSheet(path: []const u8) void {
    const z: i32 = 3;
    const cellw = 16 * z + 6;
    const cellh = 16 * z + 22;
    const w0: i32 = 24 * cellw + 20;
    // 五行的高度全部按实际绘制位置算：早先这里写死了一个偏小的常量，
    // 结果第 4 行（LED）被裁掉一截、第 5 行（人脸）整行都画在画布外面。
    const y0: i32 = 6; // 数字行
    const y1: i32 = y0 + cellh; // 未翻开/旗/雷
    const y2: i32 = y1 + cellh; // 踩中/标错
    const y3: i32 = y2 + cellh; // LED
    const y4: i32 = y3 + 24 * z + 8; // 人脸
    const h0: i32 = y4 + 24 * z + 12;
    const dcs = w.GetDC(null);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w0;
    bi.bmiHeader.biHeight = -h0;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const bmp = w.CreateDIBSection(dcs, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, dcs);
    if (bmp == null or bits == null) return;
    const dc = w.CreateCompatibleDC(null);
    _ = w.SelectObject(dc, bmp);
    _ = w.SetStretchBltMode(dc, 3);
    fill(dc, 0, 0, w0, h0, C_BTNFACE);
    const font = w.GetStockObject(17);
    _ = w.SelectObject(dc, font);
    _ = w.SetBkMode(dc, w.TRANSPARENT);
    _ = w.SetTextColor(dc, C_BLACK);

    // 第一行：24 个显示值（按 D 升序），下方标 D 与文本
    var x: i32 = 10;
    for (g.ACHIEVABLE) |D| {
        const spr = A.num_by_D[D];
        blitSpriteSq(dc, spr, x, y0, 16 * z);
        var buf: [64]u16 = undefined;
        var txt: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&txt, "D={d}", .{D}) catch "?";
        _ = w.SetWindowTextW; // 不用窗口，直接 DrawTextW
        const ws = w.asciiToW(&buf, s);
        var r = w.RECT{ .left = x - 4, .top = y0 + 16 * z + 2, .right = x + 16 * z + 4, .bottom = y0 + 16 * z + 18 };
        _ = w.DrawTextW(dc, ws.ptr, -1, &r, w.DT.CENTER | w.DT.SINGLELINE);
        x += cellw;
    }

    // 第二行：未翻开 / 空白 / 四种旗 / 四种雷
    var x2: i32 = 10;
    const row2 = [_]struct { s: u16, label: []const u8 }{
        .{ .s = A.closed, .label = "closed" },
        .{ .s = A.blank, .label = "blank" },
        .{ .s = A.flag_1, .label = "+1" },
        .{ .s = A.flag_2, .label = "-1" },
        .{ .s = A.flag_3, .label = "+i" },
        .{ .s = A.flag_4, .label = "-i" },
        .{ .s = A.mine_1, .label = "m+1" },
        .{ .s = A.mine_2, .label = "m-1" },
        .{ .s = A.mine_3, .label = "m+i" },
        .{ .s = A.mine_4, .label = "m-i" },
    };
    for (row2) |it| {
        blitSpriteSq(dc, it.s, x2, y1, 16 * z);
        var buf: [32]u16 = undefined;
        const ws = w.asciiToW(&buf, it.label);
        var r = w.RECT{ .left = x2 - 4, .top = y1 + 16 * z + 2, .right = x2 + 16 * z + 4, .bottom = y1 + 16 * z + 18 };
        _ = w.DrawTextW(dc, ws.ptr, -1, &r, w.DT.CENTER | w.DT.SINGLELINE);
        x2 += cellw;
    }

    // 第三行：四种踩中 + 四种标错
    var x3: i32 = 10;
    const row3 = [_]struct { s: u16, label: []const u8 }{
        .{ .s = A.boom_1, .label = "boom+1" },
        .{ .s = A.boom_2, .label = "boom-1" },
        .{ .s = A.boom_3, .label = "boom+i" },
        .{ .s = A.boom_4, .label = "boom-i" },
        .{ .s = A.wrong_1, .label = "wrong+1" },
        .{ .s = A.wrong_2, .label = "wrong-1" },
        .{ .s = A.wrong_3, .label = "wrong+i" },
        .{ .s = A.wrong_4, .label = "wrong-i" },
    };
    for (row3) |it| {
        blitSpriteSq(dc, it.s, x3, y2, 16 * z);
        var buf: [32]u16 = undefined;
        const ws = w.asciiToW(&buf, it.label);
        var r = w.RECT{ .left = x3 - 4, .top = y2 + 16 * z + 2, .right = x3 + 16 * z + 4, .bottom = y2 + 16 * z + 18 };
        _ = w.DrawTextW(dc, ws.ptr, -1, &r, w.DT.CENTER | w.DT.SINGLELINE);
        x3 += cellw;
    }

    // 第四行：LED 0-9 / 空 / 负
    var x4: i32 = 10;
    var d: u16 = 0;
    while (d <= 9) : (d += 1) {
        blitSprite(dc, digitSprite(@intCast('0' + d)), x4, y3, 13 * z, 23 * z);
        x4 += 13 * z + 4;
    }
    blitSprite(dc, A.led_blank, x4, y3, 13 * z, 23 * z);
    x4 += 13 * z + 4;
    blitSprite(dc, A.led_minus, x4, y3, 13 * z, 23 * z);
    x4 += 13 * z + 4;
    blitSprite(dc, A.led_i, x4, y3, 13 * z, 23 * z);

    // 第五行：人脸
    var x5: i32 = 10;
    for ([_]u16{ A.face_normal, A.face_down, A.face_scan, A.face_dead, A.face_win }) |f| {
        blitSpriteSq(dc, f, x5, y4, 24 * z);
        x5 += 24 * z + 8;
    }
    // 顺手画四块真实的 LED 面板（实雷四格数字、虚雷三格数字 + 一格 i），验证对齐与那一格 i
    const sx = x5 + 20;
    const sw = 4 * 13 * z + 10;
    const sy = y4;
    // 正实雷：0083
    _ = drawLed(dc, sx, sy, 83, 4, z);
    // 负实雷：−014（负号占一格，仍是四格）
    _ = drawLed(dc, sx + sw, sy, -14, 4, z);
    // 正虚雷：007 + i
    var vx = sx + 2 * sw;
    _ = drawLed(dc, vx, sy, 7, 3, z);
    blitSprite(dc, A.led_i, vx + 3 * 13 * z, sy, 13 * z, 23 * z);
    // 负虚雷：−07 + i
    vx = sx + 3 * sw;
    _ = drawLed(dc, vx, sy, -7, 3, z);
    blitSprite(dc, A.led_i, vx + 3 * 13 * z, sy, 13 * z, 23 * z);

    _ = saveBmp(path, @ptrCast(bits.?), w0, h0);
    _ = w.DeleteObject(bmp);
    _ = w.DeleteDC(dc);
}

fn renderToFile(path: []const u8) void {
    const L = layout();
    const dc = w.GetDC(null);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = L.client_w;
    bi.bmiHeader.biHeight = -L.client_h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const bmp = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, dc);
    if (bmp == null or bits == null) return;
    const odc = w.CreateCompatibleDC(null);
    _ = w.SelectObject(odc, bmp);
    _ = w.SetStretchBltMode(odc, 3);
    paint(odc, L);
    _ = saveBmp(path, @ptrCast(bits.?), L.client_w, L.client_h);
}

fn dumpState(path: []const u8) void {
    const f = std.fs.cwd().createFile(path, .{}) catch return;
    defer f.close();
    var buf: [1024]u8 = undefined;
    var s = std.ArrayList(u8).init(std.heap.page_allocator);
    _ = &buf;
    s.writer().print("棋盘 {d}×{d} · 雷 {d} · 已翻开 {d} · 开局格 {d}\n", .{ game.w, game.h, game.mines, game.openedCount(), game.start_cell }) catch {};
    s.writer().print("type_total  = {d} {d} {d} {d}\n", .{ game.type_total[1], game.type_total[2], game.type_total[3], game.type_total[4] }) catch {};
    s.writer().print("flags_of    = {d} {d} {d} {d}\n", .{ game.flags_of[1], game.flags_of[2], game.flags_of[3], game.flags_of[4] }) catch {};
    s.writer().print("unmarked    = {d} {d} {d} {d}\n", .{ game.unmarked(1), game.unmarked(2), game.unmarked(3), game.unmarked(4) }) catch {};
    s.writer().print("counterValue= {d} {d} {d} {d}\n", .{ counterValue(1), counterValue(2), counterValue(3), counterValue(4) }) catch {};
    s.writer().print("panelCells  = {d} {d} {d} {d}   timer={d}\n", .{
        panelCells(false, counterShown(1)),                            panelCells(true, counterShown(2)),
        panelCells(true, counterShown(3)),                             panelCells(true, counterShown(4)),
        panelCells(false, if (game.started) timerSeconds() else null),
    }) catch {};
    s.writer().print("started={} over={} win={} elapsed_ms={d}\n", .{ game.started, game.over, game.win, game.elapsed_ms }) catch {};
    f.writeAll(s.items) catch {};
}

fn runSelftest(path: []const u8) u32 {
    var buf: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var out = std.ArrayList(u8).init(fba.allocator());
    const fails = selftest.run(&out);
    const file = std.fs.cwd().createFile(path, .{}) catch return 2;
    defer file.close();
    file.writeAll(out.items) catch return 2;
    return if (fails == 0) 0 else 1;
}

const selftest = @import("selftest.zig");
const uitest = @import("uitest.zig");

fn runUiTest(path: []const u8) u32 {
    const buf = std.heap.page_allocator;
    var out = std.ArrayList(u8).init(buf);
    defer out.deinit();
    const fails = uitest.run(&out);
    const file = std.fs.cwd().createFile(path, .{}) catch return 2;
    defer file.close();
    file.writeAll(out.items) catch return 2;
    return if (fails == 0) 0 else 1;
}

// ------------------------------------------------------------------ 给 uitest 用的钩子
pub const game_ptr = &game;
pub const test_IDM_BEGINNER = IDM_BEGINNER;
pub const test_IDM_INTERMEDIATE = IDM_INTERMEDIATE;
pub const test_IDM_EXPERT = IDM_EXPERT;
pub const test_IDM_ZOOM1 = IDM_ZOOM1;
pub const test_IDM_ZOOM2 = IDM_ZOOM2;
pub const test_IDM_ZOOM3 = IDM_ZOOM3;
pub const test_IDM_NEW = IDM_NEW;
pub const test_IDM_HELP_HOW = IDM_HELP_HOW;
pub const test_IDM_HELP_ABOUT = IDM_HELP_ABOUT;
pub const test_IDM_BEST = IDM_BEST;
/// 被删掉的那条菜单命令（显示值对照表）的 ID：菜单里绝不该再出现它
pub const test_IDM_HELP_TABLE_REMOVED: usize = 201;
pub const test_IDM_HYPER_BEGINNER = IDM_HYPER_BEGINNER;
pub const test_IDM_HYPER_INTERMEDIATE = IDM_HYPER_INTERMEDIATE;
pub const test_IDM_HYPER_EXPERT = IDM_HYPER_EXPERT;
pub const test_IDM_HYPER_CUSTOM = IDM_HYPER_CUSTOM;
pub const test_IDM_HYPER_BEST = IDM_HYPER_BEST;
pub const test_IDM_CUSTOM = IDM_CUSTOM;

/// 当前是不是闵可夫斯基模式
pub fn testIsHyper() bool {
    return hyper();
}
/// 当前档位（0/1/2 = 标准三档，-1 = 自定义）
pub fn testPresetIndex() i32 {
    return cur_preset;
}
/// 计雷器第四格（单位格）现在用哪张贴图：圆复数模式 led_i，闵可夫斯基模式 led_j
pub fn testUnitSprite() u16 {
    return if (hyper()) A.led_j else A.led_i;
}
pub const testLedISprite = A.led_i;
pub const testLedJSprite = A.led_j;
/// 闵可夫斯基模式的显示值 → 贴图（界面查的就是这张表）
pub fn testHnumSprite(D: i32) u16 {
    return A.hnum_by_D[@intCast(D + 64)];
}
/// 判定贴图查表：家族 × 模式 × 雷的类型（自检拿它核对"该贴哪一张"）
pub const SpriteFamily = enum { mine, flag, boom, wrong, right, rightflag, wrongflag };
pub fn testSprite(f: SpriteFamily, hyper_mode: bool, t: u8) u16 {
    const tbl = switch (f) {
        .mine => if (hyper_mode) A.hmine_T else A.mine_T,
        .flag => if (hyper_mode) A.hflag_T else A.flag_T,
        .boom => if (hyper_mode) A.hboom_T else A.boom_T,
        .wrong => if (hyper_mode) A.hwrong_T else A.wrong_T,
        .right => if (hyper_mode) A.hright_T else A.right_T,
        .rightflag => if (hyper_mode) A.hrightflag_T else A.rightflag_T,
        .wrongflag => if (hyper_mode) A.hwrongflag_T else A.wrongflag_T,
    };
    return tbl[@min(@as(usize, t), 4)];
}
pub const testWrongBlankSprite = A.wrongblank_sprite;
/// 用户在菜单里关掉声音了吗（和"非交互模式强制静音"是两回事）
pub fn testSoundOff() bool {
    return sound_off;
}
/// 现在按下这一下，声真的会响吗（两个静音来源任一为真就不响）
pub fn testAudible() bool {
    return audible();
}
/// 第 top 个下拉里第 idx 项（顶层项）有没有勾/圆点
pub fn testPopupItemChecked(top: i32, idx: i32) bool {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return false;
    const sub = w.GetSubMenu(bar, top);
    if (sub == null) return false;
    const st = w.GetMenuState(sub, @intCast(idx), w.MF.BYPOSITION);
    return (st & w.MF.CHECKED) != 0;
}
pub const test_IDM_SOUND = IDM_SOUND;
pub const test_IDM_COLOR = IDM_COLOR;
/// 用户在菜单里关掉颜色了吗
pub fn testColorOff() bool {
    return color_off;
}
/// 现在贴图用的是黑白那份图集吗（勾着"颜色"时应当是 false）
pub fn testActiveAtlasIsBw() bool {
    return activeAtlas() == atlas_bw_dc and atlas_bw_dc != null;
}
/// 黑白图集加载成功了吗（有素材且尺寸对）
pub fn testBwAtlasLoaded() bool {
    return atlas_bw_dc != null and atlas_bw_bmp != null;
}
/// 两套纪录键名确实是两套（防"加了模式却忘了换键"）
pub fn testScoreKeysDiffer() bool {
    for (0..3) |i| {
        if (SCORE_VALUES_HYPER[i][0] == SCORE_VALUES_CPLX[i][0]) return false;
    }
    return true;
}
/// 菜单结构：第 top 个下拉里第 sub_idx 个子菜单的第 j 项命令 ID（-1 = 分隔线/子菜单/不存在）
pub fn testSubItemId(top: i32, sub_idx: i32, j: i32) i32 {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return -1;
    const menu = w.GetSubMenu(bar, top);
    if (menu == null) return -1;
    const sub = w.GetSubMenu(menu, sub_idx);
    if (sub == null) return -1;
    return @bitCast(w.GetMenuItemID(sub, j));
}
/// 第 top 个下拉里第 sub_idx 个子菜单的第 j 项有没有圆点/对勾
pub fn testSubItemChecked(top: i32, sub_idx: i32, j: i32) bool {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return false;
    const menu = w.GetSubMenu(bar, top);
    if (menu == null) return false;
    const sub = w.GetSubMenu(menu, sub_idx);
    if (sub == null) return false;
    const st = w.GetMenuState(sub, @intCast(j), w.MF.BYPOSITION);
    return (st & w.MF.CHECKED) != 0;
}
/// 菜单里第 top 个下拉的第 idx 项命令 ID（-1 = 分隔线/子菜单）
pub fn testPopupItemId(top: i32, idx: i32) i32 {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return -1;
    const sub = w.GetSubMenu(bar, top);
    if (sub == null) return -1;
    return @bitCast(w.GetMenuItemID(sub, idx));
}

pub fn testWindow() w.HWND {
    return hwnd_main;
}
pub fn testCommand(id: usize) void {
    handleCommand(hwnd_main, id);
}
pub fn testZoom() i32 {
    return zoom;
}
pub fn testLayout() Layout {
    return layout();
}
pub fn testFaceDown() bool {
    return face_down;
}
/// 这次左键是不是"从人脸按下的"（决定松手时要不要重开）
pub fn testFaceArmed() bool {
    return face_armed;
}
/// 当前被按住的格子（-1 = 没有）与两张关键贴图，供自检核对"按下预览"
pub fn testPressCell() i32 {
    return press_cell;
}
/// 左右键同时按住 / 中键按住时记下的展开目标（-1 = 没有）
pub fn testChordCell() i32 {
    return chord_cell;
}
pub const testBlankSprite = A.blank;
pub const testClosedSprite = A.closed;
pub fn testFaceX() i32 {
    return faceLeft(layout());
}
pub fn testFaceY() i32 {
    return faceTop(layout());
}
/// 计雷器上实际显示的数（负实/负虚 是负的，虚雷另外挂 i 单位格）
pub fn testCounterValue(t: usize) i32 {
    return counterValue(t);
}
/// 计雷器里最宽的一条占几格（常态是四格：实雷四格数字、虚雷三格数字 + 一格 i）
pub fn testCounterCells() i32 {
    var widest: i32 = 0;
    for (1..5) |t| widest = @max(widest, panelCells(counterImag(t), counterShown(t)));
    return widest;
}
/// 某一条计雷器的数值区画几格**数字**（实雷四格、虚雷三格；没开局时整条画空格子）
pub fn testCounterValueCells(t: usize) i32 {
    return panelValueDigits(counterImag(t), counterShown(t));
}
/// 计时器面板占几格（和计雷器同样四格）
pub fn testTimerCells() i32 {
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    return panelCells(false, tv);
}
/// 计时器画几格数字（四格）
pub fn testTimerValueCells() i32 {
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    return panelValueDigits(false, tv);
}
/// 计时器面板宽度（版式自检用）
pub fn testTimerWidth() i32 {
    return timerWidth(zoom);
}
pub fn testCounterImag(t: usize) bool {
    return counterImag(t);
}
/// 计雷器那一列的整体宽度（版式自检拿它核对没有溢进人脸/表头外）
pub fn testCountersWidth() i32 {
    return countersWidth(layout());
}
// ---- 音效的测试钩子（消息级自检里出不了声，验的是"什么时候该播哪一段"）----
/// 某个槽位播过几次；下标 0..3 = 四种踩雷（与 Game.mine 的 1..4 对应），4 = win，5 = tick
pub fn testSoundCount(i: usize) u32 {
    if (i >= snd.count) return 0;
    return sound_log[i];
}
/// 第 i 段内嵌音效的字节数（确认真的编进去了、不是空壳）
pub fn testSoundBytes(i: usize) usize {
    return snd.wav(i).len;
}
/// 第 i 段开头是不是标准 wav 头（RIFF / WAVE）
pub fn testSoundIsRiff(i: usize) bool {
    const b = snd.wav(i);
    return b.len >= 44 and std.mem.eql(u8, b[0..4], "RIFF") and std.mem.eql(u8, b[8..12], "WAVE");
}
/// 两段音效的字节是否完全一样（用来确认四种踩雷音确实各不相同）
pub fn testSoundsEqual(i: usize, j: usize) bool {
    const a = snd.wav(i);
    const b = snd.wav(j);
    if (a.len != b.len) return false;
    return std.mem.eql(u8, a, b);
}
/// 音效计数清零（自检里按组隔离，免得上一组的声音串到下一组）
pub fn testSoundReset() void {
    sound_log = [_]u32{0} ** snd.count;
    over_sound_done = false;
    tick_second = -1;
}
/// 手动走一次"计时器到点"的处理：消息级自检没有真消息循环，靠这个驱动每秒一下的 tick。
/// 它和 WM_TIMER 里做的是同一件事——先从时钟刷新 elapsed_ms，再判该不该响；
/// 少了刷新的那一步，`testBackdate` 挪过的时间就看不见（秒数一直是 0，tick 永远不播）。
pub fn testTimerTick() void {
    if (game.started and !game.over) {
        game.elapsed_ms = w.GetTickCount() -% game.t0;
    }
    maybePlayTick();
}
/// 当前是不是静音状态（自检跑在非交互模式下，应当是true；真人双击运行时为 false）
pub fn testSoundMuted() bool {
    return sound_muted;
}
/// 命令行里带了几个开关（自检自己就带了 --uitest，所以这里必然 > 0）
pub fn testArgCount() usize {
    return arg_count;
}
pub fn testMouse(msg: w.MouseMsg, x: i32, y: i32) void {
    switch (msg) {
        .left_down, .left_dblclk => _ = onLeftDown(hwnd_main, x, y),
        .left_up => _ = onLeftUp(hwnd_main, x, y),
        .right_down, .right_dblclk => _ = onRightDown(hwnd_main, x, y),
        .right_up => _ = onRightUp(hwnd_main, x, y),
        .middle_down => _ = onMiddleDown(hwnd_main, x, y),
        .middle_up => _ = onMiddleUp(hwnd_main, x, y),
        .move => _ = onMouseMove(hwnd_main, x, y),
    }
}
/// 菜单里到底挂了哪些命令：遍历菜单栏的每个下拉，收集所有命令 ID。
/// 不给真实点击菜单的机会（那会进模态循环），所以直接查系统里的菜单句柄。
/// 菜单里到底挂了哪些命令：递归遍历整棵菜单树（难度项现在在"模式 → 难度"里，是第三层）。
/// 不给真实点击菜单的机会（那会进模态循环），所以直接查系统里的菜单句柄。
pub fn testMenuHasId(id: usize) bool {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return false;
    return menuTreeHasId(bar, id, 0);
}

fn menuTreeHasId(menu: w.HMENU, id: usize, depth: u32) bool {
    if (depth > 4) return false;
    const items = w.GetMenuItemCount(menu);
    var i: i32 = 0;
    while (i < items) : (i += 1) {
        const sub = w.GetSubMenu(menu, i);
        if (sub != null) {
            if (menuTreeHasId(sub, id, depth + 1)) return true;
            continue;
        }
        if (w.GetMenuItemID(menu, i) == @as(u32, @intCast(id))) return true;
    }
    return false;
}
/// 第 top 个下拉里的项目数（含分隔线）。帮助菜单是第 2 个（索引 1）。
pub fn testPopupCount(top: i32) i32 {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return -1;
    const sub = w.GetSubMenu(bar, top);
    if (sub == null) return -1;
    return w.GetMenuItemCount(sub);
}
/// 窗口标题（自检核对用户看得见的那串字）
pub fn testWindowTitle() []const u16 {
    const hwnd = hwnd_main orelse return &[_]u16{};
    const n = w.GetWindowTextW(hwnd, &title_buf, title_buf.len);
    if (n <= 0) return &[_]u16{};
    return title_buf[0..@intCast(n)];
}
var title_buf: [128]u16 = undefined;
/// 编译期那份标题常量，供自检比对（别在自检里写死字符串，改标题时自检要跟着报）
pub const testAppTitle: [*:0]const u16 = w.wstr(APP_TITLE);
/// 版本号（关于对话框与自检报告抬头都用它）
pub const testAppVersion = APP_VERSION;
/// 关于对话框的完整正文（自检核对里面有没有版本号）
pub const testAboutText: [*:0]const u16 = w.wstr(ABOUT_TEXT);
/// 「玩法与操作」的完整正文（自检核对旗帜顺序那几行用的是不是"旗"的名字）
pub const testHelpText: [*:0]const u16 = w.wstr(HELP_TEXT);
/// 图标资源在不在：窗口图标、"关于"弹窗都靠它，缺失说明 .rsrc 没注入或者写坏了。
/// 两档都验：LoadIconW 走默认尺寸，LoadImageW 点名 16×16。
pub fn testIconResourceOk() bool {
    const hinst = w.GetModuleHandleW(null);
    if (w.LoadIconW(hinst, w.resId(ICON_RES_ID)) == null) return false;
    return w.LoadImageW(hinst, w.resId(ICON_RES_ID), w.IMAGE_ICON, 16, 16, w.LR_DEFAULTCOLOR) != null;
}
pub fn testKey(vk: w.WPARAM) w.LRESULT {
    return onKeyDown(vk);
}
// ---- 对话框与渲染的测试钩子 ----
pub fn testOpenDialog() bool {
    return createCustomWindow();
}
pub fn testCloseDialog() void {
    closeCustomWindow();
}
pub fn testSetEdit(idx: usize, v: i32) void {
    setEditInt(edit_handles[idx], v);
}
pub fn testApplyDialog() bool {
    dlgApply();
    if (dialog_done and !dialog_cancel) {
        applyCustomFromDialog();
        return true;
    }
    return false;
}
pub fn testDialogErrName() []const u8 {
    return switch (dlg_state.err) {
        .none => "none",
        .height => "height",
        .width => "width",
        .sum_zero => "sum_zero",
        .sum_big => "sum_big",
    };
}
pub fn testDialogDone() bool {
    return dialog_done;
}
// ---- 对话框外观／文案的测试钩子 ----
var dlg_texts_buf: [1024]u16 = undefined;
var dlg_texts_len: usize = 0;
fn collectDlgText(h: w.HWND, lp: w.LPARAM) callconv(.c) w.BOOL {
    _ = lp;
    if (dlg_texts_len + 130 >= dlg_texts_buf.len) return w.TRUE;
    const n = w.GetWindowTextW(h, dlg_texts_buf[dlg_texts_len..].ptr, 128);
    if (n > 0) {
        dlg_texts_len += @intCast(n);
        dlg_texts_buf[dlg_texts_len] = '|'; // 分隔符，整串搜索时不会跨控件粘连
        dlg_texts_len += 1;
    }
    return w.TRUE;
}
/// 对话框里所有子控件的文字拼成一串（自检用来核对标签文案）
pub fn testDialogTexts() []const u16 {
    dlg_texts_len = 0;
    if (dialog_hwnd != null) _ = w.EnumChildWindows(dialog_hwnd, collectDlgText, 0);
    return dlg_texts_buf[0..dlg_texts_len];
}
/// 静态标签拿到的背景刷子是不是那块白刷子（整个对话框白底）
pub fn testDialogBgBrushIsWhite() bool {
    if (dialog_hwnd == null or dlg_bg_brush == null) return false;
    const dc = w.GetDC(dialog_hwnd);
    defer _ = w.ReleaseDC(dialog_hwnd, dc);
    const r = dlgWndProc(dialog_hwnd, w.WM.CTLCOLORSTATIC, @intFromPtr(dc), @as(w.LPARAM, @intCast(@intFromPtr(dlg_err_hwnd))));
    return r == @as(w.LRESULT, @bitCast(@intFromPtr(dlg_bg_brush)));
}
pub fn testSplitClick() void {
    // 走对话框里那条真实路径（点"按合计均分"按钮）
    _ = dlgWndProc(dialog_hwnd, w.WM.COMMAND, @as(w.WPARAM, @intCast(IDC_BTN_SPLIT)), 0);
}
pub fn testEditValue(idx: usize) i32 {
    return getEditInt(edit_handles[idx], -1);
}
pub fn testFaceSpriteIsWin() bool {
    return faceSprite() == A.face_win;
}
/// 按住人脸时用的是不是"按下"那张（换素材后至少要确认五张脸都被认到）
pub fn testFaceSpriteIsDown() bool {
    return faceSprite() == A.face_down;
}
/// 翻格/插旗那一瞬间是不是在放「脸扫雷」
pub fn testFaceSpriteIsScan() bool {
    return faceSprite() == A.face_scan;
}
/// 手动把「脸扫雷」的闪动结束掉，免得自检里要真等 200ms
pub fn testFaceFlashExpire() void {
    face_flash_until = 0;
}
pub fn testFaceSpriteIsDead() bool {
    return faceSprite() == A.face_dead;
}
pub fn testCellSprite(cell: usize) u16 {
    return cellSprite(cell);
}
// ---- 最高分纪录的测试钩子 ----
pub fn testScoresStopPersist() void {
    scores_persist = false;
    scores_quiet = true;
}
pub fn testSetScores(v0: i32, v1: i32, v2: i32) void {
    best_scores = .{ v0, v1, v2 };
}
pub fn testGetScore(i: usize) i32 {
    return best_scores[i];
}
var scores_text_buf: [512]u16 = undefined;
/// 把「最高分纪录」对话框的正文取出来给自检核对（UTF-16 码元，不含结尾 0）
pub fn testScoresText() []const u16 {
    const n = buildScoresText(&scores_text_buf, best_scores);
    return scores_text_buf[0..n];
}
/// 把开局时刻往前挪 ms 毫秒，用来在自检里模拟"用了多久"
pub fn testBackdate(ms: u32) void {
    game.t0 = nowMs() -% ms;
}
