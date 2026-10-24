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

// ================================================================== GTK3 交互绑定（Phase 3 Step B）
// 手写 C ABI 绑定（不用 @cImport，避免翻译 GTK 庞大的头）：只声明本程序用到的符号。
// 动态链接由 ../build.zig 的 linkSystemLibrary 负责；extern 后面的库名是文档性标注。
const GtkWindowType = c_int;
const GTK_WINDOW_TOPLEVEL: GtkWindowType = 0;

const GtkWidget = opaque {};
const GtkWindow = opaque {};
const GtkContainer = opaque {};
const GtkBox = opaque {};
const GtkMenuBar = opaque {};
const GtkMenu = opaque {};
const GtkMenuShell = opaque {};
const GtkMenuItem = opaque {};
const GtkCheckMenuItem = opaque {};
const cairo_t = opaque {};
const cairo_surface_t = opaque {};

const GCallback = ?*const fn () callconv(.c) void;
const GSourceFunc = ?*const fn (?*anyopaque) callconv(.c) c_int;

const GDK_BUTTON_PRESS_MASK: c_int = 0x100;
const GDK_BUTTON_RELEASE_MASK: c_int = 0x200;
const GDK_POINTER_MOTION_MASK: c_int = 0x40;
const GDK_KEY_PRESS_MASK: c_int = 0x400;
const GTK_ORIENTATION_VERTICAL: c_int = 1;

// GDK 事件结构：只声明到我们要读的字段，偏移按 x86_64 GTK3 ABI 自然对齐
const GdkEventButton = extern struct {
    type: c_int,
    window: ?*anyopaque,
    send_event: i8,
    time: u32,
    x: f64,
    y: f64,
    axes: ?[*]f64,
    state: u32,
    button: u32,
    device: ?*anyopaque,
    x_root: f64,
    y_root: f64,
};
const GdkEventMotion = extern struct {
    type: c_int,
    window: ?*anyopaque,
    send_event: i8,
    time: u32,
    x: f64,
    y: f64,
    axes: ?[*]f64,
    state: u32,
    is_hint: i16,
    device: ?*anyopaque,
    x_root: f64,
    y_root: f64,
};
const GdkEventKey = extern struct {
    type: c_int,
    window: ?*anyopaque,
    send_event: i8,
    time: u32,
    state: u32,
    keyval: u32,
};

// cairo RGB24 每像素 32 位 = 小端去内存字节 [B,G,R,X]，与后端 32bpp BGRA 帧缓冲逐字节一致，
// 高 8 位被忽略 → 等价于 Win32 BitBlt 的不透明拷贝。
const CAIRO_FORMAT_RGB24: c_int = 1;

