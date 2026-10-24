// GTK3 + cairo 后端：给 ui.zig 提供与 ui_win32.zig 完全同名的符号面。
//
// 内核（像素缓冲 DIB / 内存 DC / 菜单镜像 / 逻辑窗口 / 计时器）是纯 Zig、零外部依赖，
// 从而 --selftest 与 --uitest 可以直接在 Linux 原生跑通，验证全部游戏逻辑与菜单/版式。
// 交互式窗口（GTK3 GtkDrawingArea + cairo 绘制 + 信号桥到 on* 处理器）挂在同一边界上，
// 只在真人双击运行时才走到 gtk_main，按步骤接入。
const std = @import("std");

// ------------------------------------------------------------------ 句柄与标量类型
// 与 ui_win32.zig 一致：句柄全是 ?*anyopaque，调用点类型保持不变。
pub const HINSTANCE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const HICON = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HBITMAP = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HGDIOBJ = ?*anyopaque;
pub const HFONT = ?*anyopaque;
pub const HMODULE = ?*anyopaque;
pub const HANDLE = ?*anyopaque;

pub const UINT = u32;
pub const DWORD = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const BOOL = i32;
pub const ATOM = u16;
pub const WORD = u16;
pub const BYTE = u8;
pub const LPCWSTR = ?[*:0]const u16;
pub const LPWSTR = [*]u16;

pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub const POINT = extern struct { x: i32, y: i32 };
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    pub fn w(self: RECT) i32 {
        return self.right - self.left;
    }
    pub fn h(self: RECT) i32 {
        return self.bottom - self.top;
    }
};
pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};
pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;
pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: LPCWSTR,
    lpszClassName: LPCWSTR,
    hIconSm: HICON,
};
pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};
pub const RGBQUAD = extern struct { rgbBlue: BYTE, rgbGreen: BYTE, rgbRed: BYTE, rgbReserved: BYTE };
pub const ICONINFO = extern struct {
    fIcon: BOOL,
    xHotspot: DWORD,
    yHotspot: DWORD,
    hbmMask: HBITMAP,
    hbmColor: HBITMAP,
};
pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD,
    biWidth: i32,
    biHeight: i32,
    biPlanes: WORD,
    biBitCount: WORD,
    biCompression: DWORD,
    biSizeImage: DWORD,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: DWORD,
    biClrImportant: DWORD,
};
pub const BITMAPINFO = extern struct { bmiHeader: BITMAPINFOHEADER, bmiColors: [1]RGBQUAD };

// ------------------------------------------------------------------ 字符串助手
/// 编译期 UTF-8 → UTF-16（含 BMP 三字节与超过 BMP 的代理对）
pub fn wstr(comptime s: []const u8) *const [wlen(s):0]u16 {
    return comptime blk: {
        @setEvalBranchQuota(200000);
        const N = wlen(s);
        var buf: [N:0]u16 = [_:0]u16{0} ** N;
        var i: usize = 0;
        var o: usize = 0;
        while (i < s.len) {
            const c = s[i];
            if (c < 0x80) {
                buf[o] = c;
                i += 1;
            } else if (c & 0xE0 == 0xC0) {
                buf[o] = (@as(u16, c & 0x1F) << 6) | @as(u16, s[i + 1] & 0x3F);
                i += 2;
            } else if (c & 0xF0 == 0xE0) {
                buf[o] = (@as(u16, c & 0x0F) << 12) | (@as(u16, s[i + 1] & 0x3F) << 6) | @as(u16, s[i + 2] & 0x3F);
                i += 3;
            } else {
                // 4 字节：转成代理对
                const cp: u21 = (@as(u21, c & 0x07) << 18) | (@as(u21, s[i + 1] & 0x3F) << 12) |
                    (@as(u21, s[i + 2] & 0x3F) << 6) | @as(u21, s[i + 3] & 0x3F);
                const v = cp - 0x10000;
                buf[o] = @intCast(0xD800 + (v >> 10));
                o += 1;
                buf[o] = @intCast(0xDC00 + (v & 0x3FF));
                i += 4;
            }
            o += 1;
        }
        const frozen = buf;
        break :blk &frozen;
    };
}
fn wlen(comptime s: []const u8) usize {
    var i: usize = 0;
    var n: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c < 0x80) {
            i += 1;
        } else if (c & 0xE0 == 0xC0) {
            i += 2;
        } else if (c & 0xF0 == 0xE0) {
            i += 3;
        } else {
            i += 4;
            n += 1;
        }
        n += 1;
    }
    return n;
}

/// 运行时 ascii → utf16
pub fn asciiToW(buf: []u16, s: []const u8) [:0]u16 {
    const n = @min(s.len, buf.len - 1);
    for (s[0..n], 0..) |c, i| buf[i] = c;
    buf[n] = 0;
    return buf[0..n :0];
}

/// 运行时 UTF-8 → UTF-16（含 BMP 三字节与超过 BMP 的代理对），写入调用方缓冲区并补 0 结尾。
pub fn utf8ToW(buf: []u16, s: []const u8) [:0]u16 {
    var i: usize = 0;
    var o: usize = 0;
    while (i < s.len and o < buf.len - 1) {
        const c = s[i];
        if (c < 0x80) {
            buf[o] = c;
            i += 1;
        } else if (c & 0xE0 == 0xC0) {
            if (i + 1 >= s.len) break;
            buf[o] = (@as(u16, c & 0x1F) << 6) | @as(u16, s[i + 1] & 0x3F);
            i += 2;
        } else if (c & 0xF0 == 0xE0) {
            if (i + 2 >= s.len) break;
            buf[o] = (@as(u16, c & 0x0F) << 12) | (@as(u16, s[i + 1] & 0x3F) << 6) | @as(u16, s[i + 2] & 0x3F);
            i += 3;
        } else {
            if (i + 3 >= s.len) break;
            const cp: u21 = (@as(u21, c & 0x07) << 18) | (@as(u21, s[i + 1] & 0x3F) << 12) |
                (@as(u21, s[i + 2] & 0x3F) << 6) | @as(u21, s[i + 3] & 0x3F);
            const v = cp - 0x10000;
            buf[o] = @intCast(0xD800 + (v >> 10));
            o += 1;
            if (o >= buf.len - 1) break;
            buf[o] = @intCast(0xDC00 + (v & 0x3FF));
            i += 4;
        }
        o += 1;
    }
    buf[o] = 0;
    return buf[0..o :0];
}

