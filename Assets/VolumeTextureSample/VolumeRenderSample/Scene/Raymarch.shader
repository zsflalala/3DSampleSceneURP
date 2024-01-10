// Made with Amplify Shader Editor
// Available at the Unity Asset Store - http://u3d.as/y3X 
Shader "Raymarch"
{
    Properties
    {
        [HideInInspector] _AlphaCutoff("Alpha Cutoff ", Range(0, 1)) = 0.5
        [HideInInspector] _EmissionColor("Emission Color", Color) = (1,1,1,1)
        _NumSteps("NumSteps", Float) = 0
        _StepSize("StepSize", Float) = 1
        _DensityScale("DensityScale", Float) = 1
        _Voume("Voume", 3D) = "white" {}
        _Offset("Offset", Vector) = (0,0,0,0)
        _NumLightSteps("NumLightSteps", Float) = 0
        _LightSteSize("LightSteSize", Float) = 0
        _LightAbsorb("LightAbsorb", Float) = 0
        _DarknessThreshold("DarknessThreshold", Float) = 0
        _Transmittance("Transmittance", Float) = 1
        _ForwardScattering("ForwardScattering", range(0.0, 1.0)) = 0.83
        _BackScattering("BackScattering", range(0.0, 1.0)) = 0.3
        _BaseBrightness("BaseBrightness", range(0.0, 1.0)) = 0.8
        _PhaseFactor("PhaseFactor", range(0.0, 1.0)) = 0.15
        [HDR]_Color1("Color 1", Color) = (0,0,0,0)
        [HDR]_Color0("Color 0", Color) = (0,0,0,0)
        [ASEEnd]_LightingSOP("LightingSOP", Vector) = (1,0,1,0)

    }

    SubShader
    {
        LOD 0


        Tags
        {
            "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent"
        }

        Cull Back
        AlphaToMask Off

        Pass
        {

            Name "Forward"
            Tags
            {
                "LightMode"="UniversalForwardOnly"
            }

            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Offset 0 , 0
            ColorMask RGBA


            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderGraphFunctions.hlsl"


            #define ASE_NEEDS_FRAG_WORLD_POSITION


            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 ase_normal : NORMAL;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct VertexOutput
            {
                float4 clipPos : SV_POSITION;
                #if defined(ASE_NEEDS_FRAG_WORLD_POSITION)
                float3 worldPos : TEXCOORD0;
                #endif
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR) && defined(ASE_NEEDS_FRAG_SHADOWCOORDS)
				float4 shadowCoord : TEXCOORD1;
                #endif
                #ifdef ASE_FOG
				float fogFactor : TEXCOORD2;
                #endif

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _Color0;
            float4 _Color1;
            float4 _Offset;
            float3 _LightingSOP;
            float _NumSteps;
            float _StepSize;
            float _DensityScale;
            float _NumLightSteps;
            float _LightSteSize;
            float _LightAbsorb;
            float _DarknessThreshold;
            float _Transmittance;

            float _ForwardScattering;
            float _BackScattering;
            float _BaseBrightness;
            float _PhaseFactor;
            CBUFFER_END
            sampler3D _Voume;

            // Henyey-Greenstein
            float hg(float a, float g)
            {
                float g2 = g * g;
                return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * (a), 1.5));
            }

            float phase(float a)
            {
                float4 phaseParams = float4(_ForwardScattering, _BackScattering, _BaseBrightness, _PhaseFactor);
                float blend = .5;
                float hgBlend = hg(a, phaseParams.x) * (1 - blend) + hg(a, -phaseParams.y) * blend;
                return phaseParams.z + hgBlend * phaseParams.w;
            }


            float3 Raymarch10(float3 rayOrigin, float3 rayDirection, int numSteps, float stepSize, float densityScale,
                              sampler3D Volume, float3 offset, int numLightSteps, float lightStepSize, float3 lightDir,
                              float lightAbsorb, float darknessThreshold, float transmittance)
            {
                float3 scale = float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m11, unity_ObjectToWorld._m22);
                float density = 0;
                float transmission = 0;
                float lightAccumulation = 0;
                float finalLight = 0;
                float cosAngle = dot(SafeNormalize(rayDirection), lightDir);
                float phaseVal = phase(cosAngle);
                for (int i = 0; i < numSteps; i++)
                {
                    rayOrigin += (rayDirection * stepSize);

                    float3 samplePos = rayOrigin + offset;
                    samplePos /= scale;
                    float sampledDensity = tex3D(Volume, samplePos).r;
                    density += sampledDensity * densityScale;
                    //light loop
                    float3 lightRayOrigin = samplePos;
                    for (int j = 0; j < numLightSteps; j++)
                    {
                        lightRayOrigin += lightDir * lightStepSize;
                        float lightDensity = tex3D(Volume, lightRayOrigin).r;
                        lightAccumulation += lightDensity;
                    }
                    float lightTransmission = exp(-lightAccumulation);
                    float shadow = darknessThreshold + lightTransmission * (1.0 - darknessThreshold);
                    finalLight += density * transmittance * shadow * phaseVal;
                    transmittance *= exp(-density * lightAbsorb);
                }
                transmission = exp(-density);
                return float3(finalLight, transmission, 0);
            }


            VertexOutput VertexFunction(VertexInput v)
            {
                VertexOutput o = (VertexOutput)0;

                #ifdef ASE_ABSOLUTE_VERTEX_POS
					float3 defaultVertexValue = v.vertex.xyz;
                #else
                float3 defaultVertexValue = float3(0, 0, 0);
                #endif
                float3 vertexValue = defaultVertexValue;
                #ifdef ASE_ABSOLUTE_VERTEX_POS
					v.vertex.xyz = vertexValue;
                #else
                v.vertex.xyz += vertexValue;
                #endif
                v.ase_normal = v.ase_normal;

                float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
                float4 positionCS = TransformWorldToHClip(positionWS);

                #if defined(ASE_NEEDS_FRAG_WORLD_POSITION)
                o.worldPos = positionWS;
                #endif
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR) && defined(ASE_NEEDS_FRAG_SHADOWCOORDS)
				VertexPositionInputs vertexInput = (VertexPositionInputs)0;
				vertexInput.positionWS = positionWS;
				vertexInput.positionCS = positionCS;
				o.shadowCoord = GetShadowCoord( vertexInput );
                #endif
                #ifdef ASE_FOG
				o.fogFactor = ComputeFogFactor( positionCS.z );
                #endif
                o.clipPos = positionCS;
                return o;
            }


            VertexOutput vert(VertexInput v)
            {
                return VertexFunction(v);
            }


            half4 frag(VertexOutput IN) : SV_Target
            {
                float3 WorldPosition = IN.worldPos;
                float3 rayOrigin10 = WorldPosition;
                float3 rayDirection10 = WorldPosition - _WorldSpaceCameraPos;
                int numSteps10 = (int)_NumSteps;
                float stepSize10 = _StepSize;
                float densityScale10 = _DensityScale;
                sampler3D Volume10 = _Voume;
                float4 transform21 = mul(GetObjectToWorldMatrix(), float4(0, 0, 0, 1));
                float3 scale = float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m11, unity_ObjectToWorld._m22);
                float3 offset10 = (_Offset * scale - transform21).xyz;
                int numLightSteps10 = (int)_NumLightSteps;
                float lightStepSize10 = _LightSteSize;
                float3 normalizeResult36 = normalize(SafeNormalize(_MainLightPosition.xyz));
                float3 lightDir10 = normalizeResult36;
                float lightAbsorb10 = _LightAbsorb;
                float darknessThreshold10 = _DarknessThreshold;
                float transmittance10 = _Transmittance;
                float3 localRaymarch10 = Raymarch10(rayOrigin10, rayDirection10, numSteps10, stepSize10, densityScale10,
                                                    Volume10, offset10, numLightSteps10, lightStepSize10, lightDir10,
                                                    lightAbsorb10, darknessThreshold10, transmittance10);
                float3 break32 = localRaymarch10;
                float temp_output_42_0 = saturate(break32.x);
                float4 lerpResult39 = lerp(_Color0, _Color1,
                                           saturate(pow(saturate((temp_output_42_0 * _LightingSOP.x + _LightingSOP.y)),
                                                        _LightingSOP.z)));

                float3 Color = lerpResult39.rgb;
                Color *= _MainLightColor;
                //Color = break32.x;
                float Alpha = (1.0 - break32.y);

                return half4(Color, Alpha);
            }
            ENDHLSL
        }




    }


}