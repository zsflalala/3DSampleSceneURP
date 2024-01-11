Shader "ShengFu/VolumetricCloud"{
    Properties{
        _MainTex("Main Texture", 2D) = "white" {}
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma vertex Vertex
            #pragma fragment Pixel

            // Box 
            float3 _Center;
            float3 _BoundMin;
            float3 _BoundMax;
            float3 _Dimensions;

            // Sphere
            float4 _CloudHeightRange;

            // RayMarching
            float _RayOffsetStrength;
            float  _StepCount;
            float  _step;
            float  _rayStep;
            float _HeightCurveWeight;
            float _Absorption;
            float _LightAbsorption;

            // 散射函数
            float4 _PhaseParams;
            float _DarknessThreshold;
            float _HenyeyBlend;

            // 云颜色
            half4 _ColorBright;
            half4 _ColorCentral;
            half4 _ColorDark;
            float _ColorCentralOffset;


            // 云高度密度、纹理、细节
            Texture2D _MainTex;
            SamplerState sampler_MainTex;
            TEXTURE2D(_CameraColorTexture);
	        SAMPLER(sampler_CameraColorTexture);
            
            // sampler2D _HeightCurveA;
            // sampler2D _HeightCurveB;
            sampler2D _BlueNoise;
            sampler2D _MaskNoise;
            sampler2D _WeatherMap;
            sampler3D _ShapeNoise;
            sampler3D _DetailNoise;

            float4 _xy_Speed_zw_Warp;
            float _ShapeTiling;
	        float _DetailTiling;
            float _DensityMultiplier;
            float4 _ShapeNoiseWeights;
            float _DensityOffset;
            float _DetailWeights;
            float _DetailNoiseWeight;

            

            float3 GetWorldPosition(float4 positionHCS){
                float2 UV = positionHCS.xy / _ScaledScreenParams.xy;
                #if UNITY_REVERSED_Z
                    real depth = SampleSceneDepth(UV);
                #else
                    real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(UV));
                #endif
                return ComputeWorldSpacePosition(UV, depth, UNITY_MATRIX_I_VP);
            }

            float3 GetWorldPosition(float2 uv, float3 viewDir)
            {
                float depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;//采样深度图
                depth = Linear01Depth(depth, _ZBufferParams); //转换为线性深度
                float3 viewPos = viewDir * depth; //获取实际的观察空间坐标（插值后）
                float3 worldPos = mul(unity_CameraToWorld, float4(viewPos,1)).xyz; //观察空间-->世界空间坐标
                return worldPos;
            }

            float2 squareUV(float2 uv) {
                float width = _ScreenParams.x;
                float height =_ScreenParams.y;
                float scale = 1000;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2 (x/scale, y/scale);
            }

            float GetLightAttenuation(float3 position)
            {
                float4 shadowPos = TransformWorldToShadowCoord(position); //把采样点的世界坐标转到阴影空间
                float intensity = MainLightRealtimeShadow(shadowPos); //进行shadow map采样
                return intensity; //返回阴影值
            }

            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir){
                float3 t0 = (boundsMin - rayOrigin) / rayDir;
                float3 t1 = (boundsMax - rayOrigin) / rayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                float dstToCloud = max(0, dstA);
                float dstInCloud = max(0, dstB - dstToCloud);
                return float2(dstToCloud, dstInCloud);
            }

            // Henyey-Greenstein
            float hg(float a, float g) {
                float g2 = g * g;
                return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * (a), 1.5));
            }

            // 两层Henyey-Greenstein相位函数混合
            float phase(float a) {
                float blend = _HenyeyBlend;
                float hgBlend = hg(a, _PhaseParams.x) * (1 - blend) + hg(a, -_PhaseParams.y) * blend;
                return _PhaseParams.z + hgBlend * _PhaseParams.w;
            }

            //Beer衰减
            float Beer(float density, float absorptivity = 1)
            {
                return exp(-density * absorptivity);
            }

            //粉糖效应，模拟云的内散射影响
            float BeerPowder(float density, float absorptivity = 1)
            {
                return 2.0 * exp(-density * absorptivity) * (1.0 - exp(-2.0 * density));
            }

            //在三个值间进行插值, value1 -> value2 -> value3， offset用于中间值(value2)的偏移
            float Interpolation3(float value1, float value2, float value3, float x, float offset = 0.5)
            {
                offset = clamp(offset, 0.0001, 0.9999);
                return lerp(lerp(value1, value2, min(x, offset) / offset), value3, max(0, x - offset) / (1.0 - offset));
            }

            float3 Interpolation3(float3 value1, float3 value2, float3 value3, float x, float offset = 0.5)
            {
                offset = clamp(offset, 0.0001, 0.9999);
                return lerp(lerp(value1, value2, min(x, offset) / offset), value3, max(0, x - offset) / (1.0 - offset));
            }

            // 重映射
            float remap(float original_value, float original_min, float original_max, float new_min, float new_max)
            {
                return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
            }
    
            float sampleDensity(float3 position){
                float3 boundsCentre = (_BoundMax + _BoundMin) * 0.5;
		        float3 size = _BoundMax - _BoundMin;
                float speedShape = _Time.y * _xy_Speed_zw_Warp.x;
                float speedDetail = _Time.y * _xy_Speed_zw_Warp.y;

                float3 uvwShape = position * _ShapeTiling + float3(speedShape, speedShape * 0.2, 0);
                float3 uvwDetail = position * _DetailTiling + float3(speedDetail, speedDetail * 0.2, 0);

                float2 uv = (size.xz * 0.5f + (position.xz - boundsCentre.xz)) / max(size.x, size.z);

                float4 maskNoise = tex2Dlod(_MaskNoise, float4(uv + float2(speedShape * 0.5, 0), 0, 0));
                float4 weatherMap = tex2Dlod(_WeatherMap, float4(uv + float2(speedShape * 0.4, 0), 0, 0));

                float4 shapeNoise = tex3Dlod(_ShapeNoise, float4(uvwShape + (maskNoise.r * _xy_Speed_zw_Warp.z * 0.1), 0));
                float4 detailNoise = tex3Dlod(_DetailNoise, float4(uvwDetail + (shapeNoise.r * _xy_Speed_zw_Warp.w * 0.1), 0));

                //边缘衰减
                const float containerEdgeFadeDst = 10;
                float dstFromEdgeX = min(containerEdgeFadeDst, min(position.x - _BoundMin.x, _BoundMax.x - position.x));
                float dstFromEdgeZ = min(containerEdgeFadeDst, min(position.z - _BoundMin.z, _BoundMax.z - position.z));
                float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;

                float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.6);
                float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
                float heightPercent = (position.y - _BoundMin.y) / size.y;
                float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(remap(heightPercent, 1, gMax, 0, 1));
                float heightGradient2 = saturate(remap(heightPercent, 0.0, weatherMap.r, 1, 0)) * saturate(remap(heightPercent, 0.0, gMin, 0, 1));
                heightGradient = saturate(lerp(heightGradient, heightGradient2, _HeightCurveWeight));

                heightGradient *= edgeWeight;

                float4 normalizedShapeWeights = _ShapeNoiseWeights / dot(_ShapeNoiseWeights, 1);
                float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
                float baseShapeDensity = shapeFBM + _DensityOffset * 0.01;


                if (baseShapeDensity > 0)
                {
                    float detailFBM = pow(detailNoise.r, _DetailWeights);
                    float oneMinusShape = 1 - baseShapeDensity;
                    float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
                    float cloudDensity = baseShapeDensity - detailFBM * detailErodeWeight * _DetailNoiseWeight;

                    return saturate(cloudDensity * _DensityMultiplier);
                }
                return 0;
            }

            float lightMarching(float3 position, int stepCount = 8){
                /* sample density from given point to light 
                within target step count */

                // URP的主光源位置的定义名字换了一下
                float3 dirToLight = _MainLightPosition.xyz;

                /* 这里的给传入的方向反向了一下是因为，rayBoxDst的计算是要从
                目标点到体积，而采样时，则是反过来，从position出发到主光源*/
                float dstInCloud = rayBoxDst(_BoundMin, _BoundMax, position, 1/dirToLight).y;

                // 采样
                float stepSize = dstInCloud / stepCount;
                float totalDensity = 0;
                float3 stepVec = dirToLight * stepSize;
                for(int i = 0; i < stepCount; i++){
                    position += stepVec;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }
                float transmittance = BeerPowder(totalDensity,_LightAbsorption);
                float3 cloudColor = Interpolation3(_ColorDark.rgb, _ColorCentral.rgb, _ColorBright.rgb, saturate(transmittance), _ColorCentralOffset);
                float3 lightTransmittance = _DarknessThreshold + (1.0 - _DarknessThreshold) * cloudColor ;
                return lightTransmittance;
            }

            struct vertexInput{
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };

            struct vertexOutput{
                float4 pos: SV_POSITION;
                float2 uv: TEXCOORD0;
                float3 viewDir : TEXCOORD1;
            };

            vertexOutput Vertex(vertexInput v){
                vertexOutput o;
                o.pos = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                float3 ndcPos = float3(v.uv.xy * 2.0 - 1.0, 1); //直接把uv映射到ndc坐标
                float far = _ProjectionParams.z; //获取投影信息的z值，代表远平面距离
                float3 clipVec = float3(ndcPos.x, ndcPos.y, ndcPos.z * -1) * far; //裁切空间下的视锥顶点坐标
                o.viewDir = mul(unity_CameraInvProjection, clipVec.xyzz).xyz; //观察空间下的视锥向量
                return o;
            }

            half4 Pixel(vertexOutput IN): SV_TARGET{
                
                // 重建世界坐标
                // float3 worldPosition = GetWorldPosition(IN.pos);
                // float3 worldPosition = GetWorldPosition(IN.uv,IN.viewDir);
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, IN.uv);
                float3 worldPosition = ComputeWorldSpacePosition(IN.uv, depth, UNITY_MATRIX_I_VP);
                float3 rayPosition = _WorldSpaceCameraPos.xyz;
                float3 worldViewDir = worldPosition - rayPosition;
                float3 rayDir = normalize(worldViewDir);

                // 盒型
                _BoundMin = float3(_Center.x - _Dimensions.x/2 , _Center.y - _Dimensions.z/2 , _Center.z - _Dimensions.y/2);
                _BoundMax = float3(_Center.x + _Dimensions.x/2 , _Center.y + _Dimensions.z/2 , _Center.z + _Dimensions.y/2);
                float2 dstCloud = rayBoxDst(_BoundMin, _BoundMax, rayPosition, rayDir);

                float dstToCloud = dstCloud.x;
                float dstInCloud = dstCloud.y;

                float dstToObj = LinearEyeDepth(depth, _ZBufferParams);
                float dstToOpaque = length(worldViewDir);
                float dstLimit = min(dstToObj - dstToCloud, dstInCloud);

           
                Light mainLight = GetMainLight();
                float cosAngle = dot(IN.viewDir, normalize(mainLight.direction));
                float3 phaseVal = phase(cosAngle); //当前视角方向和灯光方向而得出的米氏散射近似结果(云的白色)

                const float stepCount = 64;
                float3 entryPoint = rayPosition + rayDir * dstToCloud;
                float3 currentPoint = entryPoint;
		        // float stepSize = exp(_step)*_rayStep;
                float stepSize = dstInCloud / _StepCount; 
                float3 stepVec = stepSize * rayDir;
                // 添加抖动
                float buleNoise = tex2Dlod(_BlueNoise,float4(squareUV(IN.uv*3),0,0)).r;
                float dstTravelled = buleNoise * _RayOffsetStrength;                       
                // 散射 总亮度   
                float3 lightEnergy = 0;
                // 透过率
                float transmittance = 1.0; 
                [unroll(32)]
                for(int i = 0; i < _StepCount; i++){
                    if(dstTravelled < dstLimit){
                        currentPoint += stepVec;
                        float density = sampleDensity(currentPoint);
                        if (density > 0.01){
                            float lightTransmittance = lightMarching(currentPoint);		// 步进默认为8次
                            lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                            transmittance *= Beer(density * stepSize,_Absorption);
                            if (transmittance < 0.01)
                                break;
                        }
                        dstTravelled += stepSize;
                    }
                    else{
                        break;
                    }
                }
                float4 color = SAMPLE_TEXTURE2D(_CameraColorTexture, sampler_CameraColorTexture, IN.uv); //当前点原本的颜色
                float4 cloudColor = float4(lightEnergy, transmittance); //(光照的颜色, 原色保持程度)
                color.rgb *= cloudColor.a; //透过率越大则原本颜色越能维持
                color.rgb += cloudColor.rgb; //然后加上光照颜色
                return color;
            }
            ENDHLSL
        }
    }
}