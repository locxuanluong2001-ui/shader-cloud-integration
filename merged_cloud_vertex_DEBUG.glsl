#version 310 es
precision mediump float;

// ============================================
// UNIFORMS - DEBUG SECTION
// ============================================
// TODO: Verify all these uniforms exist in your game engine
uniform vec4 ViewportScale;

uniform mat4 u_viewRect;
uniform mat4 u_viewTexel;
uniform mat4 u_view;
uniform mat4 u_invView;
uniform mat4 u_proj;
uniform mat4 u_invProj;
uniform mat4 u_viewProj;
uniform mat4 u_invViewProj;
uniform mat4 u_model[4];
uniform mat4 u_modelView;
uniform mat4 u_modelViewProj;
uniform vec4 u_alphaRef4;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_prevViewProj;

// ============== CLOUD UNIFORMS ==============
// TODO: CRITICAL - Verify these uniforms are bound from your game engine
uniform vec4 SunDir;                    // Sun direction in world space
uniform vec4 MoonDir;                   // Moon direction in world space
uniform vec4 DimensionID;               // 0=Overworld, 1=Nether, 2=End

// ============================================
// INPUT/OUTPUT - DEBUG SECTION
// ============================================
// TODO: Verify input attributes match your mesh format
in vec3 a_position;      // Vertex position (typically screen-space quad)
in vec2 a_texcoord0;     // Texture coordinates

// TODO: CRITICAL - These varyings MUST match Fragment shader input
out vec3 v_projPosition;              // Projected position for fragment shader
out vec4 v_texcoord0;                 // Texture coordinates (expanded to vec4)
flat out vec3 v_absorbColor;          // Sun transmittance color (flat interpolation)
out vec2 v_projPos;                   // Projected position XY
flat out vec3 v_scatterColor;         // Atmospheric scatter color (flat interpolation)

// ============================================
// UTILITY FUNCTIONS
// ============================================
vec3 vec3_splat(float _x) { return vec3(_x, _x, _x); }
vec2 vec2_splat(float _x) { return vec2(_x, _x); }

float pow2(float x) { return x * x; }
float pow4(float x) { return x * x * x * x; }

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 saturation(vec3 color, float val) {
    float lum = luminance(color);
    return mix(vec3_splat(lum), color, val);
}

// ============================================
// LIGHT TRANSMITTANCE (Atmosphere)
// ============================================
// TODO: These atmospheric calculations should match Fragment shader
vec3 GetLightTransmittance(vec3 lightDir, float multiplier, float ozoneMultiplier) {
    float lightExtinctionAmount = exp(-(clamp(lightDir.y + 0.03, 0.0, 1.0) * 40.0)) 
        + exp(-(clamp(lightDir.y + 0.3, 0.0, 1.0) * 5.0)) * 0.4 
        + pow2(clamp(1.0 - lightDir.y, 0.0, 1.0)) * 0.02 + 0.002;
    
    return exp(-(vec3(5.802e-6, 13.558e-6, 33.100e-6) 
        + vec3(3.996e-6, 3.996e-6, 3.996e-6) 
        + vec3(0.650e-6, 1.881e-6, 0.085e-6) * ozoneMultiplier) 
        * lightExtinctionAmount * 1.0 * multiplier * 1e6);
}

vec3 GetSunTransmittance(vec3 sunDir) {
    return GetLightTransmittance(sunDir, 1.0, 1.0);
}

vec3 GetMoonTransmittance(vec3 moonDir) {
    return saturation(GetLightTransmittance(moonDir, 1.0, 1.0), 0.25);
}

// ============================================
// SPHERE INTERSECTION (Atmosphere)
// ============================================
vec2 SphereIntersection(vec3 rayStart, vec3 rayDir, vec3 sphereCenter, float sphereRadius) {
    vec3 oc = rayStart - sphereCenter;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - pow2(sphereRadius);
    float h = pow2(b) - c;
    if (h < 0.0) {
        return vec2(-1.0, -1.0);
    } else {
        h = sqrt(h);
        return vec2(-b - h, -b + h);
    }
}

// ============================================
// PHASE FUNCTIONS
// ============================================
float PhaseHG(float costh, float g) {
    float num = (1.0 - g * g) * (1.0 + costh * costh);
    float denom = (2.0 + g * g) * pow((1.0 + g * g - 2.0 * g * costh), 1.5);
    return 3.0 / (8.0 * 3.14159265358979) * num / denom;
}

