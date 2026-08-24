#ifndef LIB_CORE_GBUFFER_VERTEX_GLSL
#define LIB_CORE_GBUFFER_VERTEX_GLSL

out vec2 v_texcoord;
out vec2 v_lmcoord;
out vec4 v_color;
flat out int v_material_id;
out vec3 v_world_normal;
#ifdef HAS_AT_TANGENT
out vec3 v_world_tangent;
out vec3 v_world_bitangent;
#endif

#ifdef HAS_MC_ENTITY
in vec4 mc_Entity;
#endif
#ifdef HAS_AT_TANGENT
in vec4 at_tangent;
#endif
#ifdef HAS_ENTITY_ID
#endif

#include "/lib/contract/settings.glsl"
#include "/lib/contract/uniforms.glsl"

void SetupGbufferVertex() {
    vec4 view_pos = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gl_ProjectionMatrix * view_pos;
#ifdef TAA
    gl_Position.xy += u_taa_offset * gl_Position.w;
#endif

    vec3 normal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    v_world_normal = normal;

#ifdef HAS_AT_TANGENT
    vec3 tangent = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * at_tangent.xyz));
    vec3 bitangent = cross(tangent, normal) * sign(at_tangent.w);
    v_world_tangent = tangent;
    v_world_bitangent = bitangent;
#endif

    v_texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    v_lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    v_lmcoord = clamp(v_lmcoord * 1.103449 - 0.0689656, 0.0, 1.0);
    v_color = gl_Color;
}

#endif
