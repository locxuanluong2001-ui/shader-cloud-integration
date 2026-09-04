#version 310 es
precision mediump float;
precision highp int;

// ============================================
// UNIFORMS - DEBUG SECTION
// ============================================
// TODO: Verify all these uniforms exist in your game engine
// TODO: Check uniform buffer binding points match game

uniform highp mat4 u_invView;
uniform highp mat4 u_invProj;
uniform highp mat4 u_viewProj;
uniform highp mat4 u_proj;

// TODO: Verify PreExposureEnabled exists in your shader constants
uniform highp vec4 PreExposureEnabled;
uniform highp sampler2D s_PreviousFrameAverageLuminance;

// TODO: Check these atmospheric toggle uniforms
uniform highp vec4 AtmosphericScatteringToggles;
uniform highp vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform highp vec4 VolumeNearFar;
uniform highp sampler2DArray s_ScatteringBuffer;
uniform highp vec4 VolumeDimensions;

uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 FogColor;
uniform highp vec4 CameraAmbientContribution;
uniform highp vec4 UndergroundFogColor;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 SunColor;
uniform highp vec4 MoonColor;
uniform highp vec4 SkyZenithColor;
uniform highp vec4 SkyHorizonColor;
uniform highp vec4 FogSkyBlend;
uniform highp vec4 AtmosphericScattering;
uniform highp vec4 DiffuseSpecularEmissiveAmbientTermToggles;
uniform highp vec4 BlockBaseAmbientLightColorIntensity;
uniform highp vec4 SkyAmbientLightColorIntensity;
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 AmbientLightParams;

uniform highp sampler2D s_DiffuseLighting;
uniform highp sampler2D s_SpecularLighting;

uniform highp vec4 EmissiveMultiplierAndDesaturationAndCloudPCFAndContribution;
uniform highp sampler2D s_SceneDepth;
uniform highp sampler2D s_ColorMetalnessSubsurface;
uniform highp usampler2D s_EmissiveAmbientLinearRoughness;
uniform highp vec4 ColorGrading_OptimizeGammaCorrection;
uniform highp vec4 SkySamplesConfig;
uniform highp sampler3D s_SkyAmbientSamples;

// ============== CLOUD UNIFORMS ==============
// TODO: CRITICAL - Verify these exist in cloud shader
uniform highp vec4 Time;                                        // Wind/animation time
uniform highp vec4 WorldOrigin;                                 // Camera world position
uniform highp vec4 DimensionID;                                 // 0=Overworld, 1=Nether, 2=End
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;   // Sun/moon direction
uniform highp sampler2DArray s_CausticsTexture;                 // Noise textures for clouds

// ============================================
// INPUT/OUTPUT - DEBUG SECTION
// ============================================
// TODO: Verify these varyings match vertex shader output
in highp vec3 v_projPosition;
in highp vec4 v_texcoord0;
in vec3 v_absorbColor;           // TODO: Check - from vertex shader
in vec2 v_projPos;               // TODO: Check - from vertex shader
in vec3 v_scatterColor;          // TODO: Check - from vertex shader

layout(location = 0) out highp vec4 bgfx_FragData0;

// ============================================
// UTILITY FUNCTIONS
// ============================================
vec3 vec3_splat(float _x) { return vec3(_x, _x, _x); }
vec2 vec2_splat(float _x) { return vec2(_x, _x); }
vec4 vec4_splat(float _x) { return vec4(_x, _x, _x, _x); }

