const std = @import("std");

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const srcdir = getSrcDir();

const USE_SYSTEM_FREETYPE = false;
pub const ToLink = enum {
    freetype,
    lua,
    openal,
};
pub fn linkLibrary(b: *std.Build, mod: *std.Build.Module, tolink: []const ToLink) !void {
    const cdir = "c_libs";

    const include_paths = [_][]const u8{
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
        //cdir ++ "/stb_truetype.c",
        cdir ++ "/libspng/spng/spng.c",
        cdir ++ "/miniz/miniz.c",
        cdir ++ "/miniz/miniz_zip.c",
        cdir ++ "/miniz/miniz_tinfl.c",
        cdir ++ "/miniz/miniz_tdef.c",
    };

    for (c_source_files) |cfile| {
        mod.addCSourceFile(.{ .file = b.path(cfile), .flags = &[_][]const u8{
            "-Wall",
            "-DSPNG_USE_MINIZ=",
            "-DMINIZ_NO_ARCHIVE_APIS=",
            "-DMINIZ_NO_ARCHIVE_WRITING_APIS=",
            "-DMINIZ_NO_STDIO=",
            "-DMINIZ_NO_TIME=",
        } });
    }
    try freetype(b, mod);
    mod.link_libc = true;
    if (mod.resolved_target) |rt| {
        if (rt.result.os.tag == .windows) {
            if (USE_SYSTEM_FREETYPE) {
                mod.addSystemIncludePath(.{ .cwd_relative = "/mingw64/include/freetype2" });
                mod.linkSystemLibrary("freetype.dll", .{});
            } else {
                //mod.addIncludePath(b.path(cdir ++ "/freetype_build/buildwin"));
                //mod.addObjectFile(b.path(cdir ++ "/freetype_build/buildwin/libfreetype.a"));
            }

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
                    //mod.addObjectFile(b.path(cdir ++ "/freetype_build/build/libfreetype.a"));
                    continue;
                }
                mod.linkSystemLibrary(str, .{ .preferred_link_mode = .static });
            }
        }
    }

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.5",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive, .EXT_texture_compression_s3tc },
    });

    mod.addImport("gl", gl_bindings);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardOptimizeOption(.{});
    const build_gui = b.option(bool, "gui", "Build the gui test app") orelse true;

    const bake = b.addExecutable(.{
        .name = "assetbake",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/assetbake.zig"),
            .target = target,
            .optimize = mode,
        }),
    });
    b.installArtifact(bake);
    const to_link = [_]ToLink{ .freetype, .openal, .lua };
    try linkLibrary(b, bake.root_module, &to_link);

    const exe = b.addExecutable(.{
        .name = "the_engine",
        .root_module = b.createModule(.{
            .root_source_file = if (build_gui) b.path("src/rgui_test.zig") else b.path("src/main.zig"),
            .target = target,
            .optimize = mode,
        }),
        //.use_llvm = true,
    });
    b.installArtifact(exe);

    try linkLibrary(b, exe.root_module, &to_link);
    const m = b.addModule("ratgraph", .{ .root_source_file = b.path("src/graphics.zig"), .target = target });
    try linkLibrary(b, m, &.{.freetype});

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = mode,
            .link_libc = true,
        }),
    });
    unit_tests.setExecCmd(&[_]?[]const u8{ "kcov", "kcov-output", null });
    try linkLibrary(b, unit_tests.root_module, &to_link);

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

fn freetype(b: *std.Build, mod: *std.Build.Module) !void {
    // adapted from allyourcodebase/freetype
    const srcs: []const []const u8 = &.{
        "autofit/autofit.c",
        "base/ftbase.c",
        "base/ftbbox.c",
        "base/ftbdf.c",
        "base/ftbitmap.c",
        "base/ftcid.c",
        "base/ftfstype.c",
        "base/ftgasp.c",
        "base/ftglyph.c",
        "base/ftgxval.c",
        "base/ftinit.c",
        "base/ftmm.c",
        "base/ftotval.c",
        "base/ftpatent.c",
        "base/ftpfr.c",
        "base/ftstroke.c",
        "base/ftsynth.c",
        "base/fttype1.c",
        "base/ftwinfnt.c",
        "bdf/bdf.c",
        "bzip2/ftbzip2.c",
        "cache/ftcache.c",
        "cff/cff.c",
        "cid/type1cid.c",
        "gzip/ftgzip.c",
        "lzw/ftlzw.c",
        "pcf/pcf.c",
        "pfr/pfr.c",
        "psaux/psaux.c",
        "pshinter/pshinter.c",
        "psnames/psnames.c",
        "raster/raster.c",
        "sdf/sdf.c",
        "sfnt/sfnt.c",
        "smooth/smooth.c",
        "svg/svg.c",
        "truetype/truetype.c",
        "type1/type1.c",
        "type42/type42.c",
        "winfonts/winfnt.c",
    };

    var flags: std.ArrayList([]const u8) = .empty;
    defer flags.deinit(b.allocator);

    try flags.appendSlice(b.allocator, &.{
        "-DFT2_BUILD_LIBRARY",
        "-DHAVE_UNISTD_H",
        "-DHAVE_FCNTL_H",
        "-fno-sanitize=undefined",
    });

    mod.addCSourceFiles(.{
        .root = b.path("c_libs/freetype_build/src"),
        .files = srcs,
        .flags = flags.items,
    });

    if (mod.resolved_target) |rt| {
        switch (rt.result.os.tag) {
            .windows => {
                mod.addCSourceFile(.{
                    .file = b.path("c_libs/freetype_build/builds/windows/ftsystem.c"),
                    .flags = flags.items,
                });
            },
            .linux => mod.addCSourceFile(.{ .file = b.path("c_libs/freetype_build/builds/unix/ftsystem.c"), .flags = flags.items }),
            else => mod.addCSourceFile(.{ .file = b.path("c_libs/freetype_build/src/base/ftsystem.c"), .flags = flags.items }),
        }
        switch (rt.result.os.tag) {
            else => mod.addCSourceFile(.{ .file = b.path("c_libs/freetype_build/src/base/ftdebug.c"), .flags = flags.items }),
            .windows => {
                mod.addCSourceFile(.{
                    .file = b.path("c_libs/freetype_build/builds/windows/ftdebug.c"),
                    .flags = flags.items,
                });
                mod.addWin32ResourceFile(.{
                    .file = b.path("c_libs/freetype_build/src/base/ftver.rc"),
                });
            },
        }
    }
}
