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
            float2 _StratusRange;
            float _StratusFeather;
            float2 _CumulusRange;
            float _CumulusFeather;

            // RayMarching
            float _ShapeMarchLength;
            float _BlueNoiseEffect;
            float  _StepCount;
            float _Absorption;
            // float _LightAbsorption;

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
            SamplerState sampler_CameraColorTexture;
            
            sampler2D _BlueNoise;
            TEXTURE2D(_WeatherMap);
            SAMPLER(sampler_WeatherMap);
            sampler3D _ShapeNoise;
            sampler3D _DetailNoise;

            // sphere
            float _WeatherTiling;
            float _WeatherOffset;
            float _ShapeTiling;
            float _DetailTiling;
            float _DensityMultiplier;
            float _ShapeEffect;
            float _DetailEffect;
            float3 _WindDirection;
            float _WindSpeed;
            float _CloudDensityAdjust;

            

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
                float scale = 10;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2 (x/scale, y/scale);
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
            float SampleCloudDensity(float3 sphereCenter,float earthRadius,float3 position,bool isCheaply = true)
            {   

                float3 stratusInfo = float3(_StratusRange.xy, _StratusFeather);
                float3 cumulusInfo = float3(_CumulusRange.xy, _CumulusFeather);
                float heightFraction = GetHeightFraction(sphereCenter, earthRadius, position, _CloudHeightRange.x, _CloudHeightRange.y);
                //添加风的影响
                float3 windDirection = normalize(_WindDirection);
                float  windSpeed = _WindSpeed;
                float3 wind = windDirection * windSpeed * _Time.y;
                float3 windPosition = position + wind * 100;
                //采样天气纹理，默认1000km平铺， r 密度, g 吸收率, b 云类型(0~1 => 层云~积云)
                // float2 weatherTexUV = GetWeatherTexUV(dsi.sphereCenter, dsi.position, dsi.weatherTexTiling, dsi.weatherTexRepair);
                float2 weatherTexUV = position.xz * _WeatherTiling;
                // float4 weatherData = tex2Dlod(_WeatherMap,float4(weatherTexUV * 0.1 + _WeatherOffset + wind.xz * 0.01,0,0));
                float4 weatherData = SAMPLE_TEXTURE2D_LOD(_WeatherMap, sampler_WeatherMap, weatherTexUV * 0.000001 + _WeatherOffset + wind.xz * 0.01, 0);
                weatherData.r = Interpolation3(0, weatherData.r, 1, _CloudDensityAdjust);
                weatherData.b = Interpolation3(0, weatherData.b, 1, _CloudDensityAdjust);
                if (weatherData.r <= 0)
                {
                    return 0;
                }
                
                //计算云类型密度
                float stratusDensity = GetCloudTypeDensity(heightFraction, stratusInfo.x, stratusInfo.y, stratusInfo.z);
                float cumulusDensity = GetCloudTypeDensity(heightFraction, cumulusInfo.x, cumulusInfo.y, cumulusInfo.z);
                float cloudTypeDensity = lerp(stratusDensity, cumulusDensity, weatherData.b);
                if (cloudTypeDensity <= 0)
                {
                    return 0;
                }

                //云吸收率
                _Absorption = Interpolation3(0, weatherData.g, 1, _CloudDensityAdjust);
                
                //采样基础纹理
                float4 baseTex = tex3D(_ShapeNoise, windPosition * _ShapeTiling * 0.0001);
                //构建基础纹理的FBM
                float baseTexFBM = dot(baseTex.gba, float3(0.5, 0.25, 0.125));
                //对基础形状添加细节，通过Remap可以不影响基础形状下添加细节
                float baseShape = Remap(baseTex.r, saturate((1.0 - baseTexFBM) * _ShapeEffect), 1.0, 0, 1.0);
                
                float cloudDensity = baseShape * weatherData.r * cloudTypeDensity;
                
                if (cloudDensity > 0 && !isCheaply){
                    //细节噪声受更强风的影响，添加稍微向上的偏移
                    windPosition += (windDirection + float3(0, 0.1, 0)) * windSpeed * _Time.y * 0.1;
                    float3 detailTex = tex3D(_DetailNoise, windPosition * _DetailTiling * 0.0001).rgb;
                    float detailTexFBM = dot(detailTex, float3(0.5, 0.25, 0.125));
                    
                    //根据高度从纤细到波纹的形状进行变化
                    float detailNoise = detailTexFBM;//lerp(detailTexFBM, 1.0 - detailTexFBM,saturate(heightFraction * 1.0));
                    //通过使用remap映射细节噪声，可以保留基本形状，在边缘进行变化
                    cloudDensity = Remap(cloudDensity, detailNoise * _DetailEffect, 1.0, 0.0, 1.0);
                }
                

                float density = cloudDensity * _DensityMultiplier * 0.01;
                
                return density;
            }

            float3 lightMarching(float sphereCenter,float sphereRadius,float3 position,float3 lightDir, int stepCount = 8){
                float2 dstCloud_light = RayCloudLayerDst(sphereCenter, sphereRadius, _CloudHeightRange.x, _CloudHeightRange.y, position, lightDir, false);
                float dstInsideCloud = dstCloud_light.y;

                float stepSize = dstInsideCloud / stepCount;
                float totalDensity = 0;
                float3 stepVec = lightDir * stepSize;
                for(int i = 0; i < stepCount; i ++){
                    position += stepVec;
                    totalDensity += max(0, SampleCloudDensity(sphereCenter, sphereRadius, position) * stepSize);
                }
                float transmittance = BeerPowder(totalDensity,_Absorption);
                float3 lightTransmittance = _DarknessThreshold + (1.0 - _DarknessThreshold) * transmittance;
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
                float3 viewDir = mul(unity_CameraInvProjection, float4(v.uv * 2.0 - 1.0, 0, -1)).xyz;
                o.viewDir = mul(unity_CameraToWorld, float4(viewDir, 0)).xyz;
                return o;
            }

            half4 Pixel(vertexOutput i): SV_TARGET{
                half4 baseColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv);
                float dstToObj = LinearEyeDepth(depth, _ZBufferParams);
                
                Light mainLight = GetMainLight();
                float3 viewDir = normalize(i.viewDir);
                float3 lightDir = normalize(mainLight.direction);
                float3 cameraPos = GetCameraPositionWS();

                float earthRadius = 6357000.0f;
                float3 sphereCenter = float3(cameraPos.x, -earthRadius, cameraPos.z); //地球中心坐标, 使水平行走永远不会逃出地球, 高度0为地表
                float2 dstCloud = RayCloudLayerDst(sphereCenter, earthRadius, _CloudHeightRange.x, _CloudHeightRange.y, cameraPos, viewDir);
                float dstToCloud = dstCloud.x;
                float dstInCloud = dstCloud.y;
                if (dstInCloud <= 0 || dstToObj <= dstToCloud)
                {
                    return baseColor;
                }
                float endPos = dstToCloud + dstInCloud;

                float cosAngle = dot(i.viewDir, lightDir);
                float3 phaseVal = phase(cosAngle);
                
                const float stepCount = 48;
                float3 entryPoint = cameraPos + viewDir * dstToCloud;
                float3 currentPoint = entryPoint;
                float stepSize = dstInCloud / _StepCount; 
                float3 stepVec = stepSize * viewDir;

                float buleNoise = tex2Dlod(_BlueNoise,float4(i.uv,0,0)).r;
                float dstTravelled = dstToCloud + _ShapeMarchLength * buleNoise * _BlueNoiseEffect;                       
                float3 lightEnergy = 0;
                float transmittance = 1.0; 

                // 云测试密度
                float densityTest = 0;
                float densityPrevious = 0;
                int   densitySampleCount_zero = 0;
                
                [unroll(12)]
                for(int i = 0; i < _StepCount; i++){
                    if (densityTest = 0){
                        dstTravelled += _ShapeMarchLength * 2;
                        currentPoint = cameraPos + viewDir * dstTravelled;
                        if (dstToObj <= dstTravelled || endPos <= dstTravelled){
                            break;
                        }
                        densityTest = SampleCloudDensity(sphereCenter, earthRadius, currentPoint);
                        if (densityTest > 0){
                            dstTravelled -= _ShapeMarchLength;
                        }
                    }
                    else{
                        currentPoint = cameraPos + viewDir * dstTravelled;
                        float cloudDensity = SampleCloudDensity(sphereCenter, earthRadius, currentPoint,false);
                        if (cloudDensity == 0 && densityPrevious == 0){
                            densitySampleCount_zero++;
                            //累计检测到指定数值，切换到大步进
                            if (densitySampleCount_zero > 8){
                                densityTest = 0;
                                densitySampleCount_zero = 0;
                                continue;
                            }
                        }
                        float intervalDensity = cloudDensity * _ShapeMarchLength;
                        if (intervalDensity > 0.01){
                            float3 lightTransmittance = lightMarching(sphereCenter, earthRadius, currentPoint, lightDir);
                            float3 cloudColor = Interpolation3(_ColorDark.rgb, _ColorCentral.rgb, _ColorBright.rgb, saturate(lightTransmittance), _ColorCentralOffset) * mainLight.color;
                            lightEnergy += intervalDensity * transmittance * cloudColor * phaseVal;
                            transmittance *= Beer(intervalDensity,_Absorption);
                            if (transmittance < 0.01){
                                break;
                            }
                        }
                        dstTravelled += _ShapeMarchLength;
                        if (dstToObj <= dstTravelled || endPos <= dstTravelled)
                        {
                            break;
                        }
                        densityPrevious = intervalDensity;
                    }
                }
                float3 color = baseColor.rgb + lightEnergy;
                return half4(color, transmittance);
            }
            ENDHLSL
        }
    }
}