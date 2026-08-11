# Getting a Cairo surface onto the screen.
#
# The panel is drawn once per tick into an ARGB32 image surface and then
# handed to the GPU as one texture stretched over one full-screen triangle.
# Nothing else is rendered, so there is no blending to configure: Cairo
# produces premultiplied alpha, which is exactly what a compositor expects
# to find in the framebuffer of a transparent window.

const VERT_SRC = """
#version 330 core
out vec2 uv;
void main() {
    // One oversized triangle covering the viewport, built from gl_VertexID
    // so there is no vertex buffer to allocate or keep alive.
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    // Cairo's first row is the top of the image, GL's is the bottom.
    uv = vec2(p.x, 1.0 - p.y);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""

const FRAG_SRC = """
#version 330 core
in vec2 uv;
uniform sampler2D tex;
out vec4 color;
void main() {
    color = texture(tex, uv);
}
"""

function compile_shader(src::AbstractString, kind::GLenum)
    sh = glCreateShader(kind)
    s = String(src)
    GC.@preserve s begin
        glShaderSource(sh, 1, Ref(Ptr{GLchar}(pointer(s))), Ref(GLint(sizeof(s))))
    end
    glCompileShader(sh)
    ok = Ref{GLint}(0)
    glGetShaderiv(sh, GL_COMPILE_STATUS, ok)
    if ok[] != GL_TRUE
        len = Ref{GLint}(0)
        glGetShaderiv(sh, GL_INFO_LOG_LENGTH, len)
        log = Vector{UInt8}(undef, max(len[], 1))
        glGetShaderInfoLog(sh, length(log), C_NULL, log)
        glDeleteShader(sh)
        error("StatusWindows: shader compilation failed:\n", String(log))
    end
    return sh
end

function build_program()
    vs = compile_shader(VERT_SRC, GL_VERTEX_SHADER)
    fs = compile_shader(FRAG_SRC, GL_FRAGMENT_SHADER)
    prog = glCreateProgram()
    glAttachShader(prog, vs)
    glAttachShader(prog, fs)
    glLinkProgram(prog)
    ok = Ref{GLint}(0)
    glGetProgramiv(prog, GL_LINK_STATUS, ok)
    if ok[] != GL_TRUE
        len = Ref{GLint}(0)
        glGetProgramiv(prog, GL_INFO_LOG_LENGTH, len)
        log = Vector{UInt8}(undef, max(len[], 1))
        glGetProgramInfoLog(prog, length(log), C_NULL, log)
        error("StatusWindows: shader link failed:\n", String(log))
    end
    # The shaders are baked into the program now.
    glDetachShader(prog, vs); glDeleteShader(vs)
    glDetachShader(prog, fs); glDeleteShader(fs)
    return prog
end

function build_texture()
    ref = Ref{GLuint}(0)
    glGenTextures(1, ref)
    tex = ref[]
    glBindTexture(GL_TEXTURE_2D, tex)
    # One texel per pixel, so nearest filtering keeps text perfectly sharp.
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    return tex
end

"""
    upload!(tex, buf)

Push the Cairo backing store into `tex`. `buf` is a `(width, height)`
column-major `Matrix{UInt32}`, which in memory is exactly the row-major
ARGB32 image Cairo drew. On a little-endian machine those words are laid
down as B,G,R,A bytes, which is what `GL_BGRA` + `GL_UNSIGNED_INT_8_8_8_8_REV`
expects.
"""
function upload!(tex::GLuint, buf::Matrix{UInt32})
    w, h = size(buf)
    glBindTexture(GL_TEXTURE_2D, tex)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0,
                 GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, buf)
    return nothing
end

"Draw the texture over the whole framebuffer."
function blit(prog::GLuint, vao::GLuint, tex::GLuint, fbw::Integer, fbh::Integer)
    glViewport(0, 0, fbw, fbh)
    glClearColor(0.0f0, 0.0f0, 0.0f0, 0.0f0)
    glClear(GL_COLOR_BUFFER_BIT)
    glDisable(GL_BLEND)
    glUseProgram(prog)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, tex)
    glUniform1i(glGetUniformLocation(prog, "tex"), 0)
    glBindVertexArray(vao)
    glDrawArrays(GL_TRIANGLES, 0, 3)
    return nothing
end
