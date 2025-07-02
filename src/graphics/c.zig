pub usingnamespace @cImport({
    //DLLs
    //@cInclude("SDL3/SDL_main.h"); //Not sure
    @cInclude("SDL3/SDL.h");
    @cInclude("epoxy/gl.h");
    @cInclude("freetype_init.h");
    @cInclude("spng.h");

    //@cInclude("AL/al.h");
    //@cInclude("AL/alc.h");
    //@cInclude("vorbis/codec.h");
    //@cInclude("vorbis/vorbisfile.h");

    //Static
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_vorbis.h");
    @cInclude("stb_image.h");
    @cInclude("stb_truetype.h");
    @cInclude("stb_image_write.h");
});