pub fn u32ToW(buf: []u16, v: u32) [:0]u16 {
    var tmp: [12]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return buf[0..0 :0];
    return asciiToW(buf, s);
}

/// 运行时 UTF-16 → UTF-8（后端把宽字符串转给 GTK/pango 用）
pub fn wideToUtf8(buf: []u8, s: []const u16) []const u8 {
    const n = std.unicode.utf16LeToUtf8(buf, s) catch return "";
    return buf[0..n];
}

/// MAKEINTRESOURCE：整数资源 ID 当指针传
pub fn resId(id: usize) ?*const anyopaque {
    return @ptrFromInt(id);
}

pub inline fn loWord(v: LPARAM) i32 {
    return @as(i32, @intCast(@as(u16, @truncate(@as(usize, @bitCast(v))))));
}
pub inline fn hiWord(v: LPARAM) i32 {
    const u: usize = @bitCast(v);
    return @as(i32, @intCast(@as(u16, @truncate(u >> 16))));
}
pub inline fn makeLParam(lo: i32, hi: i32) LPARAM {
    const l: usize = @as(u16, @intCast(@as(u32, @bitCast(lo)) & 0xFFFF));
    const h: usize = @as(u16, @intCast(@as(u32, @bitCast(hi)) & 0xFFFF));
    return @bitCast(l | (h << 16));
}
pub inline fn rgb(r: u8, g: u8, b: u8) DWORD {
    return @as(DWORD, r) | (@as(DWORD, g) << 8) | (@as(DWORD, b) << 16);
}

// ------------------------------------------------------------------ 常量
/// MessageBoxIndirectW 的参数包
pub const MSGBOXPARAMS = extern struct {
    cbSize: UINT,
    hwndOwner: HWND,
    hInstance: HINSTANCE,
    lpszText: LPCWSTR,
    lpszCaption: LPCWSTR,
    dwStyle: DWORD,
    lpszIcon: ?*const anyopaque,
    dwContextHelpId: usize,
    lpfnMsgBoxCallback: ?*const fn (usize) callconv(.c) void,
    dwLanguageId: DWORD,
};

pub const WNDCLASS_STYLES = struct {
    pub const CS_DBLCLKS: UINT = 0x0008;
    pub const CS_HREDRAW: UINT = 0x0002;
    pub const CS_VREDRAW: UINT = 0x0001;
};
pub const WS = struct {
    pub const OVERLAPPED: UINT = 0x00000000;
    pub const POPUP: UINT = 0x80000000;
    pub const CAPTION: UINT = 0x00C00000;
    pub const SYSMENU: UINT = 0x00080000;
    pub const MINIMIZEBOX: UINT = 0x00020000;
    pub const CHILD: UINT = 0x40000000;
    pub const VISIBLE: UINT = 0x10000000;
    pub const BORDER: UINT = 0x00800000;
    pub const DLGFRAME: UINT = 0x00400000;
    pub const TABSTOP: UINT = 0x00010000;
    pub const GROUP: UINT = 0x00020000;
    pub const EX_CLIENTEDGE: UINT = 0x00000200;
    pub const EX_APPWINDOW: UINT = 0x00040000;
};
pub const SW = struct {
    pub const SHOW: i32 = 5;
    pub const HIDE: i32 = 0;
};
pub const WM = struct {
    pub const CREATE: UINT = 0x0001;
    pub const DESTROY: UINT = 0x0002;
    pub const SIZE: UINT = 0x0005;
    pub const SETFOCUS: UINT = 0x0007;
    pub const KILLFOCUS: UINT = 0x0008;
    pub const PAINT: UINT = 0x000F;
    pub const CLOSE: UINT = 0x0010;
    pub const ERASEBKGND: UINT = 0x0014;
    pub const CTLCOLOREDIT: UINT = 0x0133;
    pub const CTLCOLORBTN: UINT = 0x0135;
    pub const CTLCOLORSTATIC: UINT = 0x0138;
    pub const SETCURSOR: UINT = 0x0020;
    pub const GETMINMAXINFO: UINT = 0x0024;
    pub const TIMER: UINT = 0x0113;
    pub const KEYDOWN: UINT = 0x0100;
    pub const COMMAND: UINT = 0x0111;
    pub const SYSCOMMAND: UINT = 0x0112;
    pub const INITMENU: UINT = 0x0116;
    pub const MOUSEMOVE: UINT = 0x0200;
    pub const LBUTTONDOWN: UINT = 0x0201;
    pub const LBUTTONUP: UINT = 0x0202;
    pub const LBUTTONDBLCLK: UINT = 0x0203;
    pub const RBUTTONDOWN: UINT = 0x0204;
    pub const RBUTTONUP: UINT = 0x0205;
    pub const RBUTTONDBLCLK: UINT = 0x0206;
    pub const MBUTTONDOWN: UINT = 0x0207;
    pub const MBUTTONUP: UINT = 0x0208;
    pub const MBUTTONDBLCLK: UINT = 0x0209;
    pub const CAPTURECHANGED: UINT = 0x0215;
    pub const ENTERSIZEMOVE: UINT = 0x0231;
    pub const EXITSIZEMOVE: UINT = 0x0232;
    pub const CONTEXTMENU: UINT = 0x007B;
    pub const PRINT: UINT = 0x0317;
    pub const PRINTCLIENT: UINT = 0x0318;
};
pub const MF = struct {
    pub const STRING: UINT = 0x00000000;
    pub const SEPARATOR: UINT = 0x00000800;
    pub const CHECKED: UINT = 0x00000008;
    pub const RADIOCHECK: UINT = 0x00000200;
    pub const GRAYED: UINT = 0x00000003;
    pub const ENABLED: UINT = 0x00000000;
    pub const POPUP: UINT = 0x00000010;
    pub const BYCOMMAND: UINT = 0x00000000;
    pub const BYPOSITION: UINT = 0x00000400;
};
pub const IDC = struct {
    pub const ARROW: usize = 32512;
    pub const HAND: usize = 32649;
};
pub const COLOR = struct {
    pub const BTNFACE: i32 = 15;
    pub const WINDOW: i32 = 5;
    pub const BLACK: i32 = 0;
    pub const WHITE: i32 = 16777215;
};
pub const SRCCOPY: DWORD = 0x00CC0020;
pub const PATCOPY: DWORD = 0x00F00021;
pub const BLACKNESS: DWORD = 0x00000042;
pub const WHITENESS: DWORD = 0x00FF0062;
pub const BI_RGB: DWORD = 0;
pub const DIB_RGB_COLORS: UINT = 0;
pub const TRANSPARENT: i32 = 1;
pub const NULL_BRUSH: i32 = 5;
pub const DT = struct {
    pub const LEFT: UINT = 0x00000000;
    pub const CENTER: UINT = 0x00000001;
    pub const RIGHT: UINT = 0x00000002;
    pub const VCENTER: UINT = 0x00000004;
    pub const SINGLELINE: UINT = 0x00000020;
    pub const WORDBREAK: UINT = 0x00000010;
};
pub const MB = struct {
    pub const OK: UINT = 0x00000000;
    pub const ICONINFORMATION: UINT = 0x00000040;
    pub const ICONWARNING: UINT = 0x00000030;
    pub const USERICON: UINT = 0x00000080;
    pub const SETFOREGROUND: UINT = 0x00010000;
    pub const TOPMOST: UINT = 0x00040000;
};
pub const IMAGE_ICON: UINT = 1;
pub const LR_DEFAULTCOLOR: UINT = 0x00000000;

