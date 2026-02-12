const std = @import("std");
const graph = @import("graphics.zig");
const glID = graph.glID;
const c = graph.c;
const GL = graph.GL;
const Mat4 = graph.za.Mat4;
const Vec3 = graph.za.Vec3;
const DrawCtx = graph.ImmediateDrawingContext;
const mesh = graph.meshutil;
const util3d = @import("util_3d.zig");
const gl = graph.gl;

pub const DrawCall = struct {
    prim: GL.PrimitiveMode,
    num_elements: c_int,
    element_type: c_uint,
    vao: c_uint,
    //view: *const Mat4,
    diffuse: c_uint,
    blend: glID = 0,
    bump: glID = 0,
    model: ?Mat4 = null,
};
const SunQuadBatch = graph.NewBatch(packed struct { pos: graph.Vec3f, uv: graph.Vec2f }, .{ .index_buffer = false, .primitive_mode = .triangles });
const SkyBatch = graph.NewBatch(graph.ImmediateDrawingContext.VtxFmt.Textured_3D_NC, .{ .index_buffer = true, .primitive_mode = .triangles });

pub const Renderer = struct {
    const Self = @This();
    shader: struct {
        csm: glID,
        forward: glID,
        gbuffer: glID,
        light: glID,
        spot: glID,
        sun: glID,
        decal: glID,
        hdr: glID,
        skybox: glID,
    },
    mode: enum { forward, def } = .forward,
    gbuffer: GBuffer,
    hdrbuffer: HdrBuffer,
    csm: Csm,

    last_frame_draw_call_count: usize = 0,

    alloc: std.mem.Allocator,
    draw_calls: std.ArrayList(DrawCall) = .{},
    last_frame_view_mat: Mat4 = undefined,
    sun_batch: SunQuadBatch,
    point_light_batch: PointLightInstanceBatch,
    spot_light_batch: SpotLightInstanceBatch,
    decal_batch: DecalBatch,
    sky_meshes: [6]SkyBatch,

    ambient: [4]f32 = [4]f32{ 1, 1, 1, 255 },
    ambient_scale: f32 = 1,
    exposure: f32 = 3.5,
    gamma: f32 = 1.45,
    pitch: f32 = 35,
    yaw: f32 = 165,
    sun_color: [4]f32 = [4]f32{ 1, 1, 1, 255 },
    do_lighting: bool = true,
    do_decals: bool = true,
    do_skybox: bool = true,
    debug_light_coverage: bool = false,
    copy_depth: bool = true,
    light_render_dist: f32 = 1024 * 2,
    /// Halfs the number of draw calls if enabled
    omit_model_shadow: bool = true,

    res_scale: f32 = 1,

    do_hdr_buffer: bool = true,

    pub fn init(alloc: std.mem.Allocator, shader_dir: std.fs.Dir) !Self {
        const shadow_shader = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "shadow_map.vert", .t = .vert },
            .{ .path = "shadow_map.frag", .t = .frag },
            .{ .path = "shadow_map.geom", .t = .geom },
        });
        const forward = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "basic.vert", .t = .vert },
            .{ .path = "basic.frag", .t = .frag },
        });
        const gbuffer_shader = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "gbuffer_model.vert", .t = .vert },
            .{ .path = "gbuffer_model.frag", .t = .frag },
        });
        const light_shader = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "light.vert", .t = .vert },
            .{ .path = "light_debug.frag", .t = .frag },
        });
        const spot_light_shader = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "spot_light.vert", .t = .vert },
            .{ .path = "spot_light.frag", .t = .frag },
        });
        const def_sun_shad = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "sun.vert", .t = .vert },
            .{ .path = "sun.frag", .t = .frag },
        });
        const decal_shad = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{
            .{ .path = "decal.vert", .t = .vert },
            .{ .path = "decal.frag", .t = .frag },
        });
        const sky_shad = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{ .{ .path = "cubemap.vert", .t = .vert }, .{ .path = "cubemap.frag", .t = .frag } });
        const hdr_shad = try graph.Shader.loadFromFilesystem(alloc, shader_dir, &.{ .{ .path = "hdr.vert", .t = .vert }, .{ .path = "hdr.frag", .t = .frag } });
        var sun_batch = SunQuadBatch.init(alloc);
        _ = sun_batch.clear();
        sun_batch.appendVerts(&.{
            .{ .pos = graph.Vec3f.new(-1, 1, 0), .uv = graph.Vec2f.new(0, 1) },
            .{ .pos = graph.Vec3f.new(-1, -1, 0), .uv = graph.Vec2f.new(0, 0) },
            .{ .pos = graph.Vec3f.new(1, 1, 0), .uv = graph.Vec2f.new(1, 1) },
            .{ .pos = graph.Vec3f.new(1, -1, 0), .uv = graph.Vec2f.new(1, 0) },
        });
        sun_batch.pushVertexData();
        return Self{
            .shader = .{
                .csm = shadow_shader,
                .forward = forward,
                .gbuffer = gbuffer_shader,
                .light = light_shader,
                .spot = spot_light_shader,
                .decal = decal_shad,
                .sun = def_sun_shad,
                .hdr = hdr_shad,
                .skybox = sky_shad,
            },
            .point_light_batch = try PointLightInstanceBatch.init(alloc, shader_dir, "icosphere.obj"),
            .spot_light_batch = try SpotLightInstanceBatch.init(alloc, shader_dir, "cone.obj"),
            .decal_batch = try DecalBatch.init(alloc, shader_dir, "cube.obj"),
            .sun_batch = sun_batch,
            .alloc = alloc,
            .csm = Csm.createCsm(2048, Csm.CSM_COUNT, def_sun_shad),
            .gbuffer = GBuffer.create(100, 100),
            .hdrbuffer = HdrBuffer.create(100, 100),
            .sky_meshes = initSkyboxMeshes(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.draw_calls.deinit(self.alloc);
        self.sun_batch.deinit();
        self.point_light_batch.deinit();
        self.spot_light_batch.deinit();
        self.decal_batch.deinit();

        for (&self.sky_meshes) |*sk| {
            sk.deinit();
        }
    }

    pub fn beginFrame(self: *Self) void {
        self.last_frame_draw_call_count = self.draw_calls.items.len;
        self.draw_calls.clearRetainingCapacity();
    }

    pub fn countDCall(self: *Self) void {
        self.last_frame_draw_call_count += 1;
    }

    pub fn clearLights(self: *Self) void {
        self.point_light_batch.clear();
        self.spot_light_batch.clear();
        self.decal_batch.clear();
    }

    pub fn submitDrawCall(self: *Self, d: DrawCall) !void {
        try self.draw_calls.append(self.alloc, d);
    }

    pub fn draw(
        self: *Self,
        cam: graph.Camera3D,
        screen_area: graph.Rect,
        screen_dim: graph.Vec2f,
        param: struct {
            fac: f32,
            pad: f32,
            index: usize,
        },
        dctx: *DrawCtx,
        pl: anytype,
    ) !void {
        self.point_light_batch.pushVertexData();
        self.spot_light_batch.pushVertexData();
        self.decal_batch.pushVertexData();
        const view1 = cam.getMatrix(screen_area.w / screen_area.h);
        self.csm.pad = param.pad;
        switch (self.mode) {
            .forward => {
                const view = view1;
                const sh = self.shader.forward;
                gl.UseProgram(sh);
                GL.passUniform(sh, "view", view);
                for (self.draw_calls.items) |dc| {
                    if (dc.diffuse != 0) {
                        const diffuse_loc = gl.GetUniformLocation(sh, "diffuse_texture");

                        gl.Uniform1i(diffuse_loc, 0);
                        gl.BindTextureUnit(0, dc.diffuse);
                    }
                    if (dc.blend != 0) {
                        const blend_loc = gl.GetUniformLocation(sh, "blend_texture");
                        gl.Uniform1i(blend_loc, 1);
                        gl.BindTextureUnit(1, dc.blend);
                    }
                    GL.passUniform(sh, "model", if (dc.model) |mod| mod else Mat4.identity());
                    gl.BindVertexArray(dc.vao);
                    gl.DrawElements(@intFromEnum(dc.prim), dc.num_elements, dc.element_type, 0);
                }
            },
            .def => {
                const view = if (param.index == 0) view1 else self.csm.mats[(param.index - 1) % self.csm.mats.len];
                self.last_frame_view_mat = cam.getViewMatrix();
                var light_dir = Vec3.new(@sin(std.math.degreesToRadians(35)), 0, @sin(std.math.degreesToRadians(165))).norm();
                {
                    light_dir = util3d.eulerToNormal(Vec3.new(self.pitch, self.yaw + 180, 0)).scale(1);
                }
                const planes = [_]f32{
                    pl[0],
                    pl[1],
                    pl[2],
                };
                const last_plane = pl[3];
                self.csm.calcMats(cam.fov, screen_area.w / screen_area.h, cam.near, cam.far, self.last_frame_view_mat, light_dir, planes);
                self.csm.draw(self);
                self.gbuffer.updateResolution(@intFromFloat(screen_area.w * self.res_scale), @intFromFloat(screen_area.h * self.res_scale));
                if (self.do_hdr_buffer)
                    self.hdrbuffer.updateResolution(@intFromFloat(screen_area.w * self.res_scale), @intFromFloat(screen_area.h * self.res_scale));
                gl.BindFramebuffer(gl.FRAMEBUFFER, self.gbuffer.buffer);
                gl.Viewport(0, 0, self.gbuffer.scr_w, self.gbuffer.scr_h);
                gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
                { //Write to gbuffer
                    const gbuf_sh = self.shader.gbuffer;
                    gl.UseProgram(gbuf_sh);
                    const diffuse_loc = gl.GetUniformLocation(gbuf_sh, "diffuse_texture");
                    const diff_slot = 0;
                    const blend_slot = 1;
                    const blend_loc = gl.GetUniformLocation(gbuf_sh, "blend_texture");

                    const norm_slot = 2;
                    const norm_loc = gl.GetUniformLocation(gbuf_sh, "normal_texture");

                    gl.Uniform1i(diffuse_loc, diff_slot);
                    gl.Uniform1i(blend_loc, blend_slot);
                    gl.Uniform1i(norm_loc, norm_slot);
                    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, self.csm.mat_ubo);
                    for (self.draw_calls.items) |dc| {
                        gl.BindTextureUnit(diff_slot, dc.diffuse);
                        if (dc.blend != 0) {
                            gl.BindTextureUnit(blend_slot, dc.blend);
                        }
                        gl.BindTextureUnit(norm_slot, dc.bump);
                        GL.passUniform(gbuf_sh, "do_normal", dc.bump != 0);
                        GL.passUniform(gbuf_sh, "view", view);
                        //GL.passUniform(gbuf_sh, "model", Mat4.identity());
                        GL.passUniform(gbuf_sh, "model", if (dc.model) |mod| mod else Mat4.identity());
                        gl.BindVertexArray(dc.vao);
                        gl.DrawElements(@intFromEnum(dc.prim), dc.num_elements, dc.element_type, 0);
                    }
                }
                if (self.do_decals) {
                    self.drawDecal(cam, graph.Vec2i{ .x = self.gbuffer.scr_w, .y = self.gbuffer.scr_h }, view, .{ .x = 0, .y = 0 }, cam.far);
                }
                const y_: i32 = @intFromFloat(screen_dim.y - (screen_area.y + screen_area.h));
                if (self.do_hdr_buffer) {
                    gl.BindFramebuffer(gl.FRAMEBUFFER, self.hdrbuffer.fb);
                    gl.Clear(gl.COLOR_BUFFER_BIT);
                    gl.ClearColor(0, 0, 0, 0);
                } else {
                    self.bindMainFramebufferAndVp(screen_area, screen_dim);
                }

                const scrsz = if (self.do_hdr_buffer) graph.Vec2i{ .x = self.gbuffer.scr_w, .y = self.gbuffer.scr_h } else graph.Vec2i{ .x = @intFromFloat(screen_area.w), .y = @intFromFloat(screen_area.h) };
                const win_offset = if (self.do_hdr_buffer) graph.Vec2i{ .x = 0, .y = 0 } else graph.Vec2i{ .x = @intFromFloat(screen_area.x), .y = y_ };
                { //Draw sun
                    gl.DepthMask(gl.FALSE);
                    defer gl.DepthMask(gl.TRUE);
                    //defer gl.Disable(gl.BLEND);
                    gl.Clear(gl.DEPTH_BUFFER_BIT);

                    const sh1 = self.shader.sun;
                    gl.UseProgram(sh1);
                    gl.BindVertexArray(self.sun_batch.vao);
                    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, self.csm.mat_ubo);
                    gl.BindTextureUnit(0, self.gbuffer.pos);
                    gl.BindTextureUnit(1, self.gbuffer.normal);
                    gl.BindTextureUnit(2, self.gbuffer.albedo);
                    gl.BindTextureUnit(3, self.csm.textures);
                    var ambient_scaled = self.ambient;
                    ambient_scaled[3] *= self.ambient_scale;
                    graph.GL.passUniform(sh1, "view_pos", cam.pos);
                    graph.GL.passUniform(sh1, "light_dir", light_dir);
                    graph.GL.passUniform(sh1, "screenSize", scrsz);
                    graph.GL.passUniform(sh1, "the_fucking_window_offset", win_offset);
                    graph.GL.passUniform(sh1, "ambient_color", ambient_scaled);
                    graph.GL.passUniform(sh1, "light_color", self.sun_color);
                    graph.GL.passUniform(sh1, "cascadePlaneDistances[0]", @as(f32, planes[0]));
                    graph.GL.passUniform(sh1, "cascadePlaneDistances[1]", @as(f32, planes[1]));
                    graph.GL.passUniform(sh1, "cascadePlaneDistances[2]", @as(f32, planes[2]));
                    graph.GL.passUniform(sh1, "cascadePlaneDistances[3]", @as(f32, last_plane));
                    const cam_mat = cam.getViewMatrix();
                    graph.GL.passUniform(sh1, "cam_view", cam_mat);
                    graph.GL.passUniform(sh1, "cam_view_inv", cam_mat.inv());

                    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, @as(c_int, @intCast(self.sun_batch.vertices.items.len)));

                    gl.Enable(gl.BLEND);
                    gl.BlendFunc(gl.ONE, gl.ONE);
                    defer gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
                    gl.BlendEquation(gl.FUNC_ADD);

                    if (self.do_lighting) {
                        self.drawLighting(cam, scrsz, view, win_offset);
                    }
                }

                if (self.do_hdr_buffer) {
                    self.bindMainFramebufferAndVp(screen_area, screen_dim);

                    const sh1 = self.shader.hdr;
                    gl.UseProgram(sh1);
                    gl.BindVertexArray(self.sun_batch.vao);
                    graph.GL.passUniform(sh1, "exposure", self.exposure);
                    graph.GL.passUniform(sh1, "gamma", self.gamma);
                    gl.BindTextureUnit(0, self.hdrbuffer.color);
                    gl.DrawArrays(gl.TRIANGLE_STRIP, 0, @as(c_int, @intCast(self.sun_batch.vertices.items.len)));
                }

                if (self.copy_depth) {
                    const y: i32 = @intFromFloat(screen_dim.y - (screen_area.y + screen_area.h));
                    const x: i32 = @intFromFloat(screen_area.x);
                    gl.BindFramebuffer(gl.READ_FRAMEBUFFER, self.gbuffer.buffer);
                    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0);
                    gl.BlitFramebuffer(
                        0,
                        0,
                        self.gbuffer.scr_w,
                        self.gbuffer.scr_h,
                        x,
                        y,
                        x + @as(i32, @intFromFloat(screen_area.w)),
                        y + @as(i32, @intFromFloat(screen_area.h)),
                        gl.DEPTH_BUFFER_BIT,
                        gl.NEAREST,
                    );
                    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
                }
                _ = dctx;
            },
        }
        self.last_frame_view_mat = cam.getViewMatrix();
    }

    pub fn drawSkybox(self: *Self, cam: graph.Camera3D, screen_area: graph.Rect, textures: [6]glID) void {
        if (self.do_skybox) { //sky stuff
            gl.Disable(gl.BLEND);
            gl.DepthMask(gl.FALSE);
            gl.DepthFunc(gl.LEQUAL);
            defer gl.DepthFunc(gl.LESS);
            defer gl.DepthMask(gl.TRUE);

            const za = graph.za;
            const la = za.lookAt(Vec3.zero(), cam.front, cam.getUp());
            const perp = za.perspective(cam.fov, screen_area.w / screen_area.h, 0, 1);

            for (&self.sky_meshes, textures) |*sk, txt| {
                sk.draw(.{ .texture = txt, .shader = self.shader.skybox }, perp.mul(la), graph.za.Mat4.identity());
            }
        }
    }

    fn drawDecal(self: *Self, cam: graph.Camera3D, wh: anytype, view: anytype, window_offset: anytype, far_clip: f32) void {
        {
            gl.DepthMask(gl.FALSE);
            defer gl.DepthMask(gl.TRUE);
            _ = window_offset;
            const sh = self.shader.decal;
            gl.UseProgram(sh);
            gl.BindVertexArray(self.decal_batch.vao);
            gl.BindTextureUnit(0, self.gbuffer.pos);
            gl.BindTextureUnit(1, self.gbuffer.normal);
            gl.BindTextureUnit(2, self.gbuffer.depth);
            graph.GL.passUniform(sh, "view_pos", cam.pos);
            graph.GL.passUniform(sh, "exposure", self.exposure);
            graph.GL.passUniform(sh, "gamma", self.gamma);
            graph.GL.passUniform(sh, "screenSize", wh);
            graph.GL.passUniform(sh, "draw_debug", self.debug_light_coverage);
            graph.GL.passUniform(sh, "far_clip", far_clip);

            graph.GL.passUniform(sh, "cam_view", cam.getViewMatrix());
            graph.GL.passUniform(sh, "view", view);
            graph.GL.passUniform(sh, "viewInv", view.inv());

            self.decal_batch.draw();
        }
    }

    fn drawLighting(self: *Self, cam: graph.Camera3D, wh: anytype, view: anytype, window_offset: anytype) void {
        if (!self.debug_light_coverage)
            graph.gl.CullFace(graph.gl.FRONT);
        defer graph.gl.CullFace(graph.gl.BACK);
        { //point lights
            const sh = self.shader.light;
            gl.UseProgram(sh);
            gl.BindVertexArray(self.point_light_batch.vao);
            gl.BindTextureUnit(0, self.gbuffer.pos);
            gl.BindTextureUnit(1, self.gbuffer.normal);
            gl.BindTextureUnit(2, self.gbuffer.albedo);
            graph.GL.passUniform(sh, "view_pos", cam.pos);
            graph.GL.passUniform(sh, "exposure", self.exposure);
            graph.GL.passUniform(sh, "gamma", self.gamma);
            graph.GL.passUniform(sh, "screenSize", wh);
            graph.GL.passUniform(sh, "the_fucking_window_offset", window_offset);
            graph.GL.passUniform(sh, "draw_debug", self.debug_light_coverage);

            graph.GL.passUniform(sh, "cam_view", cam.getViewMatrix());
            graph.GL.passUniform(sh, "view", view);

            self.point_light_batch.draw();
        }
        {
            const sh = self.shader.spot;
            gl.UseProgram(sh);
            gl.BindVertexArray(self.spot_light_batch.vao);
            gl.BindTextureUnit(0, self.gbuffer.pos);
            gl.BindTextureUnit(1, self.gbuffer.normal);
            gl.BindTextureUnit(2, self.gbuffer.albedo);
            graph.GL.passUniform(sh, "view_pos", cam.pos);
            graph.GL.passUniform(sh, "exposure", self.exposure);
            graph.GL.passUniform(sh, "gamma", self.gamma);
            graph.GL.passUniform(sh, "screenSize", wh);
            graph.GL.passUniform(sh, "the_fucking_window_offset", window_offset);
            graph.GL.passUniform(sh, "draw_debug", self.debug_light_coverage);

            graph.GL.passUniform(sh, "cam_view", cam.getViewMatrix());
            graph.GL.passUniform(sh, "view", view);

            self.spot_light_batch.draw();
        }
    }

    fn bindMainFramebufferAndVp(_: *Self, screen_area: graph.Rect, screen_dim: graph.Vec2f) void {
        const y_: i32 = @intFromFloat(screen_dim.y - (screen_area.y + screen_area.h));
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
        gl.Viewport(
            @intFromFloat(screen_area.x),
            y_,
            @intFromFloat(screen_area.w),
            @intFromFloat(screen_area.h),
        );
    }
};
//In forward, we just do the draw call
//otherwise, we need to draw that and the next
//then draw it again later? yes

