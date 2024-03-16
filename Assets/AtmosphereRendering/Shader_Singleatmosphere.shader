Shader "ShengFu/SingleAtmosphere"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "white" {}
        // _AtmosphereHeight ("AtmosphereHeight", float) = 80000.0
        // _PlanetRadius ("PlanetRadius",float) = 6371000.0
        // _DensityScaleHeight ("DensityScaleHeight",vector) = (7994.0, 1200.0, 0, 0)
        // _RayleighSct ("RayleighSct",vector) = (5.8, 13.5, 33.1, 0.0) 
        // _MieSct("MieSct",vector) = (2.0, 2.0, 2.0, 0.0)
        // _IncomingLight("IncomingLight",color) = (4, 4, 4, 4)
        // _RayleighScatterCoef("RayleighScatterCoef",Range(0, 10)) = 1
        // _RayleighExtinctionCoeft("RayleighExtinctionCoef",Range(0, 10)) = 1
        // _MieScatterCoef("MieScatterCoef",Range(0, 10.0)) = 1
        // _MieExtinctionCoef("MieExtinctionCoef",Range(0, 10.0)) = 1
        // _MieG("MieG",Range(0, 0.999)) = 0.76
        // _DistanceScale("DistanceScale",float) = 1.0
    }

    SubShader
    {
        Cull Off 
        ZWrite Off
        ZTest Always
        Name "MyForwardPass"
        Tags{
            "RenderPipeline" = "UniversalRenderPipeline"
        }
        Pass
        {
            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma vertex vert
            #pragma fragment frag
            
            #define PI 3.14159265359

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;

            static const float _AtmosphereHeight = 80000.0;
            static const float _PlanetRadius = 6371000.0;
            static const float2 _DensityScaleHeight = float4(7994.0, 1200.0, 0, 0);
            
            static const float4 _RayleighSct = float4(5.8, 13.5, 33.1, 0.0);
            static const float4 _MieSct = float4(2.0, 2.0, 2.0, 0.0);

            float _RayleighScatterCoef;
            float3 _ScatteringR;
            float _MieScatterCoef;
            float3 _ScatteringM;
            
            float _RayleighExtinctionCoef;
            float3 _ExtinctionR;
            float _MieExtinctionCoef;
            float3 _ExtinctionM;

            float4 _IncomingLight;
            float _MieG;

            float _SunIntensity;
            float _DistanceScale;

            float3 _LightDir;
            float4x4 _InverseViewMatrix;
            float4x4 _InverseProjectionMatrix;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };


            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float3 GetWorldPosition(float4 positionHCS){
                float2 UV = positionHCS.xy / _ScaledScreenParams.xy;
                #if UNITY_REVERSED_Z
                    real depth = SampleSceneDepth(UV);
                #else
                    real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(UV));
                #endif
                return ComputeWorldSpacePosition(UV, depth, UNITY_MATRIX_I_VP);
            }


            //-----------------------------------------------------------------------------------------
            // Helper Funcs : RaySphereIntersection
            //-----------------------------------------------------------------------------------------
            float2 RaySphereIntersection(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
            {
                rayOrigin -= sphereCenter;
                float a = dot(rayDir, rayDir);
                float b = 2.0 * dot(rayOrigin, rayDir);
                float c = dot(rayOrigin, rayOrigin) - (sphereRadius * sphereRadius);
                float d = b * b - 4 * a * c;
                if (d < 0)
                {
                    return -1;
                }
                else
                {
                    d = sqrt(d);
                    return float2(-b - d, -b + d) / (2 * a);
                }
            }


            //----- Input
            // position			视线采样点P
            // lightDir			光照方向

            //----- Output : 
            // opticalDepthCP:	dcp
            bool lightSampleing(
                float3 position,							// Current point within the atmospheric sphere
                float3 lightDir,							// Direction towards the sun
                out float2 opticalDepthCP)
            {
                opticalDepthCP = 0;


                float3 rayStart = position;
                float3 rayDir = -lightDir;

                float3 planetCenter = float3(0, -_PlanetRadius, 0);
                float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
                float3 rayEnd = rayStart + rayDir * intersection.y;

                // compute density along the ray
                float stepCount = 50;// 250;
                float3 step = (rayEnd - rayStart) / stepCount;
                float stepSize = length(step);
                float2 density = 0;

                for (float s = 0.5; s < stepCount; s += 1.0)
                {
                    float3 position = rayStart + step * s;
                    float height = abs(length(position - planetCenter) - _PlanetRadius);
                    float2 localDensity = exp(-(height.xx / _DensityScaleHeight));

                    density += localDensity * stepSize;
                }

                opticalDepthCP = density;

                return true;
            }

            //----- Input
            // position			视线采样点P
            // lightDir			光照方向

            //----- Output : 
            //dpa
            //dcp
            bool GetAtmosphereDensityRealtime(float3 position, float3 planetCenter, float3 lightDir, out float2 dpa, out float2 dpc)
            {
                float height = length(position - planetCenter) - _PlanetRadius;
                dpa = exp(-height.xx / _DensityScaleHeight.xy);

                bool bOverGround = lightSampleing(position, lightDir, dpc);
                return bOverGround;
            }

            //----- Input
            // localDensity			rho(h)
            // densityPA
            // densityCP

            //----- Output : 
            // localInscatterR 
            // localInscatterM
            void ComputeLocalInscattering(float2 localDensity, float2 densityPA, float2 densityCP, out float3 localInscatterR, out float3 localInscatterM)
            {
                float2 densityCPA = densityCP + densityPA;

                float3 Tr = densityCPA.x * _ExtinctionR;
                float3 Tm = densityCPA.y * _ExtinctionM;

                float3 extinction = exp(-(Tr + Tm));

                localInscatterR = localDensity.x * extinction;
                localInscatterM = localDensity.y * extinction;
            }

            //----- Input
            // cosAngle			散射角

            //----- Output : 
            // scatterR 
            // scatterM
            void ApplyPhaseFunction(inout float3 scatterR, inout float3 scatterM, float cosAngle)
            {
                // r
                float phase = (3.0 / (16.0 * PI)) * (1 + (cosAngle * cosAngle));
                scatterR *= phase;

                // m
                float g = _MieG;
                float g2 = g * g;
                phase = (1.0 / (4.0 * PI)) * ((3.0 * (1.0 - g2)) / (2.0 * (2.0 + g2))) * ((1 + cosAngle * cosAngle) / (pow((1 + g2 - 2 * g * cosAngle), 3.0 / 2.0)));
                scatterM *= phase;
            }


            //----- Input
            // rayStart			视线起点 A
            // rayDir			视线方向
            // rayLength		AB 长度
            // planetCenter		地球中心坐标
            // distanceScale	世界坐标的尺寸
            // lightdir			太阳光方向
            // sampleCount		AB 采样次数

            //----- Output : 
            // extinction       T(PA)
            // inscattering:	Inscatering
            float4 IntegrateInscatteringRealtime(float3 rayStart, float3 rayDir, float rayLength, float3 planetCenter, float distanceScale, float3 lightDir, float sampleCount, out float4 extinction)
            {
                float3 step = rayDir * (rayLength / sampleCount);
                float stepSize = length(step) * distanceScale;

                float2 densityPA = 0;
                float3 scatterR = 0;
                float3 scatterM = 0;

                float2 localDensity;
                float2 densityCP;

                float2 prevLocalDensity;
                float3 prevLocalInscatterR, prevLocalInscatterM;
                GetAtmosphereDensityRealtime(rayStart, planetCenter, lightDir, prevLocalDensity, densityCP);

                ComputeLocalInscattering(prevLocalDensity, densityCP, densityPA, prevLocalInscatterR, prevLocalInscatterM);

                // P - current integration point
                // A - camera position
                // C - top of the atmosphere
                [loop]
                for (float s = 1.0; s < sampleCount; s += 1)
                {
                    float3 p = rayStart + step * s;

                    GetAtmosphereDensityRealtime(p, planetCenter, lightDir, localDensity, densityCP);
                    densityPA += (localDensity + prevLocalDensity) * (stepSize / 2.0);
                    float3 localInscatterR, localInscatterM;
                    ComputeLocalInscattering(localDensity, densityCP, densityPA, localInscatterR, localInscatterM);

                    scatterR += (localInscatterR + prevLocalInscatterR) * (stepSize / 2.0);
                    scatterM += (localInscatterM + prevLocalInscatterM) * (stepSize / 2.0);

                    prevLocalInscatterR = localInscatterR;
                    prevLocalInscatterM = localInscatterM;

                    prevLocalDensity = localDensity;
                }

                float3 m = scatterM;
                // phase function
                ApplyPhaseFunction(scatterR, scatterM, dot(rayDir, -lightDir.xyz));
                //scatterR = 0;
                float3 lightInscatter = (scatterR * _ScatteringR + scatterM * _ScatteringM) * _IncomingLight.xyz;
                //lightInscatter += RenderSun(m, dot(rayDir, -lightDir.xyz)) * _SunIntensity;
                float3 lightExtinction = exp(-(densityCP.x * _ExtinctionR + densityCP.y * _ExtinctionM));

                extinction = float4(lightExtinction, 0);
                return float4(lightInscatter, 1);
            }
            
            float3 CalculateCameraVector(float2 coord, float2 screen)
            {
                coord.y = 1.0f - coord.y;
                float2 uv = 2.0f * (coord.xy - float2(0.5f, 0.5f));
                return normalize(float3(uv.x, uv.y, -1.0f));
            }

            float3 GetWorldSpacePosition(float2 i_UV)
            {
                float depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,i_UV).r;

                float4 positionViewSpace = mul(_InverseProjectionMatrix, float4(2.0 * i_UV - 1.0, depth, 1.0));
                positionViewSpace /= positionViewSpace.w;


                float3 positionWorldSpace = mul(_InverseViewMatrix, float4(positionViewSpace.xyz, 1.0)).xyz;
                return positionWorldSpace;
            }

            float4 frag(v2f i) : SV_Target
            {
                _ScatteringR = _RayleighSct * 0.000001 * _RayleighScatterCoef;
                _ScatteringM = _MieSct * 0.00001 * _MieScatterCoef;
                _ExtinctionR = _RayleighSct * _RayleighExtinctionCoef;
                _ExtinctionM = _MieSct * _MieExtinctionCoef;
                _LightDir = GetMainLight().direction;
                
                float deviceZ = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,i.uv).r;//采样深度图
                deviceZ = Linear01Depth(deviceZ, _ZBufferParams); //转换为线性深度
                // float deviceZ = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);

                float3 positionWorldSpace = GetWorldSpacePosition(i.uv);

                float3 rayStart = _WorldSpaceCameraPos;
                float3 rayDir = positionWorldSpace - _WorldSpaceCameraPos;
                float rayLength = length(rayDir);
                rayDir /= rayLength;

                if (deviceZ < 0.000001)
                {
                    rayLength = 1e20;
                }


                float3 planetCenter = float3(0, -_PlanetRadius, 0);
                float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);

                rayLength = min(intersection.y, rayLength);

                intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius);
                if (intersection.x > 0){
                    rayLength = min(intersection.x, rayLength);
                }

                float4 extinction;
                _SunIntensity = 0;

                float4 FinalResult = 0;
                if (deviceZ < 0.000001)
                {		
                    float4 inscattering = IntegrateInscatteringRealtime(rayStart, rayDir, rayLength, planetCenter, 1, _LightDir, 16, extinction);
                    FinalResult = inscattering;	
                }
                else
                {
                    float4 inscattering = IntegrateInscatteringRealtime(rayStart, rayDir, rayLength, planetCenter, _DistanceScale, _LightDir, 16, extinction);
                    float4 sceneColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex,i.uv);	

                    FinalResult = sceneColor * extinction + inscattering;		
                }
                return FinalResult;
            }
            ENDHLSL
        }
    }
}