pub const SND_ASYNC: DWORD = 0x0001;
pub const SND_NODEFAULT: DWORD = 0x0002;
pub const SND_MEMORY: DWORD = 0x0004;

pub const SM = struct {
    pub const CXSCREEN: i32 = 0;
    pub const CYSCREEN: i32 = 1;
    pub const CXFRAME: i32 = 32;
    pub const CYFRAME: i32 = 33;
    pub const CYCAPTION: i32 = 4;
    pub const CXMENU: i32 = 54;
    pub const CYSIZEFRAME: i32 = 32;
};

pub const C_BTNFACE = rgb(0xC0, 0xC0, 0xC0);
pub const C_BTNSHADOW = rgb(0x80, 0x80, 0x80);
pub const C_BTNHIGHLIGHT = rgb(0xDF, 0xDF, 0xDF);
pub const C_BTNDKSHADOW = rgb(0x00, 0x00, 0x00);
pub const C_BTNLIGHT = rgb(0xFF, 0xFF, 0xFF);

// ---- 持久化（HKCU 的等价物：Linux 下用文件实现，见底部）----
pub const HKEY_CURRENT_USER: usize = 0x80000001;
pub const KEY_READ: u32 = 0x20019;
pub const KEY_WRITE: u32 = 0x20006;
pub const REG_DWORD: u32 = 4;
pub const REG_OPTION_NON_VOLATILE: u32 = 0;
pub const ERROR_SUCCESS: i32 = 0;

// ------------------------------------------------------------------ 内部运行时结构
/// 所有 GDI 对象共用一个头部，便于从 ?*anyopaque 安全判型
const ObjKind = enum(u8) { bitmap, brush, font, pen, stock };
const GdiObj = struct { kind: ObjKind };

/// 32bpp 自顶向下 BGRA 位图：与 Win32 DIB 逐字节一致（SRCCOPY 就是 4 字节拷贝）
const Bitmap = struct {
    kind: ObjKind = .bitmap,
    w: i32,
    h: i32,
    stride: usize, // = w*4
    pixels: [*]u8,
};

const Brush = struct {
    kind: ObjKind = .brush,
    color: DWORD,
};

/// 设备上下文：内存 DC 选一张位图；窗口 DC 指向窗口（交互式绘制用，暂未接入 cairo）
const Dc = struct {
    kind: ObjKind = .stock,
    bmp: ?*Bitmap = null,
    win: ?*Window = null,
    stretch_mode: i32 = 3, // COLORONCOLOR=3（最近邻），与 Win32 SetStretchBltMode(3) 一致
};

/// 菜单镜像：按位置可查命令 ID / 复选态 / 子菜单
const MenuEntry = struct {
    id: i32 = -1, // -1 = 分隔线 / 子菜单
    sub: ?*Menu = null,
    checked: bool = false,
};
const MENU_MAX = 24;
const Menu = struct {
    entries: [MENU_MAX]MenuEntry = undefined,
    count: usize = 0,
};

/// 逻辑窗口：客户区尺寸 + 菜单栏/控件 ID + 文本 + 父子关系
const MAX_TEXT = 128;
const MAX_CHILD = 28;
const Window = struct {
    rect: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    menu: ?*Menu = null,
    id: i32 = -1, // 子控件 ID（对话框用）；-1 = 无
    parent: ?*Window = null,
    text: [MAX_TEXT]u16 = [_]u16{0} ** MAX_TEXT,
    text_len: usize = 0,
    children: [MAX_CHILD]?*Window = [_]?*Window{null} ** MAX_CHILD,
    child_count: usize = 0,
};

fn copyWstr(dst: []u16, src: LPCWSTR) usize {
    const s = src orelse return 0;
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        const c = s[i];
        if (c == 0) break;
        dst[i] = c;
    }
    return i;
}

const page = std.heap.page_allocator;

fn newMenu() ?*Menu {
    const m = page.create(Menu) catch return null;
    m.* = .{};
    return m;
}