const GBuffer = struct {
    buffer: c_uint = 0,
    depth: c_uint = 0,
    pos: c_uint = 0,
    normal: c_uint = 0,
    albedo: c_uint = 0,

    scr_w: i32 = 0,
    scr_h: i32 = 0,

    pub fn updateResolution(self: *@This(), new_w: i32, new_h: i32) void {
        if (new_w != self.scr_w or new_h != self.scr_h) {
            gl.DeleteTextures(1, @ptrCast(&self.pos));
            gl.DeleteTextures(1, @ptrCast(&self.normal));
            gl.DeleteTextures(1, @ptrCast(&self.albedo));
            gl.DeleteRenderbuffers(1, @ptrCast(&self.depth));
            gl.DeleteFramebuffers(1, @ptrCast(&self.buffer));
            self.* = create(new_w, new_h);
        }
    }

    pub fn create(scrw: i32, scrh: i32) @This() {
        var ret: GBuffer = .{};
        ret.scr_w = scrw;
        ret.scr_h = scrh;
        gl.GenFramebuffers(1, @ptrCast(&ret.buffer));
        gl.BindFramebuffer(gl.FRAMEBUFFER, ret.buffer);
        const pos_fmt = gl.RGBA32F;
        const norm_fmt = gl.RGBA16F;

        gl.GenTextures(1, @ptrCast(&ret.pos));
        gl.BindTexture(gl.TEXTURE_2D, ret.pos);
        gl.TexImage2D(gl.TEXTURE_2D, 0, pos_fmt, scrw, scrh, 0, gl.RGBA, gl.FLOAT, null);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, ret.pos, 0);

        gl.GenTextures(1, @ptrCast(&ret.normal));
        gl.BindTexture(gl.TEXTURE_2D, ret.normal);
        gl.TexImage2D(gl.TEXTURE_2D, 0, norm_fmt, scrw, scrh, 0, gl.RGBA, gl.HALF_FLOAT, null);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, ret.normal, 0);

        gl.GenTextures(1, @ptrCast(&ret.albedo));
        gl.BindTexture(gl.TEXTURE_2D, ret.albedo);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, scrw, scrh, 0, gl.RGBA, gl.HALF_FLOAT, null);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT2, gl.TEXTURE_2D, ret.albedo, 0);

        const attachments = [_]c_int{ gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1, gl.COLOR_ATTACHMENT2, 0 };
        gl.DrawBuffers(@intCast(attachments.len), @ptrCast(attachments[0..].ptr));

        gl.GenTextures(1, @ptrCast(&ret.depth));
        gl.BindTexture(gl.TEXTURE_2D, ret.depth);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT, scrw, scrh, 0, gl.DEPTH_COMPONENT, gl.FLOAT, null);
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, ret.depth, 0);

        if (gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE)
            std.debug.print("gbuffer FBO not complete\n", .{});
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
        return ret;
    }
};

