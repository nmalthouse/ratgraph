pub const c = @cImport({
    @cInclude("SDL3/SDL.h");

    //@cDefine("STBI_NO_STDIO", {});
    //@cDefine("STBI_ONLY_JPEG", {});
    //@cInclude("stb_image.h");

    //@cDefine("STBI_WRITE_NO_STDIO", {});
    //@cInclude("stb_image_write.h");
});

pub const ft = @cImport({
    @cInclude("freetype_init.h");
});

pub const stb_rp = @cImport({
    @cInclude("stb_rect_pack.h");
});

pub const spng = @cImport({
    @cDefine("SPNG_USE_MINIZ", {});
    @cInclude("spng.h");
});

pub const qoi = @cImport({
    @cDefine("QOI_NO_STDIO", {});
    @cDefine("QOI_IMPLEMENTATION", {});
    @cInclude("qoi/qoi.h");
});

pub const miniz = @cImport({
    @cInclude("miniz.h");
});

pub const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});