/// ?*anyopaque → 具体句柄类型（先判空再 @alignCast，避免可选指针直接 cast 的编译错）
inline fn asWindow(h: HWND) ?*Window {
    const hp = h orelse return null;
    return @ptrCast(@alignCast(hp));
}
inline fn asMenu(h: HMENU) ?*Menu {
    const hp = h orelse return null;
    return @ptrCast(@alignCast(hp));
}
inline fn asDc(dc: HDC) ?*Dc {
    const dp = dc orelse return null;
    return @ptrCast(@alignCast(dp));
}
inline fn asGdiObj(o: HGDIOBJ) ?*GdiObj {
    if (o == null or isStock(o)) return null;
    const op = o.?;
    return @ptrCast(@alignCast(op));
}
inline fn asBitmap(o: HGDIOBJ) ?*Bitmap {
    const g = asGdiObj(o) orelse return null;
    if (g.kind != .bitmap) return null;
    return @ptrCast(@alignCast(g));
}

// ------------------------------------------------------------------ 位图 / 设备上下文
pub fn CreateDIBSection(dc: HDC, bi: *const BITMAPINFO, usage: UINT, bits: *?*anyopaque, hsec: HANDLE, off: DWORD) HBITMAP {
    _ = dc;
    _ = usage;
    _ = hsec;
    _ = off;
    const w = bi.bmiHeader.biWidth;
    const h = bi.bmiHeader.biHeight;
    const pw: usize = @intCast(@abs(w));
    const ph: usize = @intCast(@abs(h));
    if (pw == 0 or ph == 0) return null;
    const n = pw * ph * 4;
    const mem = page.alloc(u8, n) catch return null;
    const bmp = page.create(Bitmap) catch return null;
    bmp.* = .{ .w = @intCast(pw), .h = @intCast(ph), .stride = pw * 4, .pixels = mem.ptr };
    bits.* = @ptrCast(mem.ptr);
    return @ptrCast(bmp);
}

pub fn CreateCompatibleDC(dc: HDC) HDC {
    _ = dc;
    const d = page.create(Dc) catch return null;
    d.* = .{ .kind = .stock, .bmp = null, .win = null };
    return @ptrCast(d);
}

pub fn CreateCompatibleBitmap(dc: HDC, w: i32, h: i32) HBITMAP {
    _ = dc;
    if (w <= 0 or h <= 0) return null;
    var bi = BITMAPINFO{
        .bmiHeader = .{
            .biSize = @sizeOf(BITMAPINFOHEADER),
            .biWidth = w,
            .biHeight = -h, // 自顶向下
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = BI_RGB,
            .biSizeImage = 0,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        },
        .bmiColors = undefined,
    };
    var bits: ?*anyopaque = null;
    return CreateDIBSection(null, &bi, DIB_RGB_COLORS, &bits, null, 0);
}

inline fn isStock(p: HGDIOBJ) bool {
    return @intFromPtr(p) < 0x10000;
}

pub fn SelectObject(dc: HDC, obj: HGDIOBJ) HGDIOBJ {
    const d = asDc(dc) orelse return null;
    if (obj == null or isStock(obj)) {
        const old = d.bmp;
        d.bmp = null;
        return @ptrCast(old);
    }
    if (asGdiObj(obj)) |o| {
        if (o.kind == .bitmap) {
            const old = d.bmp;
            d.bmp = asBitmap(obj);
            return @ptrCast(old);
        }
    }
    return null; // 笔 / 刷 / 字体不选进 DC（本程序用不到）
}

pub fn DeleteObject(obj: HGDIOBJ) BOOL {
    if (asBitmap(obj)) |b| {
        page.free(b.pixels[0 .. b.stride * @as(usize, @intCast(b.h))]);
        page.destroy(b);
        return TRUE;
    }
    if (asGdiObj(obj)) |o| {
        switch (o.kind) {
            .brush => page.destroy(@as(*Brush, @ptrCast(@alignCast(o)))),
            .font, .pen, .stock => page.destroy(o),
            .bitmap => {},
        }
    }
    return TRUE;
}

pub fn DeleteDC(dc: HDC) BOOL {
    const d = asDc(dc) orelse return FALSE;
    page.destroy(d);
    return TRUE;
}

/// 屏幕 DC（GetDC(null)）：一个不挂位图的共享 DC
var screen_dc: Dc = .{ .kind = .stock, .bmp = null, .win = null };

pub fn GetDC(hwnd: HWND) HDC {
    if (hwnd == null) return @ptrCast(&screen_dc);
    const d = page.create(Dc) catch return @ptrCast(&screen_dc);
    d.* = .{ .kind = .stock, .bmp = null, .win = asWindow(hwnd) };
    return @ptrCast(d);
}

pub fn ReleaseDC(hwnd: HWND, dc: HDC) i32 {
    _ = hwnd;
    const d = asDc(dc) orelse return 1;
    if (d != &screen_dc) page.destroy(d);
    return 1;
}

pub fn CreateSolidBrush(color: DWORD) HBRUSH {
    const b = page.create(Brush) catch return null;
    b.* = .{ .kind = .brush, .color = color };
    return @ptrCast(b);
}

pub fn GetStockObject(i: i32) HGDIOBJ {
    return @ptrFromInt(@as(usize, @intCast(i + 1)));
}

/// 经典填充：把 DC 上选区填成实色（写 BGRA，alpha=255，保证最终上屏不透明）
pub fn FillRect(dc: HDC, r: *const RECT, br: HBRUSH) i32 {
    const d: *Dc = @ptrCast(@alignCast(dc orelse return 0));
    const bmp = d.bmp orelse return 0;
    const br_obj: *Brush = @ptrCast(@alignCast(br orelse return 0));
    const c = br_obj.color;
    const b = @as(u8, @intCast(c & 0xFF));
    const g = @as(u8, @intCast((c >> 8) & 0xFF));
    const rp = @as(u8, @intCast((c >> 16) & 0xFF));
    const x0 = @max(r.left, 0);
    const y0 = @max(r.top, 0);
    const x1 = @min(r.right, bmp.w);
    const y1 = @min(r.bottom, bmp.h);
    if (x0 >= x1 or y0 >= y1) return 1;
    var y = y0;
    while (y < y1) : (y += 1) {
        const row: [*]u8 = bmp.pixels + @as(usize, @intCast(y)) * bmp.stride;
        var x = x0;
        while (x < x1) : (x += 1) {
            const o = @as(usize, @intCast(x)) * 4;
            row[o] = b;
            row[o + 1] = g;
            row[o + 2] = rp;
            row[o + 3] = 0xFF;
        }
    }
    return 1;
}

