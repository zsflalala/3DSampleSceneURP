Shader "Hidden/RW/VolumetricLight"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}

    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM

            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT // 柔化阴影，得到软阴影

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            
            // Boilerplate code, we aren't doind anything with our vertices or any other input info,
            // because technically we are working on a quad taking up the whole screen
            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;
            real3 _SunDirection;
     
            //We will set up these uniforms from the ScriptableRendererFeature in the future
            real _Scattering = -0.4;
            real _Steps=25;
            real _MaxDistance =75;

            //This function will tell us if a certain point in world space coordinates is in light or shadow of the main light
            real ShadowAtten(real3 worldPosition)
            {
                return MainLightrealtimeShadow(TransformWorldToShadowCoord(worldPosition));
            }

            //Unity already has a function that can reconstruct world space position from depth
            real3 GetWorldPos(real2 uv){
                #if UNITY_REVERSED_Z
                    real depth = SampleSceneDepth(uv);
                #else
                    // Adjust z to match NDC for OpenGL
                    real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(uv));
                #endif
                return ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
            }

            // Mie scaterring approximated with Henyey-Greenstein phase function.
            real ComputeScattering(real lightDotView)
            {
                real result = 1.0f - _Scattering * _Scattering;
                result /= (4.0f * PI * pow(1.0f + _Scattering * _Scattering - (2.0f * _Scattering) *      lightDotView, 1.5f));
                return result;
            }

            //standart hash
            real random( real2 p ){
                return frac(sin(dot(p, real2(41, 289)))*45758.5453 )-0.5; 
            }
            real random01( real2 p ){
                return frac(sin(dot(p, real2(41, 289)))*45758.5453 ); 
            }
            
            //from Ronja https://www.ronja-tutorials.com/post/047-invlerp_remap/
            real invLerp(real from, real to, real value){
                return (value - from) / (to - from);
            }
            real remap(real origFrom, real origTo, real targetFrom, real targetTo, real value){
                real rel = invLerp(origFrom, origTo, value);
                return lerp(targetFrom, targetTo, rel);
            }

            //this implementation is loosely based on http://www.alexandre-pestana.com/volumetric-lights/ 
            //and https://fr.slideshare.net/BenjaminGlatzel/volumetric-lighting-for-many-lights-in-lords-of-the-fallen

            // #define MIN_STEPS 25

            real frag (v2f i) : SV_Target
            {
                //first we get the world space position of every pixel on screen
                real3 worldPos = GetWorldPos(i.uv);             

                //we find out our ray info, that depends on the distance to the camera
                real3 startPosition = _WorldSpaceCameraPos;
                real3 rayVector = worldPos- startPosition;
                real3 rayDirection =  normalize(rayVector);
                real rayLength = length(rayVector);

                if(rayLength>_MaxDistance){
                    rayLength=_MaxDistance;
                    worldPos= startPosition+rayDirection*rayLength;
                }

                //We can limit the amount of steps for close objects
                // steps= remap(0,_MaxDistance,MIN_STEPS,_Steps,rayLength);  
                //or
                // steps= remap(0,_MaxDistance,0,_Steps,rayLength);   
                // steps = max(steps,MIN_STEPS);

                real stepLength = rayLength / _Steps;
                real3 step = rayDirection * stepLength;
                real3 currentPosition = startPosition;
                real accumFog = 0;
                
                 //we ask for the shadow map value at different depths, if the sample is in light we compute the contribution at that point and add it
                for (real j = 0; j < _Steps-1; j++)
                {
                    real shadowMapValue = ShadowAtten(currentPosition);
                    
                    //if it is in light
                    if(shadowMapValue>0){                       
                        real kernelColor = ComputeScattering(dot(rayDirection, _SunDirection)) ;
                        accumFog += kernelColor;
                    }
                    currentPosition += step;
                }
                //we need the average value, so we divide between the amount of samples 
                accumFog /= _Steps;
                
                return accumFog;
            }
            ENDHLSL
        }
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}