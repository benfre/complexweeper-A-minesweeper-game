// GTK 后端占位（Phase 0）：保证 ui.zig 在非 Windows 目标下给出明确报错。
// Phase 3 起按 ui_win32.zig 的同一套符号面用 GTK3 + cairo 实现。
comptime {
    @compileError("GTK 后端尚未实现（Phase 0 只保证 Windows 后端零回归）");
}