const Csm = struct {
    const CSM_COUNT = 4;
    fbo: c_uint,
    textures: c_uint,
    res: i32,

    mat_ubo: c_uint = 0,

    mats: [CSM_COUNT]Mat4 = undefined,
    pad: f32 = 15 * 32,

    fn createCsm(resolution: i32, cascade_count: i32, light_shader: c_uint) Csm {
        var fbo: c_uint = 0;
        var textures: c_uint = 0;
        gl.GenFramebuffers(1, @ptrCast(&fbo));
        gl.GenTextures(1, @ptrCast(&textures));
        gl.BindTexture(gl.TEXTURE_2D_ARRAY, textures);
        gl.TexImage3D(
            gl.TEXTURE_2D_ARRAY,
            0,
            gl.DEPTH_COMPONENT32F,
            resolution,
            resolution,
            cascade_count,
            0,
            gl.DEPTH_COMPONENT,
            gl.FLOAT,
            null,
        );
        gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
        gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);

        const border_color = [_]f32{1} ** 4;
        gl.TexParameterfv(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_BORDER_COLOR, &border_color);

        gl.BindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.FramebufferTexture(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, textures, 0);
        gl.DrawBuffer(gl.NONE);
        gl.ReadBuffer(gl.NONE);

        const status = gl.CheckFramebufferStatus(gl.FRAMEBUFFER);
        if (status != gl.FRAMEBUFFER_COMPLETE)
            std.debug.print("Framebuffer is broken\n", .{});

        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        var lmu: c_uint = 0;
        {
            gl.GenBuffers(1, @ptrCast(&lmu));
            gl.BindBuffer(gl.UNIFORM_BUFFER, lmu);
            gl.BufferData(gl.UNIFORM_BUFFER, @sizeOf([4][4]f32) * CSM_COUNT, null, gl.DYNAMIC_DRAW);
            gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, lmu);
            gl.BindBuffer(gl.UNIFORM_BUFFER, 0);

            const li = gl.GetUniformBlockIndex(light_shader, "LightSpaceMatrices");
            gl.UniformBlockBinding(light_shader, li, 0);
        }

        return .{
            .fbo = fbo,
            .textures = textures,
            .res = resolution,
            .mat_ubo = lmu,
        };
    }

    pub fn calcMats(self: *Csm, fov: f32, aspect: f32, near: f32, far: f32, last_frame_view_mat: Mat4, sun_dir: Vec3, planes: [CSM_COUNT - 1]f32) void {
        self.mats = self.getLightMatrices(fov, aspect, near, far, last_frame_view_mat, sun_dir, planes);
        gl.BindBuffer(gl.UNIFORM_BUFFER, self.mat_ubo);
        for (self.mats, 0..) |mat, i| {
            const ms = @sizeOf([4][4]f32);
            gl.BufferSubData(gl.UNIFORM_BUFFER, @as(c_long, @intCast(i)) * ms, ms, &mat.data[0][0]);
        }
        gl.BindBuffer(gl.UNIFORM_BUFFER, 0);
    }

    pub fn draw(csm: *Csm, rend: *const Renderer) void {
        gl.BindFramebuffer(gl.FRAMEBUFFER, csm.fbo);
        gl.Disable(graph.gl.SCISSOR_TEST); //BRUH
        gl.Viewport(0, 0, csm.res, csm.res);
        gl.Clear(gl.DEPTH_BUFFER_BIT);

        const sh = rend.shader.csm;
        gl.UseProgram(sh);
        for (rend.draw_calls.items) |dc| {
            if (rend.omit_model_shadow and dc.model != null) continue;
            GL.passUniform(sh, "model", if (dc.model) |mod| mod else Mat4.identity());
            gl.BindVertexArray(dc.vao);
            gl.DrawElements(@intFromEnum(dc.prim), dc.num_elements, dc.element_type, 0);
        }
    }

    fn getLightMatrices(self: *const Csm, fov: f32, aspect: f32, near: f32, far: f32, cam_view: Mat4, light_dir: Vec3, planes: [CSM_COUNT - 1]f32) [CSM_COUNT]Mat4 {
        var ret: [CSM_COUNT]Mat4 = undefined;
        //fov, aspect, near, far, cam_view, light_Dir
        for (0..CSM_COUNT) |i| {
            if (i == 0) {
                ret[i] = self.getLightMatrix(fov, aspect, near, planes[i], cam_view, light_dir);
            } else if (i < CSM_COUNT - 1) {
                ret[i] = self.getLightMatrix(fov, aspect, planes[i - 1], planes[i], cam_view, light_dir);
            } else {
                ret[i] = self.getLightMatrix(fov, aspect, planes[i - 1], far, cam_view, light_dir);
            }
        }
        return ret;
    }

    fn getLightMatrix(self: *const Csm, fov: f32, aspect: f32, near: f32, far: f32, cam_view: Mat4, light_dir: Vec3) Mat4 {
        const cam_persp = graph.za.perspective(fov, aspect, near, far);
        const corners = getFrustumCornersWorldSpace(cam_persp.mul(cam_view));
        var center = Vec3.zero();
        for (corners) |corner| {
            center = center.add(corner.toVec3());
        }
        center = center.scale(1.0 / @as(f32, @floatFromInt(corners.len)));
        const lview = graph.za.lookAt(
            center.add(light_dir),
            center,
            Vec3.new(0, 1, 0),
        );
        var min_x = std.math.floatMax(f32);
        var min_y = std.math.floatMax(f32);
        var min_z = std.math.floatMax(f32);

        var max_x = -std.math.floatMax(f32);
        var max_y = -std.math.floatMax(f32);
        var max_z = -std.math.floatMax(f32);
        for (corners) |corner| {
            const trf = lview.mulByVec4(corner);
            min_x = @min(min_x, trf.x());
            min_y = @min(min_y, trf.y());
            min_z = @min(min_z, trf.z());

            max_x = @max(max_x, trf.x());
            max_y = @max(max_y, trf.y());
            max_z = @max(max_z, trf.z());
        }

        const tw = self.pad;
        min_z = if (min_z < 0) min_z * tw else min_z / tw;
        max_z = if (max_z < 0) max_z / tw else max_z * tw;

        //const ortho = graph.za.orthographic(-20, 20, -20, 20, 0.1, 300).mul(lview);
        const ortho = graph.za.orthographic(min_x, max_x, min_y, max_y, min_z, max_z).mul(lview);
        return ortho;
    }

    fn getFrustumCornersWorldSpace(frustum: Mat4) [8]graph.za.Vec4 {
        const inv = frustum.inv();
        var corners: [8]graph.za.Vec4 = undefined;
        var i: usize = 0;
        for (0..2) |x| {
            for (0..2) |y| {
                for (0..2) |z| {
                    const pt = inv.mulByVec4(graph.za.Vec4.new(
                        2 * @as(f32, @floatFromInt(x)) - 1,
                        2 * @as(f32, @floatFromInt(y)) - 1,
                        2 * @as(f32, @floatFromInt(z)) - 1,
                        1.0,
                    ));
                    corners[i] = pt.scale(1 / pt.w());
                    i += 1;
                }
            }
        }
        if (i != 8)
            unreachable;

        return corners;
    }
};