float pow2(float x) { return x * x; }
float pow3(float x) { return x * x * x; }
float pow4(float x) { return x * x * x * x; }
float pow5(float x) { return x * x * x * x * x; }
float pow8(float x) { return x * x * x * x * x * x * x * x; }

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float linearstep(float edge0, float edge1, float x) {
    return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

vec3 saturation(vec3 color, float val) {
    float lum = luminance(color);
    return mix(vec3_splat(lum), color, val);
}

vec3 preExposeLighting(vec3 color, float lum) {
    return color * (0.18 / lum + 0.0001);
}

vec3 toLinear(vec3 sRGB) {
    bvec3 cutoff = lessThan(sRGB, vec3_splat(0.04045));
    vec3 higher = pow((sRGB + vec3_splat(0.055)) / vec3_splat(1.055), vec3_splat(2.4));
    vec3 lower = sRGB / vec3_splat(12.92);
    return mix(higher, lower, cutoff);
}

// ============================================
// CLOUD FUNCTIONS (Extracted from Minecraft shader)
// ============================================

float PhaseHG(float costh, float g) {
    float num = (1.0 - g * g) * (1.0 + costh * costh);
    float denom = (2.0 + g * g) * pow((1.0 + g * g - 2.0 * g * costh), 1.5);
    return 3.0 / (8.0 * 3.14159265358979) * num / denom;
}

float PhaseR(float costh) {
    return 3.0 / (16.0 * 3.14159265358979) * (1.0 + costh * costh);
}

// TODO: Verify s_CausticsTexture is bound to a valid noise texture
float worleyR(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 3.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float worleyG(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 3.0), 1);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float worley3d(vec3 pos) {
    pos = mod(pos, vec3(32.0, 32.0, 36.0));
    float col = mod(floor(pos.z), 6.0) * 34.0;
    float row = floor(pos.z / 6.0) * 34.0;
    vec2 uv = vec2(pos.x + col, pos.y - 34.0 - row) + 1.0;
    float a = worleyR(uv);
    float b = worleyG(uv);
    return mix(a, b, fract(pos.z));
}

float valueNoise(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 0.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float valueNoise3d(vec3 pos) {
    vec2 uv = pos.xy + floor(pos.z) * 17.0;
    float a = valueNoise(uv);
    float b = valueNoise(uv + 17.0);
    return mix(a, b, fract(pos.z));
}

// ============ CUMULUS CLOUD MODEL ============
// TODO: Cloud altitudes hardcoded (180-380m) - adjust for your game scale
float calcCumulusModel(vec3 pos) {
    vec2 windDir = vec2(0.0, Time.x);
    vec2 basePos = (pos.xz + windDir) * 0.003;
    
    float base = valueNoise(basePos);
    base += valueNoise(basePos * 2.0) * 0.5;
    base += valueNoise(basePos * 4.0) * 0.25;
    base += valueNoise(basePos * 8.0) * 0.125;
    base = clamp(base * 0.533333 - 0.25, 0.0, 1.0);
    
    float heightFraction = clamp((pos.y - 180.0) / 200.0, 0.0, 1.0);
    base = linearstep(pow8(heightFraction), 1.0, base);
    base = linearstep(exp(-heightFraction * 25.0), 1.0, base);
    
    float wsculpting = worley3d(pos * 0.15 + windDir.xxy * 0.05);
    base = linearstep(wsculpting * heightFraction, 1.0, base);
    
    return base;
}

// ============ CLOUD SETUP ============
struct CloudSetup {
    float tMin;
    float tMax;
    int stepCounts;
    bool isValidCloud;
};

CloudSetup calcCloudSetup(float direction, float camAltitude) {
    CloudSetup setup;
    setup.tMin = 0.0;
    setup.tMax = 1e6;
    setup.stepCounts = 200;  // TODO: Adjust for performance (lower = faster but lower quality)
    setup.isValidCloud = true;
    
    float cloudMaxY = 180.0 + 200.0;
    float tBottomPlane = (180.0 - camAltitude) / direction;
    float tTopPlane = (cloudMaxY - camAltitude) / direction;
    
    if (camAltitude > cloudMaxY) {
        if (direction > 0.0) {
            setup.isValidCloud = false;
            return setup;
        }
        setup.tMin = tTopPlane;
        setup.tMax = tBottomPlane;
    } else if (camAltitude < 180.0) {
        if (direction < 0.0) {
            setup.isValidCloud = false;
            return setup;
        }
        setup.tMin = tBottomPlane;
        setup.tMax = tTopPlane;
    } else {
        setup.tMin = 0.0;
        setup.tMax = direction > 0.0 ? tTopPlane : tBottomPlane;
    }
    
    float raySpan = (setup.tMax - setup.tMin) / 10.0;
    setup.stepCounts = min(setup.stepCounts, int(raySpan));
    return setup;
}

// ============ ATMOSPHERIC PARAMETERS ============
struct AtmosphereParams {
    vec3 rayStart;
    vec3 rayDir;
    vec3 lightDir;
    float rayLength;
    float aerial;
    float occlusion;
    float mieMod;
};

vec3 GetLightTransmittance(vec3 lightDir, float multiplier, float ozoneMultiplier) {
    float lightExtinctionAmount = exp(-(clamp(lightDir.y + 0.03, 0.0, 1.0) * 40.0)) 
        + exp(-(clamp(lightDir.y + 0.3, 0.0, 1.0) * 5.0)) * 0.4 
        + pow2(clamp(1.0 - lightDir.y, 0.0, 1.0)) * 0.02 + 0.002;
    
    return exp(-(vec3(5.802e-6, 13.558e-6, 33.100e-6) 
        + vec3(3.996e-6, 3.996e-6, 3.996e-6) 
        + vec3(0.650e-6, 1.881e-6, 0.085e-6) * ozoneMultiplier) 
        * lightExtinctionAmount * 1.0 * multiplier * 1e6);
}

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

// ============ DIRECT SCATTERING ============
float calcDirectScattering(vec3 samplePos, vec3 lightDir, float extinction, float costh) {
    float shadow = 0.0;
    float stepSpace = 200.0 / max(lightDir.y, 0.01) * 0.25;
    stepSpace = min(stepSpace, 200.0);
    
    for (int i = 0; i < 4; i++) {
        samplePos += lightDir * stepSpace * 0.1;
        shadow += calcCumulusModel(samplePos);
    }
    
    float lighting = 0.0;
    float lMod = clamp(lightDir.y, 0.0, 1.0);
    float g = 1.0;
    float b = 1.0 + lMod * 0.5;
    float a = 1.0;
    
    for (int j = 0; j < 4; j++) {
        float fphase = PhaseHG(costh, 0.7 * g);
        float bphase = PhaseHG(costh, -0.1 * g);
        float dphase = mix(fphase, bphase, 0.4);
        lighting += b * dphase * exp(-shadow * stepSpace * a);
        a = a * (0.25 + lMod * 0.15);
        g *= 0.5;
        b *= 0.75;
    }
    
    float powder = 1.0 - exp(-extinction * 10.0 * 3.0);
    lighting *= mix(pow5(powder) * 5.0, 1.0, costh * 0.5 + 0.5);
    
    return lighting;
}

// ============ CLOUD CALCULATION ============
vec3 calcCloud(vec3 worldDir, vec3 lightDir, float worldDist, float dither, bool isTerrain, CloudSetup setup) {
    if (!setup.isValidCloud) return vec3(0.0, 0.0, 1.0);
    
    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;
    float costh = dot(worldDir, lightDir);
    
    float lighting = 0.0;
    float wdepth = 0.0;
    float tweight = 0.0;
    float transmittance = 1.0;
    
    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);
    
    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * 10.0);
        float extinction = calcCumulusModel(samplePos);
        
        if (extinction > 0.0) {
            float dscattering = calcDirectScattering(samplePos, lightDir, extinction, costh) * extinction;
            float stepTransmittance = exp(-extinction * 10.0);
            float scatterInt = (dscattering - dscattering * stepTransmittance) / max(extinction, 0.0001);
            
            lighting += transmittance * scatterInt;
            wdepth += transmittance * setup.tMin;
            tweight += transmittance;
            transmittance *= stepTransmittance;
        }
        
        if (transmittance < 0.0001) break;
        setup.tMin += 10.0;
        if (setup.tMin > setup.tMax) break;
    }
    
    wdepth /= tweight;
    return vec3(lighting, wdepth, transmittance);
}

