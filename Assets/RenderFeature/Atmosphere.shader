Shader "XinYi/Atmosphere"{
    Properties{
        _MainTex("Main Texture", 2D) = "white"{}
        _BaseColor("基本颜色", Color) = (1,1,1,1)
            [Header(RayMarching)][Space]
            _StepCount("步进次数", Range(1,128)) = 32
            _Density("采样密度", Range(0.01,1.0)) = 0.02
            [Header(BoundingBox)][Space]
            //_BoundMin("BoundMin", Vector) = (-100.0,-20.0,-100.0,0.0)
            //_BoundMax("BoundMax", Vector) = (100.0,20.0,100.0,0.0)
            _Center("盒子中心", Vector) = (0.0,0.0,0.0,0.0)
            _Dimensions("盒子长宽高", Vector) = (10.0,10.0,10.0,0.0)
            [Header(Noise)][Space]
            _DensityNoiseTex("噪声贴图", 3D) = "white"{}
        _HeightCurve("高度-密度贴图", 2D) = "white"{}
        _DensityNoiseScale("噪声贴图缩放", Vector) = (5,5,5,0.0)
            _DensityNoiseOffset("噪声贴图偏移", Vector) = (0,0,0,0)
            _DensityThreshold("密度阈值", Range(0, 1)) = 0
            _DensityMultiplier("密度倍数", Range(0,10)) = 1
            [Header(Light)][Space]
            _LightIteration("",Range(0,10)) = 5
            _Absorption("外散射消光度",Range(0.0,10.0)) = 1.0
            _LightAbsorption("内散射消光度",Range(0.0,10.0)) = 1.0
            _LightPower("光照强度",Range(0.0,10.0)) = 1.0
        }
    SubShader{
        Tags{
            "RenderPipeline" = "UniversalRenderPipeline"
            }
        pass{

            Cull Off
                ZTest Always
                ZWrite Off

                HLSLPROGRAM
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

                #pragma vertex vert
                #pragma fragment frag

                Texture2D _MainTex;
            SamplerState sampler_MainTex;
            float4 _BaseColor;
            //float _StepSize;
            float _StepCount;
            float _Density;
            float3 _Center;
            float3 _Dimensions;
            float3 _BoundMin;
            float3 _BoundMax;
            //
            sampler3D _DensityNoiseTex;
            sampler2D _HeightCurve;
            float3 _DensityNoiseScale;
            float3 _DensityNoiseOffset;
            float _DensityThreshold;
            float _DensityMultiplier;
            //
            float _LightIteration;
            float _Absorption;
            float _LightAbsorption;
            float _LightPower;

            struct vertexInput{
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };
            struct vertexOutput{
                float4 pos: SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            vertexOutput vert(vertexInput v){
                vertexOutput o;
                o.pos = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }
            float3 GetWorldPosition(float3 positionHCS){//裁剪空间→世界空间
                float2 UV = positionHCS.xy / _ScaledScreenParams.xy;
                #if UNITY_REVERSED_Z
                    real depth = SampleSceneDepth(UV);
                #else
                    real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(UV));
                #endif
                    return ComputeWorldSpacePosition(UV, depth, UNITY_MATRIX_I_VP);
            }
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir){
                /*  通过boundsMin和boundsMax锚定一个长方体包围盒
                        从rayOrigin朝rayDir发射一条射线，计算从rayOrigin到包围盒表面的距离，以及射线在包围盒内部的距离
                    */
                float3 t0 = (boundsMin - rayOrigin) / rayDir;
                float3 t1 = (boundsMax - rayOrigin) / rayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }
            float sampleDensity(float3 position){//世界坐标采样3D噪声贴图
                float noise = 0;
                float4 heightCurveUV = 0;
                heightCurveUV.x = (position.y - _BoundMin.y) / (_BoundMax.y - _BoundMin.y);
                float heightCurve = tex2Dlod(_HeightCurve, heightCurveUV);
                float3 uvw = position * _DensityNoiseScale * 0.01 + _DensityNoiseOffset * 0.01;
                noise += tex3D(_DensityNoiseTex, uvw).r* _DensityMultiplier;
                noise *= heightCurve;
                float density = max(0, noise - _DensityThreshold);
                return density;
            }
            float calculateLightPathDensity(float3 position, int stepCount){ 
                float3 dirToLight = _MainLightPosition.xyz;
                float dstInsideBox = rayBoxDst(_BoundMin, _BoundMax, position, 1/dirToLight).y;
                // 采样
                float stepSize = dstInsideBox / stepCount;
                float totalDensity = 0;
                float3 stepVec = dirToLight * stepSize;
                for(int i = 0; i < stepCount; i ++){
                    position += stepVec;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }
                return totalDensity;
            }
            half4 frag(vertexOutput IN): SV_TARGET{
                // 采样主纹理
                half4 originalCol = _MainTex.Sample(sampler_MainTex, IN.uv);
                // // 重建世界坐标
                float3 posWS = GetWorldPosition(IN.pos);
                float3 rayOrigin = _WorldSpaceCameraPos.xyz;//射线起点，摄像机
                float3 worldViewVector = posWS - rayOrigin;
                float3 rayDir = normalize(worldViewVector);
                _BoundMin = float3(_Center.x - _Dimensions.x/2 , _Center.y - _Dimensions.z/2 , _Center.z - _Dimensions.y/2);
                _BoundMax = float3(_Center.x + _Dimensions.x/2 , _Center.y + _Dimensions.z/2 , _Center.z + _Dimensions.y/2);
                float2 hitInfo = rayBoxDst(_BoundMin, _BoundMax, rayOrigin, rayDir);
                float dstToBox = hitInfo.x; //摄像机到盒子距离
                float dstInsideBox = hitInfo.y; //射线在盒中长度
                float dstToOpaque = length(worldViewVector);
                float dstLimit = min(dstToOpaque - dstToBox, dstInsideBox);
                //===================================================================
                // RayMarching
                float3 entryPoint = rayOrigin + rayDir * dstToBox;
                float3 currentPoint = entryPoint; // 采样起点为光线与BoundingBox相交点
                float stepSize = dstInsideBox / _StepCount;
                float3 stepVec = rayDir * stepSize; // 步进向量，它由长度值乘方向得到
                float cloudDensity = 0; // 视线向量上总浓度
                float dstTravelled = 0; // 已走过距离
                float lightIntensity = 0;//光线向量上积累光强
                [unroll(128)]
                for(int i = 0; i < _StepCount; i ++){
                    if(dstTravelled < dstLimit){
                        float Dx = stepSize * sampleDensity(currentPoint);
                        cloudDensity += Dx;
                        //cloudDensity += sampleDensity(currentPoint);
                        float lightPathDensity = calculateLightPathDensity(currentPoint, 8);
                        //float lightInAttenuation = exp(-lightPathDensity * _LightAbsorption);
                        //float lightOutAttenuation = exp(-cloudDensity * _Absorption);
                        lightIntensity += exp(-(lightPathDensity * _LightAbsorption + cloudDensity * _Absorption)) * Dx;
                        dstTravelled += stepSize;
                        currentPoint += stepVec;
                        continue;
                    }
                    break;
                }
                // //return originalCol + cloudDensity;
                // //return originalCol * exp(-cloudDensity * _Absorption);
                // //return half4(cloudColor,1);
                float3 cloudColor = _MainLightColor.xyz * lightIntensity * _BaseColor.xyz * _LightPower;
                return half4(originalCol * exp(-cloudDensity * _Absorption) + cloudColor, 1);
            }
            ENDHLSL
            }
    }
}