pub extern "gtk-3" fn gtk_init(argc: ?*c_int, argv: ?*anyopaque) callconv(.c) void;
pub extern "gtk-3" fn gtk_main() callconv(.c) void;
pub extern "gtk-3" fn gtk_main_quit() callconv(.c) void;
pub extern "gtk-3" fn gtk_window_new(t: GtkWindowType) callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_window_set_title(w: ?*GtkWindow, title: [*:0]const u8) callconv(.c) void;
pub extern "gtk-3" fn gtk_window_set_resizable(w: ?*GtkWindow, resizable: c_int) callconv(.c) void;
pub extern "gtk-3" fn gtk_container_add(c: ?*GtkContainer, child: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_drawing_area_new() callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_widget_show_all(w: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_hide(w: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_queue_draw(w: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_queue_resize(w: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_set_size_request(w: ?*GtkWidget, wd: c_int, ht: c_int) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_set_can_focus(w: ?*GtkWidget, can_focus: c_int) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_grab_focus(w: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_add_events(w: ?*GtkWidget, events: c_int) callconv(.c) void;
pub extern "gtk-3" fn gtk_widget_destroy(w: ?*GtkWidget) callconv(.c) void;
// g_signal_connect 是宏，真实符号是 g_signal_connect_data（GConnectFlags 默认 0）
pub extern "gobject-2.0" fn g_signal_connect_data(instance: ?*anyopaque, sig: [*:0]const u8, cb: GCallback, data: ?*anyopaque, destroy_data: ?*anyopaque, flags: c_int) callconv(.c) c_ulong;
pub extern "glib-2.0" fn g_timeout_add(interval: c_uint, func: GSourceFunc, data: ?*anyopaque) callconv(.c) c_uint;
pub extern "glib-2.0" fn g_source_remove(tag: c_uint) callconv(.c) c_int;
pub extern "cairo" fn cairo_image_surface_create_for_data(data: [*]u8, format: c_int, width: c_int, height: c_int, stride: c_int) callconv(.c) ?*cairo_surface_t;
pub extern "cairo" fn cairo_surface_destroy(s: ?*cairo_surface_t) callconv(.c) void;
pub extern "cairo" fn cairo_set_source_surface(cr: ?*cairo_t, s: ?*cairo_surface_t, x: f64, y: f64) callconv(.c) void;
pub extern "cairo" fn cairo_paint(cr: ?*cairo_t) callconv(.c) void;
pub extern "gtk-3" fn gtk_box_new(orientation: c_int, spacing: c_int) callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_box_pack_start(box: ?*GtkBox, child: ?*GtkWidget, expand: c_int, fill: c_int, padding: c_uint) callconv(.c) void;
pub extern "gtk-3" fn gtk_menu_bar_new() callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_menu_new() callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_menu_item_new_with_mnemonic(label: [*:0]const u8) callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_check_menu_item_new_with_mnemonic(label: [*:0]const u8) callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_separator_menu_item_new() callconv(.c) ?*GtkWidget;
pub extern "gtk-3" fn gtk_menu_item_set_submenu(item: ?*GtkMenuItem, submenu: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_menu_shell_append(shell: ?*GtkMenuShell, item: ?*GtkWidget) callconv(.c) void;
pub extern "gtk-3" fn gtk_check_menu_item_set_active(item: ?*GtkCheckMenuItem, active: c_int) callconv(.c) void;
pub extern "gtk-3" fn gtk_check_menu_item_set_draw_as_radio(item: ?*GtkCheckMenuItem, draw_as_radio: c_int) callconv(.c) void;

// ------------------------------------------------------------------ 内部运行时结构
// ------------------------------------------------------------------ 内部运行时结构
/// 32bpp 自顶向下 BGRA 位图：与 Win32 DIB 逐字节一致（SRCCOPY 就是 4 字节拷贝）
const Bitmap = struct {
    w: i32,
    h: i32,
    stride: usize, // = w*4
    pixels: [*]u8,
};

const Brush = struct {
    color: DWORD,
};

// GDI 对象用「指针身份寄存器」判型：绝不通过 @ptrCast 到别的结构体类型去读类型头。
// Zig 0.14 的类型别名分析会让跨类型读拿到陈旧/脏数据（page_allocator 复用页 + 死 store 消除）。
const MAX_BMP = 64;
const MAX_BR = 32;
var g_bitmaps: [MAX_BMP]?*Bitmap = [_]?*Bitmap{null} ** MAX_BMP;
var g_brushes: [MAX_BR]?*Brush = [_]?*Brush{null} ** MAX_BR;

fn regBitmap(b: *Bitmap) void {
    for (&g_bitmaps) |*slot| {
        if (slot.* == null) {
            slot.* = b;
            return;
        }
    }
}
fn unregBitmap(b: *Bitmap) void {
    for (&g_bitmaps) |*slot| {
        if (slot.*) |bb| {
            if (bb == b) {
                slot.* = null;
                return;
            }
        }
    }
}
fn regBrush(b: *Brush) void {
    for (&g_brushes) |*slot| {
        if (slot.* == null) {
            slot.* = b;
            return;
        }
    }
}
fn unregBrush(b: *Brush) void {
    for (&g_brushes) |*slot| {
        if (slot.*) |bb| {
            if (bb == b) {
                slot.* = null;
                return;
            }
        }
    }
}

inline fn asBitmap(o: HGDIOBJ) ?*Bitmap {
    const addr = @intFromPtr(o orelse return null);
    for (g_bitmaps) |b| {
        if (b) |bb| {
            if (@intFromPtr(bb) == addr) return bb;
        }
    }
    return null;
}
inline fn asBrush(o: HGDIOBJ) ?*Brush {
    const addr = @intFromPtr(o orelse return null);
    for (g_brushes) |b| {
        if (b) |bb| {
            if (@intFromPtr(bb) == addr) return bb;
        }
    }
    return null;
}

/// 设备上下文：内存 DC 选一张位图；窗口 DC 指向窗口（交互式绘制用，暂未接入 cairo）
const Dc = struct {
    bmp: ?*Bitmap = null,
    win: ?*Window = null,
    stretch_mode: i32 = 3, // COLORONCOLOR=3（最近邻），与 Win32 SetStretchBltMode(3) 一致
};

/// 菜单镜像：按位置可查命令 ID / 复选态 / 子菜单
const MAX_LABEL = 160; // UTF-8 菜单文字上限（含 _ 助记符；\t 提示已截断）
const MenuEntry = struct {
    id: i32 = -1, // -1 = 子菜单；0 = 分隔线；>0 = 命令号
    sub: ?*Menu = null,
    checked: bool = false,
    checkable: bool = false, // 被 CheckMenuItem/CheckMenuRadioItem 动过 → 建 GtkCheckMenuItem（圆点）
    widget: ?*GtkWidget = null, // 挂在 GtkMenu/GtkMenuBar 里的 GtkMenuItem
    label: [MAX_LABEL]u8 = [_]u8{0} ** MAX_LABEL,
    label_len: usize = 0,
};
const MENU_MAX = 24;
const Menu = struct {
    entries: [MENU_MAX]MenuEntry = undefined,
    count: usize = 0,
    widget: ?*GtkWidget = null, // GtkMenuBar（顶栏）或 GtkMenu（子菜单）
};

/// 逻辑窗口：客户区尺寸 + 菜单栏/控件 ID + 文本 + 父子关系 + GTK 挂载点
const MAX_TEXT = 128;
const MAX_CHILD = 28;
const MAX_TIMERS = 4;
const WinTimer = struct { id: usize = 0, tag: c_uint = 0, active: bool = false, win: ?*Window = null };
const Window = struct {
    rect: RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    proc: ?WNDPROC = null, // 窗口过程（RegisterClassExW 保存，交互消息分派用）
    gtk_win: ?*GtkWidget = null,
    draw_area: ?*GtkWidget = null,
    fb: ?*Bitmap = null, // 客户区帧缓冲（32bpp BGRA，draw 回调里上传 cairo）
    timers: [MAX_TIMERS]WinTimer = [_]WinTimer{.{}} ** MAX_TIMERS,
    menu: ?*Menu = null,
    id: i32 = -1, // 子控件 ID（对话框用）；-1 = 无
    parent: ?*Window = null,
    text: [MAX_TEXT]u16 = [_]u16{0} ** MAX_TEXT,
    text_len: usize = 0,
    children: [MAX_CHILD]?*Window = [_]?*Window{null} ** MAX_CHILD,
    child_count: usize = 0,
};

// 窗口类注册表：RegisterClassExW 存 WndProc，CreateWindowExW 按类名查回
const MAX_CLASS = 8;
const WndClassRec = struct {
    name: [64]u16 = [_]u16{0} ** 64,
    proc: ?WNDPROC = null,
};
var wnd_classes: [MAX_CLASS]WndClassRec = [_]WndClassRec{.{}} ** MAX_CLASS;
var wnd_class_count: usize = 0;

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
    bmp.w = @intCast(pw);
    bmp.h = @intCast(ph);
    bmp.stride = pw * 4;
    bmp.pixels = mem.ptr;
    regBitmap(bmp);
    bits.* = @ptrCast(mem.ptr);
    return @ptrCast(bmp);
}

pub fn CreateCompatibleDC(dc: HDC) HDC {
    _ = dc;
    const d = page.create(Dc) catch return null;
    d.* = .{ .bmp = null, .win = null };
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
    if (asBitmap(obj)) |bmp| {
        const old = d.bmp;
        d.bmp = bmp;
        return @ptrCast(old);
    }
    return null; // 笔 / 刷 / 字体不选进 DC（本程序用不到）
}

pub fn DeleteObject(obj: HGDIOBJ) BOOL {
    if (asBitmap(obj)) |b| {
        unregBitmap(b);
        page.free(b.pixels[0 .. b.stride * @as(usize, @intCast(b.h))]);
        page.destroy(b);
        return TRUE;
    }
    if (asBrush(obj)) |b| {
        unregBrush(b);
        page.destroy(b);
        return TRUE;
    }
    return TRUE;
}

pub fn DeleteDC(dc: HDC) BOOL {
    const d = asDc(dc) orelse return FALSE;
    page.destroy(d);
    return TRUE;
}

/// 屏幕 DC（GetDC(null)）：一个不挂位图的共享 DC
var screen_dc: Dc = .{ .bmp = null, .win = null };

pub fn GetDC(hwnd: HWND) HDC {
    if (hwnd == null) return @ptrCast(&screen_dc);
    const d = page.create(Dc) catch return @ptrCast(&screen_dc);
    d.* = .{ .bmp = null, .win = asWindow(hwnd) };
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
    b.color = color;
    regBrush(b);
    return @ptrCast(b);
}

pub fn GetStockObject(i: i32) HGDIOBJ {
    return @ptrFromInt(@as(usize, @intCast(i + 1)));
}

/// 经典填充：把 DC 上选区填成实色（写 BGRA，alpha=255，保证最终上屏不透明）
pub fn FillRect(dc: HDC, r: *const RECT, br: HBRUSH) i32 {
    const d: *Dc = @ptrCast(@alignCast(dc orelse return 0));
    const bmp = d.bmp orelse return 0;
    const br_obj = asBrush(br) orelse return 0;
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

// ------------------------------------------------------------------ GTK 运行时（Phase 3 Step B）
var gtk_started = false;
var draw_cr: ?*cairo_t = null;
var capture_win: HWND = null;

fn ensureGtk() void {
    if (gtk_started) return;
    gtk_started = true;
    var argc: c_int = 0;
    gtk_init(&argc, null);
}

fn wstrEq(buf: []const u16, s: LPCWSTR) bool {
    const p = s orelse return false;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (buf[i] != p[i]) return false;
        if (buf[i] == 0) return true;
    }
    return false;
}

fn findClass(name: LPCWSTR) ?*WndClassRec {
    const s = name orelse return null;
    for (wnd_classes[0..wnd_class_count]) |*rc| {
        if (wstrEq(&rc.name, s)) return rc;
    }
    return null;
}

fn wideToUtf8Z(buf: []u8, s: []const u16) [:0]const u8 {
    const n = std.unicode.utf16LeToUtf8(buf, s) catch 0;
    if (n >= buf.len) return buf[0..0 :0];
    buf[n] = 0;
    return buf[0..n :0];
}

fn ensureFramebuffer(win: *Window) void {
    const cw = win.rect.right;
    const ch = win.rect.bottom;
    if (cw <= 0 or ch <= 0) return;
    if (win.fb) |fb| {
        if (fb.w == cw and fb.h == ch) return;
        _ = DeleteObject(@ptrCast(fb));
        win.fb = null;
    }
    win.fb = asBitmap(CreateCompatibleBitmap(null, cw, ch));
}

fn flushToCairo(win: *Window, cr: ?*cairo_t) void {
    const cr2 = cr orelse return;
    const fb = win.fb orelse return;
    const surf = cairo_image_surface_create_for_data(fb.pixels, CAIRO_FORMAT_RGB24, fb.w, fb.h, @intCast(fb.stride));
    defer cairo_surface_destroy(surf);
    cairo_set_source_surface(cr2, surf, 0, 0);
    cairo_paint(cr2);
}

fn fireMouse(win: *Window, msg: UINT, x: f64, y: f64) void {
    const ix: i32 = @intFromFloat(x);
    const iy: i32 = @intFromFloat(y);
    if (win.proc) |p| _ = p(@ptrCast(win), msg, 0, makeLParam(ix, iy));
}

/// GDK keysym → Win32 虚键码（本程序只用 F 键重开；0x72 在 Win32 里是 VK_F3）
fn gdkKeyToVk(keyval: u32) WPARAM {
    if (keyval >= 0xFFBE and keyval <= 0xFFC9) return keyval - 0xFFBE + 0x70; // F1..F12
    return keyval;
}

fn buildGtkWindow(win: *Window) void {
    if (win.gtk_win != null) return;
    ensureGtk();
    const gw = gtk_window_new(GTK_WINDOW_TOPLEVEL) orelse return;
    win.gtk_win = gw;
    var buf: [MAX_TEXT * 4]u8 = [_]u8{0} ** (MAX_TEXT * 4);
    gtk_window_set_title(@ptrCast(gw), wideToUtf8Z(&buf, win.text[0..win.text_len]).ptr);
    const cw = win.rect.right;
    const ch = win.rect.bottom;
    const da = gtk_drawing_area_new() orelse return;
    win.draw_area = da;
    gtk_widget_set_size_request(da, cw, ch);
    gtk_widget_add_events(da, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_POINTER_MOTION_MASK | GDK_KEY_PRESS_MASK);
    gtk_widget_set_can_focus(da, 1);
    const box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0) orelse return;
    if (win.menu) |bar| {
        if (buildMenuBar(win, bar)) |mb| gtk_box_pack_start(@ptrCast(box), mb, 0, 0, 0);
    }
    gtk_box_pack_start(@ptrCast(box), da, 1, 1, 0);
    gtk_container_add(@ptrCast(gw), box);
    gtk_window_set_resizable(@ptrCast(gw), 0);
    ensureFramebuffer(win);
    _ = g_signal_connect_data(@ptrCast(da), "draw", @ptrCast(&onDraw), @ptrCast(win), null, 0);
    _ = g_signal_connect_data(@ptrCast(da), "button-press-event", @ptrCast(&onButtonPress), @ptrCast(win), null, 0);
    _ = g_signal_connect_data(@ptrCast(da), "button-release-event", @ptrCast(&onButtonRelease), @ptrCast(win), null, 0);
    _ = g_signal_connect_data(@ptrCast(da), "motion-notify-event", @ptrCast(&onMotion), @ptrCast(win), null, 0);
    _ = g_signal_connect_data(@ptrCast(da), "key-press-event", @ptrCast(&onKeyPress), @ptrCast(win), null, 0);
    _ = g_signal_connect_data(@ptrCast(gw), "delete-event", @ptrCast(&onDeleteEvent), @ptrCast(win), null, 0);
    _ = g_signal_connect_data(@ptrCast(gw), "destroy", @ptrCast(&onDestroyEvent), @ptrCast(win), null, 0);
}

// ------------------------------------------------------------------ 窗口 / 消息循环
pub fn GetModuleHandleW(name: LPCWSTR) HMODULE {
    _ = name;
    return @ptrFromInt(@as(usize, 1));
}

pub fn RegisterClassExW(wc: *const WNDCLASSEXW) ATOM {
    if (wnd_class_count >= MAX_CLASS) return 0;
    const rec = &wnd_classes[wnd_class_count];
    _ = copyWstr(&rec.name, wc.lpszClassName);
    rec.proc = wc.lpfnWndProc;
    wnd_class_count += 1;
    return @intCast(wnd_class_count);
}

pub fn CreateWindowExW(exstyle: DWORD, class: LPCWSTR, title: LPCWSTR, style: DWORD, x: i32, y: i32, w: i32, h: i32, parent: HWND, menu: HMENU, hinst: HINSTANCE, param: ?*anyopaque) HWND {
    _ = exstyle;
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
    win.proc = if (findClass(class)) |rc| rc.proc else null;
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

fn onDraw(widget: ?*GtkWidget, cr: ?*cairo_t, user: ?*anyopaque) callconv(.c) c_int {
    _ = widget;
    const win: *Window = @ptrCast(@alignCast(user.?));
    draw_cr = cr;
    if (win.proc) |p| _ = p(@ptrCast(win), WM.PAINT, 0, 0);
    draw_cr = null;
    return 1;
}
fn onButtonPress(widget: ?*GtkWidget, ev: ?*anyopaque, user: ?*anyopaque) callconv(.c) c_int {
    _ = widget;
    const win: *Window = @ptrCast(@alignCast(user.?));
    const e: *GdkEventButton = @ptrCast(@alignCast(ev.?));
    const msg: UINT = switch (e.button) {
        1 => WM.LBUTTONDOWN,
        2 => WM.MBUTTONDOWN,
        3 => WM.RBUTTONDOWN,
        else => return 0,
    };
    fireMouse(win, msg, e.x, e.y);
    return 1;
}
fn onButtonRelease(widget: ?*GtkWidget, ev: ?*anyopaque, user: ?*anyopaque) callconv(.c) c_int {
    _ = widget;
    const win: *Window = @ptrCast(@alignCast(user.?));
    const e: *GdkEventButton = @ptrCast(@alignCast(ev.?));
    const msg: UINT = switch (e.button) {
        1 => WM.LBUTTONUP,
        2 => WM.MBUTTONUP,
        3 => WM.RBUTTONUP,
        else => return 0,
    };
    fireMouse(win, msg, e.x, e.y);
    return 1;
}
fn onMotion(widget: ?*GtkWidget, ev: ?*anyopaque, user: ?*anyopaque) callconv(.c) c_int {
    _ = widget;
    const win: *Window = @ptrCast(@alignCast(user.?));
    const e: *GdkEventMotion = @ptrCast(@alignCast(ev.?));
    fireMouse(win, WM.MOUSEMOVE, e.x, e.y);
    return 0;
}
fn onKeyPress(widget: ?*GtkWidget, ev: ?*anyopaque, user: ?*anyopaque) callconv(.c) c_int {
    _ = widget;
    const win: *Window = @ptrCast(@alignCast(user.?));
    const e: *GdkEventKey = @ptrCast(@alignCast(ev.?));
    if (win.proc) |p| _ = p(@ptrCast(win), WM.KEYDOWN, gdkKeyToVk(e.keyval), 0);
    return 1;
}
fn onDeleteEvent(widget: ?*GtkWidget, ev: ?*anyopaque, user: ?*anyopaque) callconv(.c) c_int {
    _ = widget;
    _ = ev;
    const win: *Window = @ptrCast(@alignCast(user.?));
    if (win.proc) |p| _ = p(@ptrCast(win), WM.CLOSE, 0, 0);
    return 1; // 手动处理关闭，GTK 别再销毁
}
fn onDestroyEvent(widget: ?*GtkWidget, user: ?*anyopaque) callconv(.c) void {
    _ = widget;
    const win: *Window = @ptrCast(@alignCast(user.?));
    win.gtk_win = null;
    win.draw_area = null;
    if (win.proc) |p| _ = p(@ptrCast(win), WM.DESTROY, 0, 0);
}

fn timerCallback(data: ?*anyopaque) callconv(.c) c_int {
    const t: *WinTimer = @ptrCast(@alignCast(data.?));
    const id = t.id;
    const win = t.win orelse return 0;
    if (win.proc) |p| _ = p(@ptrCast(win), WM.TIMER, id, 0);
    return if (t.active and t.id == id) 1 else 0;
}
fn killTimerId(win: *Window, id: usize) void {
    for (&win.timers) |*t| {
        if (t.active and t.id == id) {
            _ = g_source_remove(t.tag);
            t.active = false;
        }
    }
}

pub fn DestroyWindow(hwnd: HWND) BOOL {
    const win = asWindow(hwnd) orelse return FALSE;
    for (&win.timers) |*t| {
        if (t.active) {
            _ = g_source_remove(t.tag);
            t.active = false;
        }
    }
    if (win.fb) |fb| {
        _ = DeleteObject(@ptrCast(fb));
        win.fb = null;
    }
    if (win.gtk_win) |gw| gtk_widget_destroy(gw); // 同步触发 destroy 信号 → onDestroy
    win.gtk_win = null;
    win.draw_area = null;
    page.destroy(win);
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
    const win = asWindow(hwnd) orelse return FALSE;
    if (cmd == SW.HIDE) {
        if (win.gtk_win) |gw| gtk_widget_hide(gw);
        return TRUE;
    }
    if (cmd != SW.SHOW) return TRUE; // SHOWNA(8) 等留给抓图阶段（Phase 6）
    buildGtkWindow(win);
    gtk_widget_show_all(win.gtk_win orelse return FALSE);
    if (win.draw_area) |da| gtk_widget_grab_focus(da);
    return TRUE;
}

pub fn UpdateWindow(hwnd: HWND) BOOL {
    const win = asWindow(hwnd) orelse return FALSE;
    if (win.draw_area) |da| gtk_widget_queue_draw(da);
    return TRUE;
}

pub fn PostQuitMessage(code: i32) void {
    _ = code;
    gtk_main_quit();
}

pub fn GetMessageW(msg: *MSG, hwnd: HWND, min: UINT, max: UINT) BOOL {
    _ = msg;
    _ = hwnd;
    _ = min;
    _ = max;
    ensureGtk();
    gtk_main(); // 阻塞直到 onDestroy → PostQuitMessage → gtk_main_quit
    return 0;
}

pub fn TranslateMessage(msg: *const MSG) BOOL {
    _ = msg;
    return TRUE;
}

pub fn DispatchMessageW(msg: *const MSG) LRESULT {
    _ = msg;
    return 0;
}

pub fn BeginPaint(hwnd: HWND, ps: *PAINTSTRUCT) HDC {
    const win = asWindow(hwnd);
    if (win) |w0| ensureFramebuffer(w0);
    const d = page.create(Dc) catch return @ptrCast(&screen_dc);
    d.* = .{
        .bmp = if (win) |w0| w0.fb else null,
        .win = win,
    };
    ps.* = .{
        .hdc = @ptrCast(d),
        .fErase = FALSE,
        .rcPaint = .{ .left = 0, .top = 0, .right = if (win) |w0| w0.rect.right else 0, .bottom = if (win) |w0| w0.rect.bottom else 0 },
        .fRestore = FALSE,
        .fIncUpdate = FALSE,
        .rgbReserved = [_]u8{0} ** 32,
    };
    return @ptrCast(d);
}
pub fn EndPaint(hwnd: HWND, ps: *const PAINTSTRUCT) BOOL {
    if (asWindow(hwnd)) |win| if (draw_cr) |cr| flushToCairo(win, cr);
    const d = asDc(ps.hdc);
    if (d) |dd| if (dd != &screen_dc) page.destroy(dd);
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
    _ = r;
    _ = erase;
    const win = asWindow(hwnd) orelse return FALSE;
    if (win.draw_area) |da| gtk_widget_queue_draw(da);
    return TRUE;
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
    _ = flags;
    const win = asWindow(hwnd) orelse return FALSE;
    win.rect.right = w;
    win.rect.bottom = h;
    if (win.draw_area) |da| gtk_widget_set_size_request(da, w, h);
    if (win.gtk_win) |gw| gtk_widget_queue_resize(gw);
    return TRUE;
}

pub fn SetCapture(hwnd: HWND) HWND {
    const old = capture_win;
    capture_win = hwnd;
    return old;
}
pub fn ReleaseCapture() BOOL {
    capture_win = null;
    return TRUE;
}
pub fn GetCapture() HWND {
    return capture_win;
}

pub fn SetTimer(hwnd: HWND, id: usize, ms: UINT, cb: ?*anyopaque) usize {
    _ = cb;
    const win = asWindow(hwnd) orelse return 0;
    killTimerId(win, id); // 同 id 先替换（对齐 Win32 SetTimer 的覆盖语义）
    for (&win.timers) |*t| {
        if (t.active) continue;
        t.id = id;
        t.win = win;
        t.tag = g_timeout_add(ms, @ptrCast(&timerCallback), @ptrCast(t));
        t.active = true;
        return id;
    }
    return 0;
}
pub fn KillTimer(hwnd: HWND, id: usize) BOOL {
    const win = asWindow(hwnd) orelse return FALSE;
    killTimerId(win, id);
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

/// 把 Win32 风格菜单文字（UTF-16，含 & 加速键与 \t 提示）转成 GTK 标签：& → _ 助记符，截断 \t 之后。
fn storeLabel(e: *MenuEntry, label: LPCWSTR) void {
    e.label_len = 0;
    const s = label orelse return;
    var ubuf: [MAX_TEXT]u16 = [_]u16{0} ** MAX_TEXT;
    var n = copyWstr(&ubuf, s);
    if (n > MAX_TEXT - 1) n = MAX_TEXT - 1;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (ubuf[i] == 0x09) break; // 截断 \t 加速键提示
    }
    n = i;
    for (ubuf[0..n]) |*c| {
        if (c.* == 0x26) c.* = 0x5F; // & → _ 助记符
    }
    const n8 = std.unicode.utf16LeToUtf8(&e.label, ubuf[0..n]) catch return;
    e.label_len = if (n8 >= MAX_LABEL) MAX_LABEL - 1 else n8;
    e.label[e.label_len] = 0; // 兜底补 0（数组本身已零初始化）
}

pub fn AppendMenuW(menu: HMENU, flags: UINT, id_new: usize, label: LPCWSTR) BOOL {
    const m = menuPtr(menu) orelse return FALSE;
    if (m.count >= MENU_MAX) return FALSE;
    const e = &m.entries[m.count];
    if (flags & MF.SEPARATOR != 0) {
        e.* = .{ .id = 0, .sub = null, .checked = false }; // 分隔线 ID = 0（Win32 GetMenuItemID 语义）
        storeLabel(e, null);
    } else if (flags & MF.POPUP != 0) {
        const sub: *Menu = @ptrFromInt(id_new);
        e.* = .{ .id = -1, .sub = sub, .checked = false };
        storeLabel(e, label);
    } else {
        e.* = .{ .id = @intCast(@as(u32, @truncate(id_new))), .sub = null, .checked = false };
        storeLabel(e, label);
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

/// 程序化同步 checked 到 GTK 控件时置位，挡住 set_active 内部 gtk_menu_item_activate
/// 转发回来的 "activate" → onMenuActivate，避免同步——命令——同步无限递归（栈溢出）。
/// 换档 / 缩放都会走到 checkMenu → CheckMenuRadioItem → set_active，把上一位清掉时
/// set_active 会发出 activate，若不拦下来就会重入 handleCommand 再 checkMenu 一路套娃。
var menu_syncing = false;

/// 标记可复选并把 checked 同步回 GTK 控件（控件未建时只改标记，等 buildMenuBar 按状态建）。
fn syncCheck(e: *MenuEntry) void {
    e.checkable = true;
    if (e.widget) |w| {
        menu_syncing = true;
        gtk_check_menu_item_set_active(@ptrCast(w), if (e.checked) 1 else 0);
        menu_syncing = false;
    }
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
        syncCheck(&m.entries[i]);
    } else {
        for (m.entries[0..m.count]) |*e| {
            if (@as(UINT, @bitCast(e.id)) != item) continue;
            if (e.checked) old = MF.CHECKED;
            e.checked = want;
            syncCheck(e);
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
        syncCheck(e);
    }
    return TRUE;
}

pub fn EnableMenuItem(menu: HMENU, item: UINT, flags: UINT) BOOL {
    _ = menu;
    _ = item;
    _ = flags;
    return TRUE;
}

// ------------------------------------------------------------------ GTK 菜单栏
// 把菜单镜像树（AppendMenuW 存的 label / id / sub / checked）建成真 GtkMenuBar：
// 顶栏条目 = GtkMenuItem + 子菜单；命令项点一下 → WM_COMMAND(id)。
// 被 CheckMenuItem/CheckMenuRadioItem 动过的项建成 GtkCheckMenuItem 并画成圆点，
// 之后 CheckMenuItem/CheckMenuRadioItem 走 syncCheck 把 checked 同步回控件。
const MenuCmd = struct { win: *Window, id: usize };

fn zLabel(e: *const MenuEntry) [*:0]const u8 {
    return e.label[0..e.label_len :0].ptr;
}

fn onMenuActivate(item: ?*GtkWidget, user: ?*anyopaque) callconv(.c) void {
    _ = item;
    if (menu_syncing) return; // 程序化同步回的 activate，别当成真实点击再触发命令
    const mc: *MenuCmd = @ptrCast(@alignCast(user.?));
    if (mc.win.proc) |p| _ = p(@ptrCast(mc.win), WM.COMMAND, mc.id, 0);
}

fn populateMenu(win: *Window, m: *Menu) void {
    const gmenu: *GtkWidget = m.widget orelse return; // buildMenuBar 里已建好并挂到条目
    for (m.entries[0..m.count]) |*e| {
        if (e.sub) |sub| {
            const item = gtk_menu_item_new_with_mnemonic(zLabel(e)) orelse continue;
            e.widget = item;
            const submenu = gtk_menu_new() orelse continue;
            sub.widget = submenu;
            gtk_menu_item_set_submenu(@ptrCast(item), @ptrCast(submenu));
            populateMenu(win, sub);
            gtk_menu_shell_append(@ptrCast(gmenu), item);
        } else if (e.id == 0) {
            const sep = gtk_separator_menu_item_new() orelse continue;
            gtk_menu_shell_append(@ptrCast(gmenu), sep);
        } else {
            const it = (if (e.checkable)
                gtk_check_menu_item_new_with_mnemonic(zLabel(e))
            else
                gtk_menu_item_new_with_mnemonic(zLabel(e))) orelse continue;
            e.widget = it;
            if (e.checkable) {
                gtk_check_menu_item_set_draw_as_radio(@ptrCast(it), 1);
                gtk_check_menu_item_set_active(@ptrCast(it), if (e.checked) 1 else 0);
            }
            const mc = page.create(MenuCmd) catch continue;
            mc.* = .{ .win = win, .id = @intCast(e.id) };
            _ = g_signal_connect_data(@ptrCast(it), "activate", @ptrCast(&onMenuActivate), @ptrCast(mc), null, 0);
            gtk_menu_shell_append(@ptrCast(gmenu), it);
        }
    }
}

fn buildMenuBar(win: *Window, bar: *Menu) ?*GtkWidget {
    const mb = gtk_menu_bar_new() orelse return null;
    bar.widget = mb;
    for (bar.entries[0..bar.count]) |*e| {
        const sub = e.sub orelse continue; // 顶栏只装子菜单
        const item = gtk_menu_item_new_with_mnemonic(zLabel(e)) orelse continue;
        e.widget = item;
        const submenu = gtk_menu_new() orelse continue;
        sub.widget = submenu;
        gtk_menu_item_set_submenu(@ptrCast(item), @ptrCast(submenu));
        populateMenu(win, sub);
        gtk_menu_shell_append(@ptrCast(mb), item);
    }
    return mb;
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