// ============ CIRRUS CLOUDS ============
float calcCirrusModel(vec2 pos) {
    float tdensity = 0.0;
    float amplitude = 1.0;
    pos.y *= 0.3;
    pos.y += Time.x * 0.001;
    pos.x += sin(pos.y * 3.0) * 0.2;
    
    for (int i = 0; i < 4; i++) {
        float dens = valueNoise(pos) * amplitude;
        tdensity += dens;
        pos *= 3.0;
        pos.y += dens * pos.y * 0.2 + Time.x * 0.005;
        amplitude *= 0.5;
    }
    
    return clamp(tdensity * 0.533333 - 0.2, 0.0, 1.0);
}

void applyCirrusClouds(inout vec3 outColor, vec3 worldDir, vec3 lightDir, vec3 absorbColor, bool isTerrain) {
    float camAltitude = -WorldOrigin.y;
    float dirY = worldDir.y;
    float tPlane = ((180.0 + 200.0 + 200.0) - camAltitude) / dirY;
    
    if (tPlane < 0.0 || (dirY < 0.0 && camAltitude < (180.0 + 200.0 + 200.0)) || (dirY > 0.0 && camAltitude > (180.0 + 200.0 + 200.0))) 
        return;
    
    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 samplePos = rayOrigin + worldDir * tPlane;
    
    float extinction = isTerrain ? 0.0 : calcCirrusModel(samplePos.xz * 0.005);
    extinction *= smoothstep(0.0, 0.4, dirY);
    extinction *= smoothstep(0.0, 180.0, (180.0 + 200.0 + 200.0) - camAltitude);
    
    float transmittance = exp(-extinction);
    float costh = dot(worldDir, lightDir);
    float phase = PhaseR(costh);
    
    outColor = outColor * transmittance + absorbColor * phase * (1.0 - transmittance);
}