float PhaseR(float costh) {
    return 3.0 / (16.0 * 3.14159265358979) * (1.0 + costh * costh);
}

float pow8(float x) { return x * x * x * x * x * x * x * x; }
float pow3(float x) { return x * x * x; }

// ============================================
// ATMOSPHERE PARAMETERS & CALCULATION
// ============================================
struct AtmosphereParams {
    vec3 rayStart;
    vec3 rayDir;
    vec3 lightDir;
    float rayLength;
    float aerial;
    float occlusion;
    float mieMod;
};

vec3 GetAtmosphere(AtmosphereParams params, out vec4 transmittance) {
    vec2 t1 = SphereIntersection(params.rayStart, params.rayDir, vec3(0, -6371000.0, 0), 6371000.0);
    vec2 t2 = SphereIntersection(params.rayStart, params.rayDir, vec3(0, -6371000.0, 0), 6371000.0 + 100000.0);
    
    float altitude = params.rayStart.y;
    float normAltitude = params.rayStart.y / 100000.0;
    
    if (t2.y < 0.0) {
        transmittance = vec4(1.0, 1.0, 1.0, 1.0);
        return vec3(0.0, 0.0, 0.0);
    } else {
        t2.y -= max(0.0, t2.x);
        float opticalDepth = t2.y;
        opticalDepth = min(params.rayLength, opticalDepth);
        opticalDepth = min(opticalDepth * params.aerial * 2.5 * 1.0, t2.y);
        
        float hbias = 1.0 - 1.0 / (2.0 + pow2(t2.y) * 1e-12);
        hbias = pow(hbias, 1.0 + normAltitude * 10.0);
        float sqhbias = pow2(hbias);
        
        float densityR = sqhbias * 1.0;
        float densityM = pow2(sqhbias) * hbias * 1.0;
        
        float ly = params.lightDir.y;
        ly += clamp(-params.lightDir.y + 0.02, 0.0, 1.0) * clamp(params.lightDir.y + 0.7, 0.0, 1.0);
        ly = clamp(ly, -1.0, 1.0);
        
        vec3 lightColor = GetLightTransmittance(vec3(params.lightDir.x, ly, params.lightDir.z), hbias, 5.0);
        
        vec3 R = (1.0 - exp(-opticalDepth * densityR * vec3(5.802e-6, 13.558e-6, 33.100e-6) / 2.5)) * 2.5;
        vec3 M = (1.0 - exp(-opticalDepth * densityM * vec3(3.996e-6, 3.996e-6, 3.996e-6) / 0.5)) * 0.5;
        vec3 E = (vec3(5.802e-6, 13.558e-6, 33.100e-6) * densityR 
            + vec3(3.996e-6, 3.996e-6, 3.996e-6) * densityM 
            + vec3(0.650e-6, 1.881e-6, 0.085e-6) * densityR * 1.5) * pow4(1.0 - normAltitude) * 0.25;
        
        float costh = dot(params.rayDir, params.lightDir);
        float phaseR = PhaseR(costh);
        float phaseM = PhaseHG(costh, 0.8);
        float desaturate = smoothstep(0.0, 0.1, params.lightDir.y) * 0.75 + 0.25;
        
        vec3 rayleigh = (phaseR * params.occlusion + phaseR * 0.3) * saturation(lightColor, desaturate);
        vec3 mie = (phaseM * params.occlusion + phaseR * 0.3) * lightColor * params.mieMod;
        vec3 scattering = mie * M + rayleigh * R;
        
        transmittance.rgb = exp(-(opticalDepth + pow8(opticalDepth * 4.5e-6)) * E);
        transmittance.rgb = saturation(transmittance.rgb, desaturate);
        transmittance.a = step(t1.x, 0.0);
        
        if (t1.y > 0.0 && t1.y < params.rayLength) {
            float planetOpticalDepth = t1.y - max(0.0, t1.x);
            float skyWeight = exp(-planetOpticalDepth * 1e-6);
            scattering *= mix(vec3(0.2, 0.3, 0.4), vec3(1.0, 1.0, 1.0), skyWeight);
        }
        
        return scattering * 0.23;
    }
}

