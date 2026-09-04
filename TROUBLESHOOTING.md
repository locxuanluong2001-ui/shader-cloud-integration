# 🎮 Cloud Shader Integration - Troubleshooting Guide

## ⚠️ COMMON ISSUES & FIXES

---

## 1️⃣ **Shader Compilation Error**

### ❌ Error Message:
```
GLSL Compilation Failed: Uniform 'Time' not found
GLSL Compilation Failed: Uniform 'WorldOrigin' not found
```

### ✅ Fix:
**Problem:** Game engine không bind các uniform này vào shader.

**Solution:**
```cpp
// In your game render code, add these uniforms BEFORE rendering:
glUniform4f(glGetUniformLocation(shaderProgram, "Time"), 
    currentTime, 0.0f, 0.0f, 0.0f);

glUniform4f(glGetUniformLocation(shaderProgram, "WorldOrigin"), 
    cameraX, cameraY, cameraZ, 0.0f);

glUniform4f(glGetUniformLocation(shaderProgram, "DimensionID"), 
    dimensionID, 0.0f, 0.0f, 0.0f);

glUniform4f(glGetUniformLocation(shaderProgram, "DirectionalLightSourceWorldSpaceDirection"), 
    sunDirX, sunDirY, sunDirZ, 0.0f);
```

---

## 2️⃣ **Black Screen / No Output**

### ❌ Problem:
Màn hình toàn đen, không thấy gì.

### ✅ Debugging Steps:

**Step 1:** Tắt clouds để test
```glsl
// In merged_cloud_fragment_DEBUG.glsl, line ~360
const bool ENABLE_CLOUDS = false;  // Change to false
```

**Step 2:** Test nếu đó là vấn đề của clouds hay của code cũ
- Nếu output bình thường → **clouds code có lỗi**
- Nếu vẫn đen → **vấn đề ở fragment shader base**

**Step 3:** Kiểm tra uniform buffers
```cpp
// Add this debug output
std::cout << "s_SceneDepth binding: " << glGetUniformLocation(shader, "s_SceneDepth") << std::endl;
std::cout << "s_DiffuseLighting binding: " << glGetUniformLocation(shader, "s_DiffuseLighting") << std::endl;
```

---

## 3️⃣ **Clouds Render Ở Vị Trí Sai**

### ❌ Problem:
Đám mây xuất hiện ở nơi không đúng hoặc ngược chiều.

### ✅ Root Cause & Fix:
**Vấn đề:** World position reconstruction sai

**File affected:** `merged_cloud_fragment_DEBUG.glsl` lines 340-350

**Original code:**
```glsl
highp vec4 viewPos = u_invProj * projPos;
viewPos /= viewPos.w;
highp vec4 worldPos = u_invView * viewPos;
```

**DEBUG - Try this alternative:**
```glsl
// METHOD 1: Using only invViewProj (faster, more accurate)
highp vec4 worldPos = u_invViewProj * vec4(v_projPosition.xy, depth, 1.0);
worldPos /= worldPos.w;

// METHOD 2: If METHOD 1 doesn't work, try reconstructing from view-space
highp vec4 viewPos = u_invProj * vec4(v_projPosition.xy, depth, 1.0);
viewPos /= viewPos.w;
viewPos.z = -viewPos.z;  // OpenGL z is negative
highp vec4 worldPos = u_invView * vec4(viewPos.xyz, 1.0);
```

**How to test:**
Replace line 340-345 with each METHOD and check:
- Do clouds move with camera?
- Do clouds stay at correct altitude?
- Do clouds fade with distance?

---

## 4️⃣ **Varying Variable Mismatch**

### ❌ Error:
```
Fragment shader input v_absorbColor does not match Vertex shader output
```

### ✅ Fix:
Ensure **EXACTLY** matching in both files:

**Vertex Shader Output:**
```glsl
flat out vec3 v_absorbColor;      // 👈 MUST be "flat out"
out vec2 v_projPos;
flat out vec3 v_scatterColor;      // 👈 MUST be "flat out"
```

**Fragment Shader Input:**
```glsl
in vec3 v_absorbColor;             // 👈 MUST be "in"
in vec2 v_projPos;
in vec3 v_scatterColor;
```