void applyCumulusClouds(inout vec3 outColor, vec3 absorbColor, vec3 worldDir, float worldDist, float dither, bool isTerrain) {
    CloudSetup cloudSetup = calcCloudSetup(worldDir.y, -WorldOrigin.y);
    vec3 clouds = calcCloud(worldDir, DirectionalLightSourceWorldSpaceDirection.xyz, worldDist, dither, isTerrain, cloudSetup);
    
    // TODO: Verify SunDir/MoonDir are properly set
    AtmosphereParams sunAtmParams;
    sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    sunAtmParams.rayDir = worldDir;
    sunAtmParams.lightDir = SunDir.xyz;
    sunAtmParams.rayLength = clouds.g;
    sunAtmParams.aerial = 80.0;
    sunAtmParams.occlusion = 1.0;
    sunAtmParams.mieMod = 1.0;
    
    AtmosphereParams moonAtmParams;
    moonAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    moonAtmParams.rayDir = worldDir;
    moonAtmParams.lightDir = MoonDir.xyz;
    moonAtmParams.rayLength = clouds.g;
    moonAtmParams.aerial = 40.0;
    moonAtmParams.occlusion = 1.0;
    moonAtmParams.mieMod = 1.0;
    
    vec4 transmittance;
    vec3 atmContrib = GetAtmosphere(sunAtmParams, transmittance) * 100.0;
    atmContrib += GetAtmosphere(moonAtmParams) * 0.1;
    
    if (MoonDir.y > 0.0) clouds.r *= 0.8;
    
    vec3 cloudsColor = clouds.r * absorbColor * transmittance.rgb;
    cloudsColor += atmContrib * (1.0 - clouds.b);
    
    outColor = clouds.b * outColor + cloudsColor;
}

// ============ VOLUMETRIC FOG ============
float logToLinearDepth(float logDepth) {
    return (exp(4.0 * logDepth) - 1.0) / (exp(4.0) - 1.0);
}

float linearToLogDepth(float linearDepth) {
    return log((exp(4.0) - 1.0) * linearDepth + 1.0) / 4.0;
}

vec3 ndcToVolume(vec3 ndc) {
    vec2 uv = ndc.xy * 0.5 + 0.5;
    vec4 view = (u_invProj * vec4(ndc, 1.0));
    float viewDepth = (-view.z) / view.w;
    float wLinear = (viewDepth - VolumeNearFar.x) / (VolumeNearFar.y - VolumeNearFar.x);
    return vec3(uv, linearToLogDepth(wLinear));
}

vec4 sampleVolume(highp sampler2DArray volume, vec3 uvw) {
    float depth = uvw.z * VolumeDimensions.z - 0.5;
    int slice = clamp(int(depth), 0, int(VolumeDimensions.z) - 2);
    float offsets = clamp(depth - float(slice), 0.0, 1.0);
    vec4 a = textureLod(volume, vec3(uvw.xy, slice), 0.0);
    vec4 b = textureLod(volume, vec3(uvw.xy, slice + 1), 0.0);
    return mix(a, b, offsets);
}