/// 拿 DC 上选的位图（无位图则 null）；窗口 DC 暂不参与像素拷贝
inline fn dcBitmap(dc: HDC) ?*Bitmap {
    const d = asDc(dc) orelse return null;
    return d.bmp;
}

/// SRCCOPY：按 4 字节逐字拷贝（与 Win32 的 32bpp DIB 行为逐字节一致）
pub fn BitBlt(dst: HDC, dx: i32, dy: i32, w: i32, h: i32, src: HDC, sx: i32, sy: i32, rop: DWORD) BOOL {
    if (rop == PATCOPY or rop == BLACKNESS or rop == WHITENESS) return TRUE; // 本项目只用 SRCCOPY
    const dstb = dcBitmap(dst) orelse return FALSE;
    const srcb = dcBitmap(src) orelse return FALSE;
    if (w <= 0 or h <= 0) return TRUE;
    var y: i32 = 0;
    while (y < h) : (y += 1) {
        const syy = sy + y;
        const dyy = dy + y;
        if (syy < 0 or syy >= srcb.h or dyy < 0 or dyy >= dstb.h) continue;
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const sxx = sx + x;
            const dxx = dx + x;
            if (sxx < 0 or sxx >= srcb.w or dxx < 0 or dxx >= dstb.w) continue;
            const so = @as(usize, @intCast(syy)) * srcb.stride + @as(usize, @intCast(sxx)) * 4;
            const do_ = @as(usize, @intCast(dyy)) * dstb.stride + @as(usize, @intCast(dxx)) * 4;
            dstb.pixels[do_] = srcb.pixels[so];
            dstb.pixels[do_ + 1] = srcb.pixels[so + 1];
            dstb.pixels[do_ + 2] = srcb.pixels[so + 2];
            dstb.pixels[do_ + 3] = srcb.pixels[so + 3];
        }
    }
    return TRUE;
}

/// 最近邻缩放（SetStretchBltMode COLORONCOLOR）：从 src 的 (sx,sy,sw,sh) 贴到 dst 的 (dx,dy,dw,dh)
pub fn StretchBlt(dst: HDC, dx: i32, dy: i32, dw: i32, dh: i32, src: HDC, sx: i32, sy: i32, sw: i32, sh: i32, rop: DWORD) BOOL {
    _ = rop;
    const dstb = dcBitmap(dst) orelse return FALSE;
    const srcb = dcBitmap(src) orelse return FALSE;
    if (dw <= 0 or dh <= 0 or sw <= 0 or sh <= 0) return TRUE;
    var y: i32 = 0;
    while (y < dh) : (y += 1) {
        const syy = sy + @divTrunc(y * sh, dh);
        const dyy = dy + y;
        if (syy < 0 or syy >= srcb.h or dyy < 0 or dyy >= dstb.h) continue;
        var x: i32 = 0;
        while (x < dw) : (x += 1) {
            const sxx = sx + @divTrunc(x * sw, dw);
            const dxx = dx + x;
            if (sxx < 0 or sxx >= srcb.w or dxx < 0 or dxx >= dstb.w) continue;
            const so = @as(usize, @intCast(syy)) * srcb.stride + @as(usize, @intCast(sxx)) * 4;
            const do_ = @as(usize, @intCast(dyy)) * dstb.stride + @as(usize, @intCast(dxx)) * 4;
            dstb.pixels[do_] = srcb.pixels[so];
            dstb.pixels[do_ + 1] = srcb.pixels[so + 1];
            dstb.pixels[do_ + 2] = srcb.pixels[so + 2];
            dstb.pixels[do_ + 3] = srcb.pixels[so + 3];
        }
    }
    return TRUE;
}

pub fn SetStretchBltMode(dc: HDC, mode: i32) i32 {
    const d: *Dc = @ptrCast(@alignCast(dc orelse return 0));
    const old = d.stretch_mode;
    d.stretch_mode = mode;
    return old;
}

// 文本 / 画笔等 GDI 杂项：游戏本体不用程序字体（LED 走图集），只有对话框/关于文案用，
// 交给 Phase 5 的 pango 实现；这里先给安全空实现。
pub fn SetBkMode(dc: HDC, mode: i32) i32 {
    _ = dc;
    _ = mode;
    return TRANSPARENT;
}
pub fn SetTextColor(dc: HDC, c: DWORD) DWORD {
    _ = dc;
    return c;
}
pub fn SetBkColor(dc: HDC, c: DWORD) DWORD {
    _ = dc;
    return c;
}
pub fn DrawTextW(dc: HDC, text: LPCWSTR, n: i32, r: *RECT, fmt: UINT) i32 {
    _ = dc;
    _ = text;
    _ = n;
    _ = r;
    _ = fmt;
    return 0;
}
pub fn CreatePen(style: i32, width: i32, color: DWORD) HGDIOBJ {
    _ = style;
    _ = width;
    _ = color;
    return null;
}
pub fn Rectangle(dc: HDC, x1: i32, y1: i32, x2: i32, y2: i32) BOOL {
    _ = dc;
    _ = x1;
    _ = y1;
    _ = x2;
    _ = y2;
    return TRUE;
}
pub fn MoveToEx(dc: HDC, x: i32, y: i32, prev: ?*POINT) BOOL {
    _ = dc;
    _ = x;
    _ = y;
    _ = prev;
    return TRUE;
}
pub fn LineTo(dc: HDC, x: i32, y: i32) BOOL {
    _ = dc;
    _ = x;
    _ = y;
    return TRUE;
}
pub fn DrawEdge(dc: HDC, r: *RECT, edge: UINT, flags: UINT) BOOL {
    _ = dc;
    _ = r;
    _ = edge;
    _ = flags;
    return TRUE;
}

pub fn GetSystemMetrics(i: i32) i32 {
    return switch (i) {
        SM.CYSCREEN => 1080,
        else => 1920,
    };
}

