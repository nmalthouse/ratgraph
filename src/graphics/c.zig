pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("freetype_init.h");

    @cDefine("SPNG_USE_MINIZ", "");
    @cInclude("spng.h");

    //@cInclude("AL/al.h");
    //@cInclude("AL/alc.h");
    //@cInclude("vorbis/codec.h");
    //@cInclude("vorbis/vorbisfile.h");

    //Static
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_vorbis.h");

    @cDefine("STBI_NO_STDIO", {});
    @cDefine("STBI_ONLY_JPEG", {});
    @cInclude("stb_image.h");

    @cDefine("STBI_WRITE_NO_STDIO", {});
    @cInclude("stb_image_write.h");

    @cDefine("QOI_NO_STDIO", {});
    @cDefine("QOI_IMPLEMENTATION", {});
    @cInclude("qoi/qoi.h");
});
