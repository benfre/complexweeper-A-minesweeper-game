const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "cs_gtk",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    inline for (.{ "gtk-3", "gdk-3", "cairo", "gobject-2.0", "glib-2.0", "pangocairo-1.0", "pango-1.0", "gdk_pixbuf-2.0" }) |lib| {
        exe.linkSystemLibrary(lib);
    }
    b.installArtifact(exe);
}