// ------------------------------------------------------------------ 窗口 / 消息循环
pub fn GetModuleHandleW(name: LPCWSTR) HMODULE {
    _ = name;
    return @ptrFromInt(@as(usize, 1));
}

pub fn RegisterClassExW(wc: *const WNDCLASSEXW) ATOM {
    _ = wc;
    return 1;
}

pub fn CreateWindowExW(exstyle: DWORD, class: LPCWSTR, title: LPCWSTR, style: DWORD, x: i32, y: i32, w: i32, h: i32, parent: HWND, menu: HMENU, hinst: HINSTANCE, param: ?*anyopaque) HWND {
    _ = exstyle;
    _ = class;
    _ = x;
    _ = y;
    _ = hinst;
    _ = param;
    const win = page.create(Window) catch return null;
    win.* = .{
        .rect = .{ .left = 0, .top = 0, .right = w, .bottom = h },
        .menu = null,
        .id = -1,
        .parent = if (parent == null) null else asWindow(parent),
        .text = [_]u16{0} ** MAX_TEXT,
        .text_len = 0,
        .children = [_]?*Window{null} ** MAX_CHILD,
        .child_count = 0,
    };
    const is_child = (style & WS.CHILD) != 0;
    if (is_child) {
        // 子控件的第 9 个参数（hMenu 位）装的是控件 ID（@ptrFromInt(IDC_*)）
        win.id = @intCast(@intFromPtr(menu));
        win.text_len = copyWstr(&win.text, title);
    } else {
        win.menu = menuPtr(menu);
        win.text_len = copyWstr(&win.text, title); // 窗口标题（testWindowTitle 读它）
    }
    if (win.parent != null and win.parent.?.child_count < MAX_CHILD) {
        win.parent.?.children[win.parent.?.child_count] = win;
        win.parent.?.child_count += 1;
    }
    return @ptrCast(win);
}

pub fn DestroyWindow(hwnd: HWND) BOOL {
    const w = asWindow(hwnd) orelse return FALSE;
    page.destroy(w);
    return TRUE;
}

pub fn DefWindowProcW(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM) LRESULT {
    _ = hwnd;
    _ = msg;
    _ = wp;
    _ = lp;
    return 0;
}

pub fn ShowWindow(hwnd: HWND, cmd: i32) BOOL {
    _ = hwnd;
    _ = cmd;
    return TRUE; // TODO(Phase 3 Step B)：接 gtk_widget_show_all
}

pub fn UpdateWindow(hwnd: HWND) BOOL {
    _ = hwnd;
    return TRUE;
}

pub fn PostQuitMessage(code: i32) void {
    _ = code; // TODO(Phase 3 Step B)：接 gtk_main_quit
}

pub fn GetMessageW(msg: *MSG, hwnd: HWND, min: UINT, max: UINT) BOOL {
    _ = msg;
    _ = hwnd;
    _ = min;
    _ = max;
    @panic("GTK 消息循环尚未接入（Phase 3 Step B）");
}

pub fn TranslateMessage(msg: *const MSG) BOOL {
    _ = msg;
    return TRUE;
}

pub fn DispatchMessageW(msg: *const MSG) LRESULT {
    _ = msg;
    return 0;
}

/// 测试路径不会走到真实绘制；给出共享 DC 兜底
pub fn BeginPaint(hwnd: HWND, ps: *PAINTSTRUCT) HDC {
    _ = hwnd;
    ps.* = .{
        .hdc = @ptrCast(&screen_dc),
        .fErase = FALSE,
        .rcPaint = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
        .fRestore = FALSE,
        .fIncUpdate = FALSE,
        .rgbReserved = [_]u8{0} ** 32,
    };
    return @ptrCast(&screen_dc);
}
pub fn EndPaint(hwnd: HWND, ps: *const PAINTSTRUCT) BOOL {
    _ = hwnd;
    _ = ps;
    return TRUE;
}

pub fn GetClientRect(hwnd: HWND, r: *RECT) BOOL {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return FALSE));
    r.* = .{ .left = 0, .top = 0, .right = win.rect.right, .bottom = win.rect.bottom };
    return TRUE;
}

pub fn GetWindowRect(hwnd: HWND, r: *RECT) BOOL {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return FALSE));
    r.* = .{ .left = 0, .top = 0, .right = win.rect.right, .bottom = win.rect.bottom };
    return TRUE;
}

pub fn InvalidateRect(hwnd: HWND, r: ?*const RECT, erase: BOOL) BOOL {
    _ = hwnd;
    _ = r;
    _ = erase;
    return TRUE; // TODO(Phase 3 Step B)：接 gtk_widget_queue_draw
}

pub fn AdjustWindowRect(r: *RECT, style: DWORD, menu: BOOL) BOOL {
    _ = r;
    _ = style;
    _ = menu;
    return TRUE; // 逻辑窗口无边框，客户区即窗口
}

pub fn SetWindowPos(hwnd: HWND, after: HWND, x: i32, y: i32, w: i32, h: i32, flags: UINT) BOOL {
    _ = after;
    _ = x;
    _ = y;
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return FALSE));
    win.rect.right = w;
    win.rect.bottom = h;
    _ = flags;
    return TRUE;
}

pub fn SetCapture(hwnd: HWND) HWND {
    return hwnd;
}
pub fn ReleaseCapture() BOOL {
    return TRUE;
}
pub fn GetCapture() HWND {
    return null;
}

pub fn SetTimer(hwnd: HWND, id: usize, ms: UINT, cb: ?*anyopaque) usize {
    _ = hwnd;
    _ = ms;
    _ = cb;
    return id | 1; // TODO(Phase 3 Step B)：接 g_timeout_add
}
pub fn KillTimer(hwnd: HWND, id: usize) BOOL {
    _ = hwnd;
    _ = id;
    return TRUE;
}

