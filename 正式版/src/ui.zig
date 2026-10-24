// ---------------------------------------------------------------------------
// UI 兼容层（facade）
//
// main.zig / uitest.zig 一律 @import("ui.zig")，不再直接依赖 win32.zig。
// 这里按目标平台在编译期二选一，把后端命名空间原样透传出去，
// 因此现有代码里的 w.HWND / w.FillRect / w.WM.* 等调用点无需改动。
//
//   Windows → ui_win32.zig：现有手写 Win32 绑定（行为与历史版本完全一致）
//   Linux 等 → ui_gtk.zig：GTK3 + cairo 实现同一接口（Phase 3 起落地）
//
const builtin = @import("builtin");

pub const backend = switch (builtin.os.tag) {
    .windows => @import("ui_win32.zig"),
    else => @import("ui_gtk.zig"),
};

// ------------------------------------------------------------------ 平台无关类型
// uitest.zig 用这套枚举描述鼠标输入，不再直接引用 Win32 的 WM_* 消息号。
pub const MouseMsg = enum(u32) {
    left_down,
    left_up,
    right_down,
    right_up,
    middle_down,
    middle_up,
    left_dblclk,
    right_dblclk,
    move,
};

// 可移植菜单模型：label 存 UTF-8（含 & 加速键与 \t 提示），id 是命令号或子菜单的 key，
// items 非空即子菜单。后端各自按此树建原生菜单。
pub const MenuItem = struct {
    label: []const u8 = "", // "" => 分隔线；否则为项目/子菜单标题
    id: usize = 0, // 命令 id；0 => 无命令（分隔线/子菜单标题）
    items: []const MenuItem = &.{}, // 非空 => 子菜单
};

pub usingnamespace backend;