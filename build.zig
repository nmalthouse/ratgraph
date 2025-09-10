const std = @import("std");

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const srcdir = getSrcDir();

//const LUA_SRC: ?[]const u8 = "lua5.4.7/src/";
const LUA_SRC = null;

const USE_SYSTEM_FREETYPE = false;

pub const ToLink = enum {
    freetype,
    lua,
    openal,
};
pub fn linkLibrary(b: *std.Build, mod: *std.Build.Module, tolink: []const ToLink) void {
    const cdir = "c_libs";

    const include_paths = [_][]const u8{
        cdir ++ "/libepoxy/include",
        cdir ++ "/libepoxy/build/include",
        cdir ++ "/miniz/build",
        cdir ++ "/miniz",
        cdir ++ "/freetype",
        cdir ++ "/stb",
        cdir,
        cdir ++ "/libspng/spng",
    };

    for (include_paths) |path| {
        mod.addIncludePath(b.path(path));
    }
    if (!USE_SYSTEM_FREETYPE) {
        mod.addIncludePath(b.path(cdir ++ "/freetype_build/include"));
    }

    const c_source_files = [_][]const u8{
        cdir ++ "/stb_image_write.c",
        cdir ++ "/stb_image.c",
        cdir ++ "/stb/stb_vorbis.c",
        cdir ++ "/stb_rect_pack.c",
        cdir ++ "/stb_truetype.c",
        cdir ++ "/libspng/spng/spng.c",
        cdir ++ "/miniz/miniz.c",
        cdir ++ "/miniz/miniz_zip.c",
        cdir ++ "/miniz/miniz_tinfl.c",
        cdir ++ "/miniz/miniz_tdef.c",
    };

    if (LUA_SRC) |lsrc| {
        const paths = [_][]const u8{ "lapi.c", "lauxlib.c", "lbaselib.c", "lcode.c", "lcorolib.c", "lctype.c", "ldblib.c", "ldebug.c", "ldo.c", "ldump.c", "lfunc.c", "lgc.c", "linit.c", "liolib.c", "llex.c", "lmathlib.c", "lmem.c", "loadlib.c", "lobject.c", "lopcodes.c", "loslib.c", "lparser.c", "lstate.c", "lstring.c", "lstrlib.c", "ltable.c", "ltablib.c", "ltm.c", "lundump.c", "lutf8lib.c", "lvm.c", "lzio.c" };
        inline for (paths) |p| {
            mod.addCSourceFile(.{ .file = b.path(lsrc ++ p), .flags = &[_][]const u8{"-Wall"} });
        }
    }

    for (c_source_files) |cfile| {
        mod.addCSourceFile(.{ .file = b.path(cfile), .flags = &[_][]const u8{ "-Wall", "-DSPNG_USE_MINIZ=" } });
    }
    mod.link_libc = true;
    if (mod.resolved_target) |rt| {
        if (rt.result.os.tag == .windows) {
            if (USE_SYSTEM_FREETYPE) {
                mod.addSystemIncludePath(.{ .cwd_relative = "/mingw64/include/freetype2" });
                mod.linkSystemLibrary("freetype.dll", .{});
            } else {
                mod.addIncludePath(b.path(cdir ++ "/freetype_build/buildwin"));
                mod.addObjectFile(b.path(cdir ++ "/freetype_build/buildwin/libfreetype.a"));
            }

            mod.addObjectFile(b.path(cdir ++ "/libepoxy/buildwin/src/libepoxy.a"));

            //These all come from sdl/buildwin/sdl3.pc
            mod.linkSystemLibrary("m", .{});
            mod.linkSystemLibrary("kernel32", .{});
            mod.linkSystemLibrary("user32", .{});
            mod.linkSystemLibrary("gdi32", .{});
            mod.linkSystemLibrary("winmm", .{});
            mod.linkSystemLibrary("imm32", .{});
            mod.linkSystemLibrary("ole32", .{});
            mod.linkSystemLibrary("oleaut32", .{});
            mod.linkSystemLibrary("version", .{});
            mod.linkSystemLibrary("uuid", .{});
            mod.linkSystemLibrary("advapi32", .{});
            mod.linkSystemLibrary("setupapi", .{});
            mod.linkSystemLibrary("shell32", .{});
            mod.linkSystemLibrary("dinput", .{});
        } else {
            mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });

            if (USE_SYSTEM_FREETYPE) {
                mod.addSystemIncludePath(.{ .cwd_relative = "/usr/include/freetype2" });
            } else {
                mod.addIncludePath(b.path(cdir ++ "/freetype_build/build"));
            }
            for (tolink) |tl| {
                const str = switch (tl) {
                    .lua => "lua",
                    .freetype => "freetype",
                    .openal => "openal",
                };
                if (tl == .freetype and !USE_SYSTEM_FREETYPE) {
                    mod.addObjectFile(b.path(cdir ++ "/freetype_build/build/libfreetype.a"));
                    //mod.linkSystemLibrary("bzip2", .{});
                    continue;
                }
                mod.linkSystemLibrary(str, .{ .preferred_link_mode = .static });
            }
            mod.addObjectFile(b.path(cdir ++ "/libepoxy/build/src/libepoxy.a"));
            //mod.linkSystemLibrary("epoxy", .{});
            //mod.linkSystemLibrary("z", .{});
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardOptimizeOption(.{});
    const build_gui = b.option(bool, "gui", "Build the gui test app") orelse true;

    const bake = b.addExecutable(.{
        .name = "assetbake",
        .root_source_file = b.path("src/assetbake.zig"),
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(bake);
    const to_link = [_]ToLink{ .freetype, .openal, .lua };
    linkLibrary(b, bake.root_module, &to_link);

    const exe = b.addExecutable(.{
        .name = "the_engine",
        .root_source_file = if (build_gui) b.path("src/rgui_test.zig") else b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(exe);

    linkLibrary(b, exe.root_module, &to_link);
    const m = b.addModule("ratgraph", .{ .root_source_file = b.path("src/graphics.zig"), .target = target });
    linkLibrary(b, m, &.{.freetype});

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = mode,
        .link_libc = true,
    });
    unit_tests.setExecCmd(&[_]?[]const u8{ "kcov", "kcov-output", null });
    linkLibrary(b, unit_tests.root_module, &to_link);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = mode,
    });

    const zalgebra_module = zalgebra_dep.module("zalgebra");
    exe.root_module.addImport("zalgebra", zalgebra_module);
    bake.root_module.addImport("zalgebra", zalgebra_module);
    unit_tests.root_module.addImport("zalgebra", zalgebra_module);
    m.addImport("zalgebra", zalgebra_module);

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = .ReleaseFast,
        .preferred_linkage = .static,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
        //.install_build_config_h = false,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    m.linkLibrary(sdl_lib);
    exe.root_module.linkLibrary(sdl_lib);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