pub fn SetWindowTextW(hwnd: HWND, text: LPCWSTR) BOOL {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return FALSE));
    win.text_len = copyWstr(&win.text, text);
    return TRUE;
}
pub fn GetWindowTextW(hwnd: HWND, buf: LPWSTR, max: i32) i32 {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return 0));
    if (max <= 0) return 0;
    const n = @min(win.text_len, @as(usize, @intCast(max - 1)));
    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = win.text[i];
    buf[n] = 0;
    return @intCast(n);
}

pub fn GetDlgItem(hwnd: HWND, id: i32) HWND {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return null));
    for (win.children[0..win.child_count]) |c| {
        if (c != null and c.?.id == id) return @ptrCast(c.?);
    }
    return null;
}
pub fn GetParent(hwnd: HWND) HWND {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return null));
    return @ptrCast(win.parent);
}
pub fn IsChild(parent: HWND, child: HWND) BOOL {
    _ = parent;
    _ = child;
    return FALSE;
}
pub fn EnumChildWindows(hwnd: HWND, cb: ?*const fn (HWND, LPARAM) callconv(.c) BOOL, lp: LPARAM) BOOL {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return FALSE));
    const f = cb orelse return FALSE;
    for (win.children[0..win.child_count]) |c| {
        if (c == null) continue;
        if (f(@ptrCast(c.?), lp) == FALSE) return FALSE;
    }
    return TRUE;
}
pub fn SetFocus(hwnd: HWND) HWND {
    return hwnd;
}
pub fn GetFocus() HWND {
    return null;
}
pub fn ScreenToClient(hwnd: HWND, p: *POINT) BOOL {
    _ = hwnd;
    _ = p;
    return TRUE;
}
pub fn ClientToScreen(hwnd: HWND, p: *POINT) BOOL {
    _ = hwnd;
    _ = p;
    return TRUE;
}
pub fn GetForegroundWindow() HWND {
    return null;
}
pub fn SetForegroundWindow(hwnd: HWND) BOOL {
    _ = hwnd;
    return TRUE;
}
pub fn GetDesktopWindow() HWND {
    return null;
}
pub fn GetKeyState(k: i32) i16 {
    _ = k;
    return 0;
}
pub fn IsDialogMessageW(hwnd: HWND, msg: *MSG) BOOL {
    _ = hwnd;
    _ = msg;
    return FALSE;
}
pub fn SystemParametersInfoW(a: UINT, b: UINT, c: ?*anyopaque, d: UINT) BOOL {
    _ = a;
    _ = b;
    _ = c;
    _ = d;
    return TRUE;
}
pub fn SetProcessDpiAwarenessContext(c: ?*anyopaque) BOOL {
    _ = c;
    return TRUE;
}

pub fn SendMessageW(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM) LRESULT {
    _ = hwnd;
    _ = msg;
    _ = wp;
    _ = lp;
    return 0;
}

pub fn GetTickCount() DWORD {
    return @truncate(@as(u64, @bitCast(std.time.milliTimestamp())));
}
pub fn GetTickCount64() u64 {
    return @intCast(std.time.milliTimestamp());
}
pub fn ExitProcess(code: UINT) noreturn {
    std.process.exit(@intCast(code));
}
pub fn SetProcessDPIAware() BOOL {
    return TRUE;
}
pub fn QueryPerformanceCounter(c: *i64) BOOL {
    c.* = std.time.nanoTimestamp();
    return TRUE;
}
// ------------------------------------------------------------------ 菜单
fn menuPtr(h: HMENU) ?*Menu {
    return asMenu(h);
}

pub fn CreateMenu() HMENU {
    const m = newMenu() orelse return null;
    return @ptrCast(m);
}
pub fn CreatePopupMenu() HMENU {
    const m = newMenu() orelse return null;
    return @ptrCast(m);
}

pub fn AppendMenuW(menu: HMENU, flags: UINT, id_new: usize, label: LPCWSTR) BOOL {
    const m = menuPtr(menu) orelse return FALSE;
    _ = label;
    if (m.count >= MENU_MAX) return FALSE;
    const e = &m.entries[m.count];
    if (flags & MF.SEPARATOR != 0) {
        e.* = .{ .id = 0, .sub = null, .checked = false }; // 分隔线 ID = 0（Win32 GetMenuItemID 语义）
    } else if (flags & MF.POPUP != 0) {
        const sub: *Menu = @ptrFromInt(id_new);
        e.* = .{ .id = -1, .sub = sub, .checked = false };
    } else {
        e.* = .{ .id = @intCast(@as(u32, @truncate(id_new))), .sub = null, .checked = false };
    }
    m.count += 1;
    return TRUE;
}

pub fn SetMenu(hwnd: HWND, menu: HMENU) BOOL {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return FALSE));
    win.menu = menuPtr(menu);
    return TRUE;
}

pub fn GetMenu(hwnd: HWND) HMENU {
    const win: *Window = @ptrCast(@alignCast(hwnd orelse return null));
    return @ptrCast(win.menu);
}

pub fn GetSubMenu(menu: HMENU, pos: i32) HMENU {
    const m = menuPtr(menu) orelse return null;
    if (pos < 0 or @as(usize, @intCast(pos)) >= m.count) return null;
    return @ptrCast(m.entries[@intCast(pos)].sub);
}

pub fn GetMenuItemCount(menu: HMENU) i32 {
    const m = menuPtr(menu) orelse return -1;
    return @intCast(m.count);
}

pub fn GetMenuItemID(menu: HMENU, pos: i32) UINT {
    const m = menuPtr(menu) orelse return 0xFFFFFFFF;
    if (pos < 0 or @as(usize, @intCast(pos)) >= m.count) return 0xFFFFFFFF;
    return @bitCast(m.entries[@intCast(pos)].id);
}

pub fn GetMenuState(menu: HMENU, item: UINT, flags: UINT) UINT {
    const m = menuPtr(menu) orelse return 0;
    if (flags & MF.BYPOSITION != 0) {
        const i: usize = item;
        if (i >= m.count) return 0;
        if (m.entries[i].checked) return MF.CHECKED;
        return 0;
    }
    // BYCOMMAND
    for (m.entries[0..m.count]) |e| {
        if (@as(UINT, @bitCast(e.id)) == item and e.checked) return MF.CHECKED;
    }
    return 0;
}