pub fn LightBatchGeneric(comptime vertT: type) type {
    return struct {
        pub const Vertex = packed struct {
            pos: graph.Vec3f,
        };

        vbo: c_uint = 0,
        vao: c_uint = 0,
        ebo: c_uint = 0,
        ivbo: c_uint = 0,

        alloc: std.mem.Allocator,
        vertices: std.ArrayList(Vertex) = .{},
        indicies: std.ArrayList(u32) = .{},
        inst: std.ArrayList(vertT) = .{},

        pub fn init(alloc: std.mem.Allocator, asset_dir: std.fs.Dir, obj_name: []const u8) !@This() {
            var ret = @This(){
                .alloc = alloc,
                .vao = GL.genVertexArray(),
                .vbo = GL.genBuffer(),
                .ebo = GL.genBuffer(),
                .ivbo = GL.genBuffer(),
            };

            graph.GL.generateVertexAttributes(ret.vao, ret.vbo, Vertex);
            gl.BindVertexArray(ret.vao);
            gl.EnableVertexAttribArray(1);
            gl.BindBuffer(gl.ARRAY_BUFFER, ret.ivbo);
            graph.GL.generateVertexAttributesEx(ret.vao, ret.ivbo, vertT, 1);
            gl.BindVertexArray(ret.vao);
            const count = @typeInfo(vertT).@"struct".fields.len;
            for (1..count + 1) |i|
                gl.VertexAttribDivisor(@intCast(i), 1);

            var obj = try mesh.loadObj(alloc, asset_dir, obj_name, 1);
            defer obj.deinit();
            if (obj.meshes.items.len == 0) return error.invalidIcoSphere;
            for (obj.meshes.items[0].vertices.items) |v| {
                try ret.vertices.append(ret.alloc, .{ .pos = graph.Vec3f.new(v.x, v.y, v.z) });
            }
            try ret.indicies.appendSlice(ret.alloc, obj.meshes.items[0].indicies.items);
            ret.pushVertexData();

            return ret;
        }

        pub fn deinit(self: *@This()) void {
            self.vertices.deinit(self.alloc);
            self.indicies.deinit(self.alloc);
            self.inst.deinit(self.alloc);
        }

        pub fn pushVertexData(self: *@This()) void {
            gl.BindVertexArray(self.vao);
            graph.GL.bufferData(gl.ARRAY_BUFFER, self.vbo, Vertex, self.vertices.items);
            graph.GL.bufferData(gl.ELEMENT_ARRAY_BUFFER, self.ebo, u32, self.indicies.items);
            graph.GL.bufferData(gl.ARRAY_BUFFER, self.ivbo, vertT, self.inst.items);
        }

        pub fn clear(self: *@This()) void {
            self.inst.clearRetainingCapacity();
        }

        pub fn draw(self: *@This()) void {
            gl.DrawElementsInstanced(
                gl.TRIANGLES,
                @intCast(self.indicies.items.len),
                gl.UNSIGNED_INT,
                0,
                @intCast(self.inst.items.len),
            );
            gl.BindVertexArray(0);
        }
    };
}