void applyVolumetricFog(inout vec3 outColor, vec3 projPos) {
    // TODO: Check if VolumeScatteringEnabledAndPointLightVolumetricsEnabled should toggle this
    vec3 uvw = ndcToVolume(projPos);
    vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) 
        outColor = outColor * volumetricFog.a + volumetricFog.rgb;
}

// ============================================
// MAIN FRAGMENT SHADER
// ============================================
void main() {
    // TODO: Test - Print depth to verify it's being read correctly
    highp vec4 depthSample = texture(s_SceneDepth, v_texcoord0.xy);
    highp float depth = (depthSample.x * 2.0) - 1.0;
    
    // TODO: Verify projection matrix transforms are correct
    highp vec4 projPos = vec4(v_projPosition.xy, depth, 1.0);
    highp vec4 viewPos = u_invProj * projPos;
    viewPos /= viewPos.w;
    
    // TODO: Check if world position reconstruction is correct
    // If clouds appear in wrong location, issue is likely here
    highp vec4 worldPos = u_invView * viewPos;
    vec3 worldDir = normalize(worldPos.xyz);
    float worldDist = length(worldPos.xyz);
    
    // Fog calculation
    float wDistNorm = worldDist / FogAndDistanceControl.z;
    vec3 outColor = vec3_splat(0.0);
    bool isTerrain = depth < 1.0;
    
    // Sample textures
    vec3 diffuseLighting = texture(s_DiffuseLighting, v_texcoord0.xy).rgb;
    vec3 specularLighting = texture(s_SpecularLighting, v_texcoord0.xy).rgb;
    
    // TODO: Verify these texture samples are used correctly
    vec4 colorSample = texture(s_ColorMetalnessSubsurface, v_texcoord0.xy);
    uvec4 emissiveSample = texelFetch(s_EmissiveAmbientLinearRoughness, 
        ivec2(vec2(textureSize(s_EmissiveAmbientLinearRoughness, 0)) * v_texcoord0.xy), 0);
    
    // Base color blend
    if (isTerrain) {
        outColor = diffuseLighting + specularLighting;
    }
    
    // ========== CRITICAL: CLOUD RENDERING ==========
    // TODO: Set to 0 to disable clouds for testing
    const bool ENABLE_CLOUDS = true;
    
    if (ENABLE_CLOUDS && int(DimensionID.r) == 0) {
        // TODO: Verify SunDir and DirectionalLightSourceWorldSpaceDirection are the same
        // If different, clouds may render incorrectly
        
        AtmosphereParams sunAtmParams;
        sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
        sunAtmParams.rayDir = worldDir;
        sunAtmParams.lightDir = SunDir.xyz;
        sunAtmParams.rayLength = 1e10;
        sunAtmParams.aerial = 1.0;
        sunAtmParams.occlusion = 1.0;
        sunAtmParams.mieMod = 1.0;
        
        // Add atmospheric scattering
        vec3 scattering = GetAtmosphere(sunAtmParams) * 100.0;
        if (!isTerrain) outColor = scattering;
        
        // Apply cloud layers
        // TODO: v_absorbColor should contain sun transmittance from vertex shader
        applyCirrusClouds(outColor, worldDir, DirectionalLightSourceWorldSpaceDirection.xyz, v_absorbColor, isTerrain);
        
        // TODO: Verify dither pattern works with screen-space coordinates
        float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
        applyCumulusClouds(outColor, v_absorbColor, worldDir, worldDist, dither, isTerrain);
        
    } else if (!ENABLE_CLOUDS && int(DimensionID.r) != 0) {
        // Underground/Nether/End fog
        float borderFog = clamp((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x) * FogAndDistanceControl.y, 0.0, 1.0);
        vec3 linFogColor = toLinear(FogColor.rgb);
        outColor = mix(outColor, linFogColor, borderFog);
    }
    
    // Apply volumetric fog
    // TODO: Check if this should always apply or only in Overworld
    applyVolumetricFog(outColor, projPos.xyz);
    
    // Pre-exposure
    if (PreExposureEnabled.x > 0.0) {
        float avgLum = texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r;
        outColor = preExposeLighting(outColor, avgLum);
    }
    
    // TODO: Check output format - should always be RGBA with A=1.0
    bgfx_FragData0 = vec4(outColor, 1.0);
}