pub fn CheckMenuItem(menu: HMENU, item: UINT, flags: UINT) DWORD {
    const m = menuPtr(menu) orelse return 0xFFFFFFFF;
    const want = (flags & MF.CHECKED) != 0;
    var old: DWORD = 0;
    if (flags & MF.BYPOSITION != 0) {
        const i: usize = item;
        if (i >= m.count) return 0xFFFFFFFF;
        if (m.entries[i].checked) old = MF.CHECKED;
        m.entries[i].checked = want;
    } else {
        for (m.entries[0..m.count]) |*e| {
            if (@as(UINT, @bitCast(e.id)) != item) continue;
            if (e.checked) old = MF.CHECKED;
            e.checked = want;
        }
    }
    return old;
}

pub fn CheckMenuRadioItem(menu: HMENU, first: UINT, last: UINT, checked: UINT, flags: UINT) BOOL {
    const m = menuPtr(menu) orelse return FALSE;
    for (m.entries[0..m.count]) |*e| {
        const key: UINT = if (flags & MF.BYPOSITION != 0) blk: {
            const idx = @intFromPtr(e) - @intFromPtr(&m.entries[0]);
            const off = idx / @sizeOf(MenuEntry);
            break :blk @intCast(off);
        } else @bitCast(e.id);
        if (key < first or key > last) continue;
        e.checked = (key == checked);
    }
    return TRUE;
}

pub fn EnableMenuItem(menu: HMENU, item: UINT, flags: UINT) BOOL {
    _ = menu;
    _ = item;
    _ = flags;
    return TRUE;
}

// ------------------------------------------------------------------ 图标 / 光标 / 字体
// Linux 没有 .rsrc，图标统一回退到图集里的编程图标；这里给非空句柄满足「图标可用」判断。
pub fn LoadCursorW(hinst: HINSTANCE, name: LPCWSTR) HCURSOR {
    _ = hinst;
    _ = name;
    return @ptrFromInt(@as(usize, 0x300));
}
pub fn LoadIconW(hinst: HINSTANCE, name: ?*const anyopaque) HICON {
    _ = hinst;
    _ = name;
    return @ptrFromInt(@as(usize, 0x300));
}
pub fn LoadImageW(hinst: HINSTANCE, name: ?*const anyopaque, kind: UINT, cx: i32, cy: i32, flags: UINT) HANDLE {
    _ = hinst;
    _ = name;
    _ = kind;
    _ = cx;
    _ = cy;
    _ = flags;
    return @ptrFromInt(@as(usize, 0x300));
}
pub fn CreateIconIndirect(info: *ICONINFO) HICON {
    _ = info;
    return @ptrFromInt(@as(usize, 0x300));
}
pub fn CreateFontW(h: i32, w: i32, e: i32, o: i32, wt: i32, it: DWORD, u: DWORD, s: DWORD, cs: DWORD, op: DWORD, cp: DWORD, q: DWORD, p: DWORD, face: LPCWSTR) HFONT {
    _ = h;
    _ = w;
    _ = e;
    _ = o;
    _ = wt;
    _ = it;
    _ = u;
    _ = s;
    _ = cs;
    _ = op;
    _ = cp;
    _ = q;
    _ = p;
    _ = face;
    return @ptrFromInt(@as(usize, 0x320));
}

// ------------------------------------------------------------------ 消息框 / 音频 / 抓图
pub fn MessageBoxW(hwnd: HWND, text: LPCWSTR, caption: LPCWSTR, kind: UINT) i32 {
    _ = hwnd;
    _ = text;
    _ = caption;
    _ = kind;
    return 1; // IDOK；真实 GTK 对话框接在 Phase 5
}
pub fn MessageBoxIndirectW(p: *const MSGBOXPARAMS) i32 {
    _ = p;
    return 1;
}
pub fn PlaySoundW(data: ?*const anyopaque, mod: ?*anyopaque, flags: DWORD) BOOL {
    _ = data;
    _ = mod;
    _ = flags;
    return TRUE; // TODO(Phase 4)：SDL2_mixer
}
pub fn PrintWindow(hwnd: HWND, dc: HDC, flags: UINT) BOOL {
    _ = hwnd;
    _ = dc;
    _ = flags;
    return TRUE; // TODO(Phase 6)：窗口抓图
}

// ------------------------------------------------------------------ 持久化
// Linux 侧把 HKCU 注册表换成「零副作用」实现：open/create 一律返回失败（走默认值，
// 不 load 也不 save）。真正的文件持久化（~/.config/complexweeper/registry.ini）留到 Phase 5。
pub fn RegOpenKeyExW(hive: usize, sub: LPCWSTR, opt: u32, access: u32, out: *usize) callconv(.c) i32 {
    _ = hive;
    _ = sub;
    _ = opt;
    _ = access;
    _ = out;
    return 2; // ERROR_FILE_NOT_FOUND
}
pub fn RegCreateKeyExW(hive: usize, sub: LPCWSTR, opt: u32, cls: LPCWSTR, disp: u32, access: u32, sec: ?*anyopaque, out: *usize, disp_out: ?*u32) callconv(.c) i32 {
    _ = hive;
    _ = sub;
    _ = opt;
    _ = cls;
    _ = disp;
    _ = access;
    _ = sec;
    _ = out;
    _ = disp_out;
    return 2;
}
pub fn RegSetValueExW(key: usize, name: LPCWSTR, opt: u32, kind: u32, data: [*]const u8, len: u32) callconv(.c) i32 {
    _ = key;
    _ = name;
    _ = opt;
    _ = kind;
    _ = data;
    _ = len;
    return 0;
}
pub fn RegQueryValueExW(key: usize, name: LPCWSTR, kind: ?*u32, kind_out: ?*u32, data: ?[*]u8, len: ?*u32) callconv(.c) i32 {
    _ = key;
    _ = name;
    _ = kind;
    _ = kind_out;
    _ = data;
    _ = len;
    return 2;
}
pub fn RegCloseKey(key: usize) callconv(.c) i32 {
    _ = key;
    return 0;
}