fn initSkyboxMeshes(alloc: std.mem.Allocator) [6]SkyBatch {
    var ret: [6]SkyBatch = undefined;
    const a = 1;
    const t = 1;
    const b = 0.006; //Inset the uv sligtly to prevent seams from showing
    //Maybe use clamptoedge?
    const o = 1 - b;
    const uvs = [4]graph.Vec2f{
        .{ .x = b, .y = b },
        .{ .x = o, .y = b },
        .{ .x = o, .y = o },
        .{ .x = b, .y = o },
    };
    const verts = [_]SkyBatch.VtxType{
        .{ .uv = uvs[3], .pos = .{ .y = -a, .z = -a, .x = t } },
        .{ .uv = uvs[2], .pos = .{ .y = a, .z = -a, .x = t } },
        .{ .uv = uvs[1], .pos = .{ .y = a, .z = a, .x = t } },
        .{ .uv = uvs[0], .pos = .{ .y = -a, .z = a, .x = t } },

        .{ .uv = uvs[1], .pos = .{ .y = -a, .z = a, .x = -t } },
        .{ .uv = uvs[0], .pos = .{ .y = a, .z = a, .x = -t } },
        .{ .uv = uvs[3], .pos = .{ .y = a, .z = -a, .x = -t } },
        .{ .uv = uvs[2], .pos = .{ .y = -a, .z = -a, .x = -t } },

        .{ .uv = uvs[1], .pos = .{ .x = -a, .z = a, .y = t } },
        .{ .uv = uvs[0], .pos = .{ .x = a, .z = a, .y = t } },
        .{ .uv = uvs[3], .pos = .{ .x = a, .z = -a, .y = t } },
        .{ .uv = uvs[2], .pos = .{ .x = -a, .z = -a, .y = t } },

        .{ .uv = uvs[3], .pos = .{ .x = -a, .z = -a, .y = -t } },
        .{ .uv = uvs[2], .pos = .{ .x = a, .z = -a, .y = -t } },
        .{ .uv = uvs[1], .pos = .{ .x = a, .z = a, .y = -t } },
        .{ .uv = uvs[0], .pos = .{ .x = -a, .z = a, .y = -t } },

        //top and bottom
        .{ .uv = uvs[3], .pos = .{ .x = -a, .y = -a, .z = t } },
        .{ .uv = uvs[2], .pos = .{ .x = a, .y = -a, .z = t } },
        .{ .uv = uvs[1], .pos = .{ .x = a, .y = a, .z = t } },
        .{ .uv = uvs[0], .pos = .{ .x = -a, .y = a, .z = t } },

        .{ .uv = uvs[0], .pos = .{ .x = -a, .y = a, .z = -t } },
        .{ .uv = uvs[1], .pos = .{ .x = a, .y = a, .z = -t } },
        .{ .uv = uvs[2], .pos = .{ .x = a, .y = -a, .z = -t } },
        .{ .uv = uvs[3], .pos = .{ .x = -a, .y = -a, .z = -t } },
    };
    const ind = [_]u32{
        2, 1, 0, 3, 2, 0,
    };
    for (&ret, 0..) |*sky, i| {
        var skybatch = SkyBatch.init(alloc);
        skybatch.appendVerts(verts[i * 4 .. i * 4 + 4]);
        skybatch.appendIndex(&ind);
        skybatch.pushVertexData();
        sky.* = skybatch;
    }
    return ret;
}

