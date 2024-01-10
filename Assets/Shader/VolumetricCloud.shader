Shader "ShengFu/VolumetricCloud"{
    Properties{
        _MainTex("Main Texture", 2D) = "white" {}
        [HideInInspector]_BoundBoxMin ("_BoundBoxMin", vector) = (-1, -1, -1, -1)
        [HideInInspector]_BoundBoxMax ("_BoundBoxMax", vector) = (1, 1, 1, 1)
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
            #define random(seed) sin(seed * 641.5467987313875 + 1.943856175)

            // Box or Sphere
            half4 _BaseColor;
            float3 _Center;
            float3 _BoundMin;
            float3 _BoundMax;
            float3 _Dimensions;
            float3 _BoundBoxMin;
            float3 _BoundBoxMax;
            float4 _CloudHeightRange;

            // RayMarching
            float _RayOffsetStrength;
            float  _StepCount;
            float _RandomNumber;
            float _HeightCurveWeight;
            float _DensityScale3D;
            float _Absorption;
            float3 _DensityNoiseScale;
            float3 _DensityNoiseOffset;
            float _DensityThreshold;
            float _LightMarchStep;
            float _LightAbsorption;

            // 散射函数
            float4 _PhaseParams;
            float _DarknessThreshold;
            float _HenyeyBlend;
            float _HenyeyG;

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
            sampler2D _WeatherMap;
            sampler2D _HeightCurveA;
            sampler2D _HeightCurveB;
            sampler2D _BlueNoise;
            sampler2D _MaskNoise;
            sampler3D _Noise3DA;
            sampler3D _Noise3DB;
            float _Noise2DaSpeed;
            float _Noise3DaSpeed;
            float _Noise2DWeight;

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

            float3 GetWorldPosition(float2 uv, float3 viewVec)
            {
                float depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;//采样深度图
                depth = Linear01Depth(depth, _ZBufferParams); //转换为线性深度
                float3 viewPos = viewVec * depth; //获取实际的观察空间坐标（插值后）
                float3 worldPos = mul(unity_CameraToWorld, float4(viewPos,1)).xyz; //观察空间-->世界空间坐标
                return worldPos;
            }

            float2 squareUV(float2 uv) {
                float width = _ScreenParams.x;
                float height =_ScreenParams.y;
                //float minDim = min(width, height);
                float scale = 1000;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2 (x/scale, y/scale);
            }

            // float GetLightAttenuation(float3 position)
            // {
            //     float4 shadowPos = TransformWorldToShadowCoord(position); //把采样点的世界坐标转到阴影空间
            //     float intensity = MainLightRealtimeShadow(shadowPos); //进行shadow map采样
            //     return intensity; //返回阴影值
            // }

            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir){
                /*  通过boundsMin和boundsMax锚定一个长方体包围盒
                    从rayOrigin朝rayDir发射一条射线，计算从rayOrigin到包围盒表面的距离，以及射线在包围盒内部的距离
                    关于更多该算法可以参考：https://jcgt.org/published/0007/03/04/ 
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

            //射线与球体相交, x 到球体最近的距离， y 穿过球体的距离
            //原理是将射线方程(x = o + dl)带入球面方程求解(|x - c|^2 = r^2)
            float2 RaySphereDst(float3 sphereCenter, float sphereRadius, float3 pos, float3 rayDir)
            {
                float3 oc = pos - sphereCenter;
                float b = dot(rayDir, oc);
                float c = dot(oc, oc) - sphereRadius * sphereRadius;
                float t = b * b - c;//t > 0有两个交点, = 0 相切， < 0 不相交
                
                float delta = sqrt(max(t, 0));
                float dstToSphere = max(-b - delta, 0);
                float dstInSphere = max(-b + delta - dstToSphere, 0);
                return float2(dstToSphere, dstInSphere);
            }

            //射线与云层相交, x到云层的最近距离, y穿过云层的距离
            //通过两个射线与球体相交进行计算
            float2 RayCloudLayerDst(float3 sphereCenter, float earthRadius, float heightMin, float heightMax, float3 pos, float3 rayDir, bool isShape = true)
            {
                float2 cloudDstMin = RaySphereDst(sphereCenter, heightMin + earthRadius, pos, rayDir);
                float2 cloudDstMax = RaySphereDst(sphereCenter, heightMax + earthRadius, pos, rayDir);
                
                //射线到云层的最近距离
                float dstToCloudLayer = 0;
                //射线穿过云层的距离
                float dstInCloudLayer = 0;
                
                //形状步进时计算相交
                if (isShape)
                {
                    
                    //在地表上
                    if (pos.y <= heightMin)
                    {
                        float3 startPos = pos + rayDir * cloudDstMin.y;
                        //开始位置在地平线以上时，设置距离
                        if (startPos.y >= 0)
                        {
                            dstToCloudLayer = cloudDstMin.y;
                            dstInCloudLayer = cloudDstMax.y - cloudDstMin.y;
                        }
                        return float2(dstToCloudLayer, dstInCloudLayer);
                    }
                    
                    //在云层内
                    if (pos.y > heightMin && pos.y <= heightMax)
                    {
                        dstToCloudLayer = 0;
                        dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x: cloudDstMax.y;
                        return float2(dstToCloudLayer, dstInCloudLayer);
                    }
                    
                    //在云层外
                    dstToCloudLayer = cloudDstMax.x;
                    dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x - dstToCloudLayer: cloudDstMax.y;
                }
                else//光照步进时，步进开始点一定在云层内
                {
                    dstToCloudLayer = 0;
                    dstInCloudLayer = cloudDstMin.y > 0 ? cloudDstMin.x: cloudDstMax.y;
                }
                
                return float2(dstToCloudLayer, dstInCloudLayer);
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

            //Henyey-Greenstein相位函数
            float HenyeyGreenstein(float angle, float g)
            {
                float g2 = g * g;
                return(1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * angle, 1.5));
            }

            //两层Henyey-Greenstein散射，使用Max混合。同时兼顾向前 向后散射
            float HGScatterMax(float angle, float g_1, float intensity_1, float g_2, float intensity_2)
            {
                return max(intensity_1 * HenyeyGreenstein(angle, g_1), intensity_2 * HenyeyGreenstein(angle, g_2));
            }

            //两层Henyey-Greenstein散射，使用Lerp混合。同时兼顾向前 向后散射
            float HGScatterLerp(float angle, float g_1, float g_2, float weight)
            {
                return lerp(HenyeyGreenstein(angle, g_1), HenyeyGreenstein(angle, g_2), weight);
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

            //在三个值间进行插值, value1 -> value2 -> value3， offset用于中间值(value2)的偏移
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

                float4 shapeNoise = tex3Dlod(_Noise3DA, float4(uvwShape + (maskNoise.r * _xy_Speed_zw_Warp.z * 0.1), 0));
                float4 detailNoise = tex3Dlod(_Noise3DB, float4(uvwDetail + (shapeNoise.r * _xy_Speed_zw_Warp.w * 0.1), 0));

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

                // float noise = 0;
                // float4 heightCurveUV = 0;
                // heightCurveUV.x = (position.y - _BoundMin.y) / (_BoundMax.y - _BoundMin.y);
                // float heightCurveA = tex2Dlod(_HeightCurveA, heightCurveUV);
                // float heightCurveB = tex2Dlod(_HeightCurveB, heightCurveUV);

                // // 2D NoiseB 作为高度曲线的采样权重
                // // float4 noise2DbUV = float4(position.xz, 0, 0);
                // // float noise2Db = tex2Dlod(_WeatherMap, noise2DbUV);
                // // float heightCurve = max(0,lerp(heightCurveA, heightCurveB, noise2Db));
                // float heightCurve = max(0,lerp(heightCurveB, heightCurveA, _HeightCurveWeight));
                // // float heightCurve = max(0,heightCurveA);

                // // 2D NoiseA 作为噪声浓度 占比 55%
                // // float4 weatherMap = tex2Dlod(_WeatherMap, float4(uv + float2(speedShape * 0.4, 0), 0, 0));
                // float4 noise2DaUV = float4(position.xz, 0, 0);
                // noise2DaUV.xy += _Time.y * _Noise2DaSpeed;
                // noise += tex2Dlod(_MaskNoise, noise2DaUV) * _Noise2DWeight; 

                // // 3D NoiseA 作为噪声浓度 占比 25%
                // float3 noise3DaUV = position * _DensityNoiseScale * 0.01 + _DensityNoiseOffset * 0.01;
                // noise3DaUV.xyz += _Time.y * _Noise3DaSpeed;
                // noise += tex3D(_Noise3DA, noise3DaUV).r * _DensityScale3D ;

                // // 3D NoiseB 作为噪声浓度 占比 20%
                // float3 noise3DbUV = position * _DensityNoiseScale * 0.02 + _DensityNoiseOffset * 0.02;
                // noise += tex3D(_Noise3DB, noise3DbUV).r * (1 - _DensityScale3D) ;


                // noise *= heightCurve;
                // float density = max(0, noise - _DensityThreshold);
                // return density;
            }

            float lightMarching(float3 position, int stepCount = 8){
                /* sample density from given point to light 
                within target step count */

                // URP的主光源位置的定义名字换了一下
                float3 dirToLight = _MainLightPosition.xyz;

                /* 这里的给传入的方向反向了一下是因为，rayBoxDst的计算是要从
                目标点到体积，而采样时，则是反过来，从position出发到主光源*/
                float dstInsideBox = rayBoxDst(_BoundMin, _BoundMax, position, 1/dirToLight).y;

                // 采样
                float stepSize = dstInsideBox / stepCount;
                float totalDensity = 0;
                float3 stepVec = dirToLight * stepSize;
                [unroll(8)]
                for(int i = 0; i < stepCount; i ++){
                    position += stepVec;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }
                // 光照强度
                float transmittance = BeerPowder(totalDensity,_LightAbsorption);
                //云层颜色
                float3 cloudColor = Interpolation3(_ColorDark.rgb, _ColorCentral.rgb, _ColorBright.rgb, saturate(transmittance), _ColorCentralOffset);
                float3 lightTransmittance = _DarknessThreshold + (1.0 - _DarknessThreshold) * cloudColor ;
                return lightTransmittance;
            }

            float lightMarching(float sphereCenter,float sphereRadius,float3 position, int stepCount = 8){
                // URP的主光源位置的定义名字换了一下
                float3 dirToLight = _MainLightPosition.xyz;
                float dstInsideCloud = RaySphereDst(sphereCenter, sphereRadius, position, 1 / dirToLight).y;

                // 采样
                float stepSize = dstInsideCloud / stepCount;
                float totalDensity = 0;
                float3 stepVec = dirToLight * stepSize;
                [unroll(8)]
                for(int i = 0; i < stepCount; i ++){
                    position += stepVec;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }
                return totalDensity;
            }

            struct vertexInput{
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };

            struct vertexOutput{
                float4 pos: SV_POSITION;
                float2 uv: TEXCOORD0;
                float3 viewVec : TEXCOORD1;
            };

            vertexOutput Vertex(vertexInput v){
                vertexOutput o;
                o.pos = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                float3 ndcPos = float3(v.uv.xy * 2.0 - 1.0, 1); //直接把uv映射到ndc坐标
                float far = _ProjectionParams.z; //获取投影信息的z值，代表远平面距离
                float3 clipVec = float3(ndcPos.x, ndcPos.y, ndcPos.z * -1) * far; //裁切空间下的视锥顶点坐标
                o.viewVec = mul(unity_CameraInvProjection, clipVec.xyzz).xyz; //观察空间下的视锥向量
                return o;
            }

            half4 Pixel(vertexOutput IN): SV_TARGET{
                
                // 重建世界坐标viewVec
                // float3 worldPosition = GetWorldPosition(IN.pos);
                float3 worldPosition = GetWorldPosition(IN.uv,IN.viewVec);
                float3 rayPosition = _WorldSpaceCameraPos.xyz;
                float3 worldViewVector = worldPosition - rayPosition;
                float3 rayDir = normalize(worldViewVector);

                // 解决遮挡关系
                _BoundMin = float3(_Center.x - _Dimensions.x/2 , _Center.y - _Dimensions.z/2 , _Center.z - _Dimensions.y/2);
                _BoundMax = float3(_Center.x + _Dimensions.x/2 , _Center.y + _Dimensions.z/2 , _Center.z + _Dimensions.y/2);
                float2 rayBoxInfo = rayBoxDst(_BoundMin, _BoundMax, rayPosition, rayDir);
                float dstToBox = rayBoxInfo.x;
                float dstInsideBox = rayBoxInfo.y;
                float dstToOpaque = length(worldViewVector);
                float dstLimit = min(dstToOpaque - dstToBox, dstInsideBox);


                // 地球半径在6,357km到6,378km
                // float earthRadius = 1000;
                // // 地球中心坐标, 使水平行走永远不会逃出地球, 高度0为地表,
                // float3 sphereCenter = float3(rayPosition.x, earthRadius, rayPosition.z);
                // // 包围盒缩放
                // float boundBoxScaleMax = 1;
                // // 包围盒位置
                // float3 boundBoxPosition = (_BoundBoxMax + _BoundBoxMin) / 2.0;

                // float2 dstCloud = RayCloudLayerDst(sphereCenter, earthRadius, _CloudHeightRange.x, _CloudHeightRange.y, rayPosition, worldViewVector);
                // float dstToCloud = dstCloud.x;
                // float dstInCloud = dstCloud.y;
                // float dstLimitCloud = min(length(worldViewVector) - dstToCloud, dstInCloud);


                // 添加抖动
                float seed = random((_Dimensions.y * IN.uv.y + IN.uv.x) * _Dimensions.x + _RandomNumber);
                float buleNoise = tex2Dlod(_BlueNoise,float4(squareUV(IN.uv*3),0,0)).r;
                buleNoise *= _RayOffsetStrength;

                //向灯光方向的散射更强一些
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, IN.uv);
                //世界空间坐标
                float3 worldPos = ComputeWorldSpacePosition(IN.uv, depth, UNITY_MATRIX_I_VP);
                //世界空间相机方向
                float3 worldViewDir = normalize(worldPos - rayPosition.xyz);
                Light mainLight = GetMainLight();
                float cosAngle = dot(worldViewDir, mainLight.direction);
                float3 phaseVal = phase(cosAngle); //当前视角方向和灯光方向而得出的米氏散射近似结果(云的白色)
                // float3 phaseVal = hg(cosAngle,_HenyeyG); //当前视角方向和灯光方向而得出的米氏散射近似结果(云的白色)

                float3 entryPoint = rayPosition + rayDir * dstToBox;     // 采样起点
                // float stepSize = dstInsideBox / _StepCount ;             // 步长
                float stepSize = dstInsideBox / _StepCount ;             // 步长
                float3 stepVec = stepSize * rayDir;                      // 步长 * 方向
                // float totalDensity = 0;                                  // 浓度积分
                float dstTravelled = buleNoise;                                  // 已经走过的距离
                float3 currentPoint = entryPoint;                        // 当前点
                float lightIntensity = 0;                                
                float3 lightEnergy = 0;          // 总亮度
                float transmittance = 1.0; // 光照衰减
                
                [unroll(64)]
                for(int i = 0; i < _StepCount; i++){
                    if(dstTravelled < dstLimit){
                        currentPoint += stepVec;
                        float density = sampleDensity(currentPoint);// * (1 + buleNoise);//(1 + seed * 0.4);
                        if (density > 0.01){
                            float lightTransmittance = lightMarching(currentPoint, _LightMarchStep);		// 步进默认为8次
                            lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                            transmittance *= Beer(density * stepSize,_Absorption);
                            // totalDensity += Dx;
                            // float lightPathDensity = lightMarching(sphereCenter,earthRadius,currentPoint, _LightMarchStep);		// 步进默认为8次
                            // lightIntensity += exp(-(lightPathDensity * _LightAbsorption + totalDensity * _Absorption)) * Dx; // https://zhuanlan.zhihu.com/p/533853808
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
                // 采样主纹理
                // half4 albedo = _MainTex.Sample(sampler_MainTex, IN.uv);
                // float3 cloudColor = _MainLightColor.xyz * lightIntensity * _BaseColor.xyz;
                // return half4(albedo * exp(-totalDensity * _Absorption) + cloudColor, 1);
                // return half4(albedo * transmittance + lightEnergy, transmittance);
            }
            ENDHLSL
        }
    }
}