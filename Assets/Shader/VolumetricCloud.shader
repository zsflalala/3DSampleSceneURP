Shader "ShengFu/VolumetricCloud"{
    Properties{
        _MainTex("Main Texture", 2D) = "white" {}
        [Range(RealTime)]_StratusRange ("层云范围", vector) = (0.1, 0.4, 0, 1)
        [Switch(RealTime)]_StratusFeather ("层云边缘羽化", Range(0, 1)) = 0.2
        [Range(RealTime)]_CumulusRange ("积云范围", vector) = (0.15, 0.8, 0, 1)
        [Switch(RealTime)]_CumulusFeather ("积云边缘羽化", Range(0, 1)) = 0.2
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
            float4 _StratusRange;
            float _StratusFeather;
            float4 _CumulusRange;
            float _CumulusFeather;

            // RayMarching
            float _RayOffsetStrength;
            float  _StepCount;
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

            float lightMarching(float sphereCenter,float sphereRadius,float3 position, int stepCount = 8){
                // URP的主光源位置的定义名字换了一下
                float3 dirToLight = _MainLightPosition.xyz;
                float dstInsideCloud = RaySphereDst(sphereCenter, sphereRadius, position, 1 / dirToLight).y;

                // 采样
                float stepSize = dstInsideCloud / stepCount;
                float totalDensity = 0;
                float3 stepVec = dirToLight * stepSize;
                for(int i = 0; i < stepCount; i ++){
                    position += stepVec;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }
                return totalDensity;
            }

            //重映射
            float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
            {
                return new_min + ((original_value - original_min) / (original_max - original_min)) * (new_max - new_min);
            }
            
            //获取高度比率
            float GetHeightFraction(float3 sphereCenter, float earthRadius, float3 pos, float height_min, float height_max)
            {
                float height = length(pos - sphereCenter) - earthRadius;
                return(height - height_min) / (height_max - height_min);
            }

            //获取云类型密度
            float GetCloudTypeDensity(float heightFraction, float cloud_min, float cloud_max, float feather)
            {
                //云的底部羽化需要弱一些，所以乘0.5
                return saturate(Remap(heightFraction, cloud_min, cloud_min + feather * 0.5, 0, 1)) * saturate(Remap(heightFraction, cloud_max - feather, cloud_max, 1, 0));
            }

            //采样云的密度  isCheaply=true时不采样细节纹理
            float SampleCloudDensity(float3 sphereCenter,float earthRadius,float3 position)
            {   
                float3 stratusInfo = float3(_StratusRange.xy, _StratusFeather);
                float3 cumulusInfo = float3(_CumulusRange.xy, _CumulusFeather);
                float heightFraction = GetHeightFraction(sphereCenter, earthRadius, position, _CloudHeightRange.x, _CloudHeightRange.y);
                
                //采样天气纹理，默认1000km平铺， r 密度, g 吸收率, b 云类型(0~1 => 层云~积云)
                // float2 weatherTexUV = GetWeatherTexUV(dsi.sphereCenter, dsi.position, dsi.weatherTexTiling, dsi.weatherTexRepair);
                // float2 weatherTexUV = position.xz ;
                // float4 weatherData = tex2Dlod(_WeatherMap,float4(weatherTexUV,0,0));
                // weatherData.r = Interpolation3(0, weatherData.r, 1, 0.5);
                // weatherData.b = Interpolation3(0, weatherData.b, 1, 0.5);
                // if (weatherData.r <= 0)
                // {
                //     return 0;
                // }
                
                // //计算云类型密度
                float stratusDensity = GetCloudTypeDensity(heightFraction, stratusInfo.x, stratusInfo.y, stratusInfo.z);
                // float cumulusDensity = GetCloudTypeDensity(heightFraction, cumulusInfo.x, cumulusInfo.y, cumulusInfo.z);
                // float cloudTypeDensity = lerp(stratusDensity, cumulusDensity, weatherData.b);
                // if (cloudTypeDensity <= 0)
                // {
                //     return 0;
                // }
                
                //采样基础纹理
                float4 baseTex = tex3D(_ShapeNoise,position * _ShapeTiling * 0.01 + _DetailTiling * 0.01);
                //构建基础纹理的FBM
                float baseTexFBM = dot(baseTex.gba, float3(0.5, 0.25, 0.125));
                //对基础形状添加细节，通过Remap可以不影响基础形状下添加细节
                float baseShape = Remap(baseTex.r, saturate((1.0 - baseTexFBM) * _DetailNoiseWeight), 1.0, 0, 1.0);
                
                float cloudDensity = baseTex.r * stratusDensity;
                
                float density = cloudDensity * _DensityMultiplier * 0.01;
                
                return max(0,baseTex.r - _DetailNoiseWeight);
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

                float3 cameraPos = GetCameraPositionWS();
                float  earthRadius = 6300000;   //地球半径在6,357km到6,378km
                float3 sphereCenter = float3(cameraPos.x, -earthRadius, cameraPos.z); //地球中心坐标, 使水平行走永远不会逃出地球, 高度0为地表
                float2 dstCloud = RayCloudLayerDst(sphereCenter, earthRadius, _CloudHeightRange.x, _CloudHeightRange.y, cameraPos, IN.viewDir);
                float dstToCloud = dstCloud.x;
                float dstInCloud = dstCloud.y;

                float dstToObj = LinearEyeDepth(depth, _ZBufferParams);
                float endPos = dstToCloud + dstInCloud;  //穿出云覆盖范围的位置(结束位置)
                
                // float dstToOpaque = length(worldViewDir);
                float dstLimit = min(dstToObj - dstToCloud, dstInCloud);

                Light mainLight = GetMainLight();
                float cosAngle = dot(IN.viewDir, normalize(mainLight.direction));
                float3 phaseVal = phase(cosAngle); //当前视角方向和灯光方向而得出的米氏散射近似结果(云的白色)

                float3 entryPoint = cameraPos + rayDir * dstToCloud;
                float3 currentPoint = entryPoint;
                float stepSize = dstInCloud / _StepCount; 
                float3 stepVec = stepSize * rayDir;
                float buleNoise = tex2Dlod(_BlueNoise,float4(squareUV(IN.uv*3),0,0)).r;
                float dstTravelled = dstToCloud + buleNoise * _RayOffsetStrength;                       
                float3 lightEnergy = 0;
                float transmittance = 1.0; 

                // 如果步进到被物体遮挡,或穿出云覆盖范围时,跳出循环
                if (dstToObj <= dstTravelled || endPos <= dstTravelled)
                {
                    return float4(1,0,0, 1.0);
                }
                
                [unroll(32)]
                for(int i = 0; i < _StepCount; i++){
                    
                    currentPoint += stepVec;
                    
                    // float density = sampleDensity(currentPoint);
                    float density = SampleCloudDensity(sphereCenter, earthRadius, currentPoint);
                    if (density > 0.01){
                        // lightEnergy.b += 0.01;
                        // lightEnergy.g += 0.01;
                        // float lightTransmittance = lightMarching(currentPoint);		// 步进默认为8次
                        lightEnergy += density * stepSize * transmittance;// * lightTransmittance * phaseVal;
                        transmittance *= Beer(density * stepSize,_Absorption);
                        if (transmittance < 0.01)
                            break;
                    }
                    dstTravelled += stepSize;
                    
                    //如果步进到被物体遮挡,或穿出云覆盖范围时,跳出循环
                    if (dstToObj <= dstTravelled || endPos <= dstTravelled)
                    {
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