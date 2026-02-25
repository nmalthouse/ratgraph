const std = @import("std");

fn getSrcDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const srcdir = getSrcDir();

pub fn linkLibrary(b: *std.Build, mod: *std.Build.Module) !void {
    const cdir = "c_libs";
    const vend = "c_libs/vendored";

    const include_paths = [_][]const u8{
        vend ++ "/miniz",
        vend ++ "/stb",
        cdir,
        vend ++ "/libspng",
        vend,
    };

    for (include_paths) |path| {
        mod.addIncludePath(b.path(path));
    }

    const c_source_files = [_][]const u8{
        //cdir ++ "/stb_image_write.c",
        //cdir ++ "/stb_image.c",
        cdir ++ "/stb_rect_pack.c",
        vend ++ "/libspng/spng.c",

        vend ++ "/miniz/miniz.c",
        vend ++ "/miniz/miniz_zip.c",
        vend ++ "/miniz/miniz_tinfl.c",
        vend ++ "/miniz/miniz_tdef.c",
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
            //TODO on wine, all is well without linking these, verify this is true on actual Windows

            //These all come from sdl/buildwin/sdl3.pc
            // mod.linkSystemLibrary("m", .{});
            // mod.linkSystemLibrary("kernel32", .{});
            // mod.linkSystemLibrary("user32", .{});
            // mod.linkSystemLibrary("gdi32", .{});
            // mod.linkSystemLibrary("winmm", .{});
            // mod.linkSystemLibrary("imm32", .{});
            // mod.linkSystemLibrary("ole32", .{});
            // mod.linkSystemLibrary("oleaut32", .{});
            // mod.linkSystemLibrary("version", .{});
            // mod.linkSystemLibrary("uuid", .{});
            // mod.linkSystemLibrary("advapi32", .{});
            // mod.linkSystemLibrary("setupapi", .{});
            // mod.linkSystemLibrary("shell32", .{});
            // mod.linkSystemLibrary("dinput", .{});
        } else {
            //mod.addIncludePath(b.path(cdir ++ "/freetype_build/build"));
        }
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardOptimizeOption(.{});
    const build_gui = b.option(bool, "gui", "Build the gui test app") orelse true;
    const strip = mode == .ReleaseFast;

    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = mode,
    });
    const zalgebra_module = zalgebra_dep.module("zalgebra");

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.5",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive, .EXT_texture_compression_s3tc },
    });

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = .ReleaseFast,
        .preferred_linkage = .static,
        .strip = strip,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    const m = b.addModule("ratgraph", .{
        .root_source_file = b.path("src/graphics.zig"),
        .target = target,
    });
    try linkLibrary(b, m);
    m.addImport("zalgebra", zalgebra_module);
    m.linkLibrary(sdl_lib);
    m.addImport("gl", gl_bindings);

    const bake = b.addExecutable(.{
        .name = "assetbake",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/assetbake.zig"),
            .target = target,
            .optimize = mode,
            .strip = strip,
        }),
    });
    b.installArtifact(bake);
    try linkLibrary(b, bake.root_module);
    bake.root_module.addImport("zalgebra", zalgebra_module);

    const exe = b.addExecutable(.{
        .name = "the_engine",
        .root_module = b.createModule(.{
            .root_source_file = if (build_gui) b.path("src/rgui_test.zig") else b.path("src/main.zig"),
            .target = target,
            .optimize = mode,
            .strip = strip,
        }),
    });
    {
        b.installArtifact(exe);
        try linkLibrary(b, exe.root_module);
        exe.root_module.addImport("zalgebra", zalgebra_module);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "run app");
        run_step.dependOn(&run_cmd.step);
        exe.root_module.linkLibrary(sdl_lib);
        exe.root_module.addImport("gl", gl_bindings);
    }

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = mode,
            .link_libc = true,
        }),
        .use_llvm = true, //Kcov can't test binaries using zig backend
    });
    {
        unit_tests.setExecCmd(&[_]?[]const u8{ "kcov", "--clean", "--include-pattern=ratgraph/src", "/tmp/kcov-output", null });
        try linkLibrary(b, unit_tests.root_module);
        unit_tests.root_module.linkLibrary(sdl_lib);

        const run_unit_tests = b.addRunArtifact(unit_tests);

        unit_tests.root_module.addImport("zalgebra", zalgebra_module);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
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
    mod.addIncludePath(b.path("c_libs/freetype_build/include"));
    mod.addIncludePath(b.path("c_libs/freetype"));

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