⚠️ **CRITICAL:** `flat` keyword must match EXACTLY!

---

## 5️⃣ **Texture Binding Issues**

### ❌ Error:
```
Texture 's_CausticsTexture' not bound
Texture 's_SceneDepth' returns black
```

### ✅ Fix:

**Check texture binding order:**
```cpp
// Bind textures in correct order BEFORE drawing
glActiveTexture(GL_TEXTURE0);
glBindTexture(GL_TEXTURE_2D, depthTexture);
glUniform1i(glGetUniformLocation(shader, "s_SceneDepth"), 0);

glActiveTexture(GL_TEXTURE1);
glBindTexture(GL_TEXTURE_2D, diffuseTexture);
glUniform1i(glGetUniformLocation(shader, "s_DiffuseLighting"), 1);

glActiveTexture(GL_TEXTURE2);
glBindTexture(GL_TEXTURE_2D_ARRAY, causticsTexture);
glUniform1i(glGetUniformLocation(shader, "s_CausticsTexture"), 2);

glActiveTexture(GL_TEXTURE3);
glBindTexture(GL_TEXTURE_2D_ARRAY, scatteringBuffer);
glUniform1i(glGetUniformLocation(shader, "s_ScatteringBuffer"), 3);
```

---

## 6️⃣ **Atmospheric Colors Wrong**

### ❌ Problem:
Sky colors look weird, not matching original.

### ✅ Solution:

**Check atmospheric toggle uniforms:**
```cpp
// These control what gets rendered
glUniform4f(glGetUniformLocation(shader, "AtmosphericScatteringToggles"),
    1.0f,  // x: enable atmospheric scattering
    1.0f,  // y: use fog color or compute
    1.0f,  // z: ambient multiplier
    1.0f); // w: underground fog blend
```

**If colors still wrong, check sun/moon directions:**
```cpp
// SunDir should point FROM sun TO earth (normalized)
glUniform4f(glGetUniformLocation(shader, "SunDir"),
    sinf(sunAngle), cosf(sunElevation), cosf(sunAngle), 0.0f);

// MoonDir similarly
glUniform4f(glGetUniformLocation(shader, "MoonDir"),
    sinf(moonAngle), cosf(moonElevation), cosf(moonAngle), 0.0f);
```

---

## 7️⃣ **Performance Too Slow**

### ❌ Problem:
FPS drop significantly, game lagging.

### ✅ Optimization:

**Reduce cloud raymarching steps:**
```glsl
// In merged_cloud_fragment_DEBUG.glsl, function calcCloudSetup()
// Around line ~250, change:
setup.stepCounts = 200;  // Too high, causes lag

// To:
setup.stepCounts = 50;   // Much faster, still looks decent
```

**Disable expensive features:**
```glsl
// In main(), around line 360
const bool ENABLE_CLOUDS = true;  // Set to false if too slow

// Or disable specific effects:
// - applyCirrusClouds (expensive)
// - calcDirectScattering (many samples)
// - applyVolumetricFog (many texture lookups)
```

**Check if it's Vertex or Fragment shader bound:**
```cpp
// If FPS better without clouds = Fragment shader issue
// If FPS same = Vertex shader bottleneck (unlikely)
```

---

## 8️⃣ **Clouds Not Appearing at All**

### ❌ Problem:
All other rendering works, but no clouds visible.

### ✅ Checklist:

1. **Is DimensionID correct?**
   ```glsl
   // Clouds only render in Overworld (DimensionID == 0)
   if (int(DimensionID.r) == 0)  // ✅ This must be true
   ```
   Fix: Ensure DimensionID.r is 0 for Overworld

2. **Are s_CausticsTexture layers correct?**
   ```glsl
   // Noise texture should have layers:
   // Layer 0: Value noise
   // Layer 1: Dither pattern
   // Layer 2: Perlin-Worley
   // Layer 3: Worley
   ```
   Fix: Check texture layer arrangement

3. **Is WorldOrigin set?**
   ```cpp
   // WorldOrigin must match camera position
   glUniform4f(glGetUniformLocation(shader, "WorldOrigin"),
       -cameraX, -cameraY, -cameraZ, 0.0f);  // Note: negated!
   ```