vec3 GetAtmosphere(AtmosphereParams params) {
    vec4 transmittance;
    return GetAtmosphere(params, transmittance);
}

// ============================================
// MAIN VERTEX SHADER
// ============================================
void main() {
    // TODO: Verify input position is in correct space
    // For fullscreen quads, typically a_position.xy ranges [0,1]
    vec4 positionVec4 = vec4(a_position, 1.0);
    
    // TODO: Screen space position for clip space (-1 to 1)
    vec2 screenPos = (positionVec4.xy * 2.0) - vec2(1.0);
    
    // TODO: Projected position for ray reconstruction in fragment shader
    vec2 projectedPos = a_position.xy * 2.0 - vec2(1.0);
    
    // TODO: Verify ViewportScale is set correctly by game engine
    // This scales texture coordinates for sub-viewport rendering
    vec2 scaledTexcoord = a_texcoord0 * ViewportScale.xy;
    
    // ========== OUTPUT VARYINGS ==========
    // TODO: Verify these match Fragment shader exactly
    
    // Projected position for world reconstruction
    v_projPosition = vec3(projectedPos.x, projectedPos.y, a_position.z);
    
    // Texture coordinates (expanded to vec4 for potential future use)
    v_texcoord0 = vec4(scaledTexcoord.x, scaledTexcoord.y, a_texcoord0.x, a_texcoord0.y);
    
    // Projected position XY
    v_projPos = projectedPos;
    
    // ========== ATMOSPHERIC CALCULATIONS ==========
    // TODO: CRITICAL - These calculations happen EVERY VERTEX
    // For better performance, consider moving to Fragment shader if possible
    
    // Calculate sun and moon fade based on their Y position
    // TODO: Adjust smoothstep ranges if sun/moon behavior seems wrong
    float sunFade = smoothstep(0.0, 0.1, SunDir.y);      // Fade sun below horizon
    float moonFade = smoothstep(0.0, 0.1, MoonDir.y);    // Fade moon below horizon
    
    // TODO: Verify these multipliers (100.0 for sun, 0.1 for moon)
    // If lighting looks too bright/dark, adjust these values
    v_absorbColor = GetSunTransmittance(SunDir.xyz) * sunFade * 100.0;
    v_absorbColor += GetMoonTransmittance(MoonDir.xyz) * moonFade * 0.1;
    
    // Calculate scatter color from atmosphere
    // This is the atmospheric glow visible in the sky
    AtmosphereParams sunAtmParams;
    sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);       // Ray start height
    sunAtmParams.rayDir = vec3(0.0, 1.0, 0.0);          // Looking straight up
    sunAtmParams.lightDir = SunDir.xyz;
    sunAtmParams.rayLength = 1e10;
    sunAtmParams.aerial = 1.0;
    sunAtmParams.occlusion = 1.0;
    sunAtmParams.mieMod = 1.0;
    
    v_scatterColor = GetAtmosphere(sunAtmParams) * 100.0;
    
    // Add moon contribution
    // TODO: Adjust 0.1 multiplier if moon glow is too faint/bright
    AtmosphereParams moonAtmParams;
    moonAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    moonAtmParams.rayDir = vec3(0.0, 1.0, 0.0);
    moonAtmParams.lightDir = MoonDir.xyz;
    moonAtmParams.rayLength = 1e10;
    moonAtmParams.aerial = 1.0;
    moonAtmParams.occlusion = 1.0;
    moonAtmParams.mieMod = 1.0;
    
    v_scatterColor += GetAtmosphere(moonAtmParams) * 0.1;
    
    // ========== DIMENSION-SPECIFIC ADJUSTMENTS ==========
    // TODO: If in Nether/End, disable sun/moon contributions
    if (int(DimensionID.r) != 0) {
        v_absorbColor = vec3_splat(0.0);    // No sun/moon transmittance
        v_scatterColor = vec3_splat(1.0);   // Use default white
    }
    
    // ========== FINAL OUTPUT ==========
    // TODO: Verify this matches your expected clip space
    // gl_Position should be in [-1, 1] range after perspective divide
    gl_Position = vec4(screenPos.x, screenPos.y, positionVec4.z, positionVec4.w);
    
    // DEBUG: You can uncomment these for shader debugging
    // gl_Position = vec4(0.0);  // This will render nothing - useful to test if shader is being called
}