const HdrBuffer = struct {
    fb: c_uint = 0,
    color: c_uint = 0,

    scr_w: i32 = 0,
    scr_h: i32 = 0,

    pub fn updateResolution(self: *@This(), new_w: i32, new_h: i32) void {
        if (new_w != self.scr_w or new_h != self.scr_h) {
            gl.DeleteTextures(1, @ptrCast(&self.color));
            gl.DeleteFramebuffers(1, @ptrCast(&self.fb));
            self.* = create(new_w, new_h);
        }
    }

    pub fn create(scrw: i32, scrh: i32) @This() {
        var ret: HdrBuffer = .{};
        ret.scr_w = scrw;
        ret.scr_h = scrh;

        gl.GenFramebuffers(1, @ptrCast(&ret.fb));
        gl.BindFramebuffer(gl.FRAMEBUFFER, ret.fb);

        gl.GenTextures(1, @ptrCast(&ret.color));
        gl.BindTexture(gl.TEXTURE_2D, ret.color);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, scrw, scrh, 0, gl.RGBA, gl.HALF_FLOAT, null);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, ret.color, 0);

        const attachments = [_]c_int{ gl.COLOR_ATTACHMENT0, 0 };
        gl.DrawBuffers(1, @ptrCast(&attachments[0]));

        if (gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE)
            std.debug.print("gbuffer FBO not complete\n", .{});
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
        return ret;
    }
};

