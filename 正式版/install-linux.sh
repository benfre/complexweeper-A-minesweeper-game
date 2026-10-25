#!/usr/bin/env bash
# --- help:start ---
# 复扫雷 Complexweeper · Linux 安装脚本
# 默认装到用户目录（~/.local，无需 root）；用 PREFIX=/usr 或 --prefix=/usr 装到系统目录。
# 装三样东西：可执行文件、图标 PNG（hicolor 图标主题 + pixmaps）、.desktop 菜单项。
# 源码目录和 Release 解压包都能跑：前者可现场生成图标/编译，后者自带二进制、图标与本脚本。
#
# 用法:
#   ./install-linux.sh                  # 源码目录：装 zig-out/bin/cs_gtk
#   ./install-linux.sh --build          # 源码目录：先 gen_atlas + zig build 再装
#   ./install-linux.sh ./某个二进制     # 装指定二进制
#   ./install-linux.sh --prefix=/usr    # 装到 /usr（需要 root）
#   ./install-linux.sh --uninstall      # 卸掉（按之前的 PREFIX）
#   （Release 包：解压后直接 ./install-linux.sh，无需 node/zig）
#
# 说明：Linux 下程序图标不在可执行文件里（不像 Windows 把 .ico 注进 PE 资源），
# 得靠安装时落成独立 PNG，再由 .desktop 的 Icon= 字段引用。见 tools/make_icon_png.js。
# --- help:end ---
set -euo pipefail

# 先记住脚本自身的绝对路径：后面会 cd 进 SCRIPT_DIR，相对路径的 $0 就失效了（--help 要用它）
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SELF_PATH")"
cd "$SCRIPT_DIR"

APP="complexweeper"
# 版本号优先读源码；Release 包里没有源码，退到 VERSION 文件（都没有就留空）
VERSION=""
if [ -f "src/main.zig" ]; then
  VERSION="$(sed -n 's/.*const APP_VERSION = "\([0-9.]*\)";.*/\1/p' src/main.zig | head -1)"
fi
[ -n "$VERSION" ] || VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || true)"
SIZES="32 48 64 128 256"

PREFIX="${PREFIX:-$HOME/.local}"
BIN_SRC=""
DO_BUILD=0
DO_UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --build)       DO_BUILD=1 ;;
    --uninstall)   DO_UNINSTALL=1 ;;
    --prefix=*)    PREFIX="${1#*=}" ;;
    -h|--help)     sed -n '/^# --- help:start ---$/,/^# --- help:end ---$/p' "$SELF_PATH" | sed '1d;$d;s/^# \{0,1\}//'; exit 0 ;;
    *)             BIN_SRC="$1" ;;
  esac
  shift
done

# 去尾部斜杠，保证拼路径不出「//」
PREFIX="${PREFIX%/}"
[ -n "$PREFIX" ] || PREFIX="$HOME/.local"

BIN_DIR="$PREFIX/bin"
ICON_THEME="$PREFIX/share/icons/hicolor"
APPS_DIR="$PREFIX/share/applications"
PIXMAPS_DIR="$PREFIX/share/pixmaps"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少依赖：$1" >&2; exit 1; }; }

uninstall() {
  echo "卸载 $APP（PREFIX=$PREFIX）"
  rm -f "$BIN_DIR/$APP" \
        "$APPS_DIR/$APP.desktop" \
        "$PIXMAPS_DIR/$APP.png"
  for s in $SIZES; do rm -f "$ICON_THEME/${s}x${s}/apps/$APP.png"; done
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$ICON_THEME" 2>/dev/null || true
  echo "完成。"
  exit 0
}
[ "$DO_UNINSTALL" = 1 ] && uninstall

# ---- 1) 找到（或构建）可执行文件 ----
if [ -z "$BIN_SRC" ]; then
  if [ "$DO_BUILD" = 1 ]; then
    echo "生成图集 + 编译…"
    need node
    need zig
    node tools/gen_atlas.js
    zig build
    BIN_SRC="zig-out/bin/cs_gtk"
  elif [ -x "zig-out/bin/cs_gtk" ]; then
    BIN_SRC="zig-out/bin/cs_gtk"
  elif [ -x "$SCRIPT_DIR/$APP" ]; then
    BIN_SRC="$SCRIPT_DIR/$APP"          # Release 包：二进制就放在脚本旁边
  else
    echo "找不到二进制：请先 zig build、加 --build，或到 Release 解压包根目录里跑本脚本。" >&2
    exit 1
  fi
fi
[ -f "$BIN_SRC" ] || { echo "找不到二进制：$BIN_SRC" >&2; exit 1; }

# ---- 2) 找到（或生成）图标 PNG ----
icons_ready() { local d="$1"; for s in $SIZES; do [ -f "$d/$APP-${s}.png" ] || return 1; done; }
ICON_DIR=""
if icons_ready "$SCRIPT_DIR/icons"; then
  ICON_DIR="$SCRIPT_DIR/icons"       # Release 包：icons/ 就在脚本旁边
elif icons_ready "build/icons"; then
  ICON_DIR="build/icons"
else
  need node
  echo "生成图标 PNG…"
  node tools/make_icon_png.js "build/icons" $SIZES
  ICON_DIR="build/icons"
fi

# ---- 3) 装可执行文件 ----
mkdir -p "$BIN_DIR"
install -m 0755 "$BIN_SRC" "$BIN_DIR/$APP"

# ---- 4) 装图标（hicolor 各尺寸 + pixmaps 兜底）----
for s in $SIZES; do
  mkdir -p "$ICON_THEME/${s}x${s}/apps"
  install -m 0644 "$ICON_DIR/$APP-${s}.png" "$ICON_THEME/${s}x${s}/apps/$APP.png"
done
mkdir -p "$PIXMAPS_DIR"
install -m 0644 "$ICON_DIR/$APP-256.png" "$PIXMAPS_DIR/$APP.png"

# ---- 5) 写 .desktop 菜单项 ----
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/$APP.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=复扫雷
GenericName=Minesweeper
Comment=扫雷，但雷是复数
Comment[en]=Minesweeper where the mines are complex numbers
Exec=$BIN_DIR/$APP
Icon=$APP
Terminal=false
Categories=Game;LogicGame;
EOF

# ---- 6) 刷新菜单/图标缓存（能刷新才刷新，非系统级写不进也不报错）----
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$ICON_THEME" 2>/dev/null || true

echo
echo "安装完成：$APP ${VERSION:-}"
echo "  程序      $BIN_DIR/$APP"
echo "  图标      $ICON_THEME/{32,48,64,128,256}x…/apps/$APP.png  +  $PIXMAPS_DIR/$APP.png"
echo "  菜单项    $APPS_DIR/$APP.desktop"
echo "卸载：$0 --uninstall${PREFIX:+ --prefix=$PREFIX}"