4. **CloudSetup invalid?**
   ```glsl
   // Add debug output
   if (!setup.isValidCloud) {
       outColor = vec3(1.0, 0.0, 0.0);  // Red = invalid
   }
   ```

---

## 9️⃣ **Lighting Looks Wrong**

### ❌ Problem:
Clouds too bright/dark, lighting doesn't match time of day.

### ✅ Solution:

**Check light transmittance values:**
```glsl
// In GetLightTransmittance(), line ~180
// These constants control atmospheric extinction:
vec3(5.802e-6, 13.558e-6, 33.100e-6)    // Rayleigh scattering
vec3(3.996e-6, 3.996e-6, 3.996e-6)      // Mie scattering
vec3(0.650e-6, 1.881e-6, 0.085e-6)      // Ozone

// Adjust multipliers if needed:
lightExtinctionAmount * 1.0 * multiplier * 1e6  // Change 1e6 to 1e5 for dimmer
```

**Adjust cloud color intensity:**
```cpp
// In Vertex shader, around line 360-365
v_absorbColor = GetSunTransmittance(SunDir.xyz) * sunFade * 100.0;
//                                                              ^^^^^ Try 50.0 or 200.0
```

---

## 🔟 **Fragment Shader Still Compiling Old Code**

### ❌ Problem:
Changes to shader not taking effect.

### ✅ Solution:

**Clear shader cache:**
```cpp
// Your graphics engine likely caches compiled shaders
// Force recompile:

// Option 1: Delete cached files (engine-dependent)
rm ~/.cache/your_game/shaders/*

// Option 2: Force recompile in code
glDeleteProgram(shaderProgram);
shaderProgram = CompileShaders(vertexSrc, fragmentSrc);

// Option 3: Add timestamp uniform to force uniqueness
glUniform1f(glGetUniformLocation(shader, "ShaderDebugTime"), 
    (float)glfwGetTime());
```

---

## 📋 COMPREHENSIVE DEBUG CHECKLIST

Use this when shader still not working:

```cpp
// 1. Check compilation
if (!CheckShaderCompilation(shader)) {
    std::cerr << "Shader compile error: " << GetShaderError(shader) << std::endl;
    return false;
}

// 2. Check uniforms bound
CheckUniformBinding(shader, "Time");
CheckUniformBinding(shader, "WorldOrigin");
CheckUniformBinding(shader, "DimensionID");
CheckUniformBinding(shader, "SunDir");
CheckUniformBinding(shader, "MoonDir");

// 3. Check textures
CheckTextureBinding(shader, "s_SceneDepth", 0);
CheckTextureBinding(shader, "s_DiffuseLighting", 1);
CheckTextureBinding(shader, "s_CausticsTexture", 2);
CheckTextureBinding(shader, "s_ScatteringBuffer", 3);

// 4. Check varyings match
CheckVaryingMatch(vertexShader, fragmentShader);

// 5. Test with minimal clouds
const bool ENABLE_CLOUDS = false;  // Disable first
// Then gradually enable features
```

---

## 🆘 STILL STUCK?

**Create minimal test case:**

```glsl
// Test 1: Just output depth
void main() {
    float depth = texture(s_SceneDepth, v_texcoord0.xy).r;
    bgfx_FragData0 = vec4(vec3(depth), 1.0);
}

// Test 2: Just output diffuse
void main() {
    vec3 diffuse = texture(s_DiffuseLighting, v_texcoord0.xy).rgb;
    bgfx_FragData0 = vec4(diffuse, 1.0);
}

// Test 3: Just output world direction
void main() {
    vec3 worldDir = normalize(worldPos.xyz);
    bgfx_FragData0 = vec4(worldDir * 0.5 + 0.5, 1.0);
}
```

If any of these work → that part is OK
If none work → problem is earlier (vertex shader or uniforms)

---

## 📞 NEED MORE HELP?

Provide:
1. Shader compiler error message (full text)
2. Game engine name & version
3. Output screenshot (what you see vs what you expect)
4. GPU info (vendor, driver version)

Then I can provide more specific fixes! 🚀