pub const PointLightVertex = packed struct {
    light_pos: graph.Vec3f,
    ambient: graph.Vec3f = graph.Vec3f.new(0.1, 0.1, 0.1),
    diffuse: graph.Vec3f = graph.Vec3f.new(1, 1, 1),
    specular: graph.Vec3f = graph.Vec3f.new(4, 4, 4),

    constant: f32 = 1,
    linear: f32 = 0.7,
    quadratic: f32 = 1.8,
};

pub const SpotLightVertex = packed struct {
    pos: graph.Vec3f,

    ambient: graph.Vec3f = graph.Vec3f.new(0.1, 0.1, 0.1),
    diffuse: graph.Vec3f = graph.Vec3f.new(1, 1, 1),
    specular: graph.Vec3f = graph.Vec3f.new(4, 4, 4),

    constant: f32 = 1,
    linear: f32 = 0.7,
    quadratic: f32 = 1.8,

    cutoff: f32,
    cutoff_outer: f32,

    dir: graph.Vec3f, //These form a quat lol
    w: f32,
};

pub const DecalVertex = packed struct {
    pos: graph.Vec3f,
    ext: graph.Vec3f,
};

pub const PointLightInstanceBatch = LightBatchGeneric(PointLightVertex);
pub const SpotLightInstanceBatch = LightBatchGeneric(SpotLightVertex);
pub const DecalBatch = LightBatchGeneric(DecalVertex);

pub const Skybox_name_endings = [_][]const u8{ "ft", "bk", "lf", "rt", "up", "dn" };
