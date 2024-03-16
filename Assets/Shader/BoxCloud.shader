Shader "ShengFu/RayMarchingCloud"
{

	HLSLINCLUDE

	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

	float _step;
	float _rayStep;
	float _rayOffsetStrength;
	float4 _color;
	float3 _CamDir;
	float4x4 _InverseProjectionMatrix;
	float4x4 _InverseViewMatrix;
	float _shapeTiling;
	float _detailTiling;
	sampler3D _noiseTex;
	sampler3D _noiseDetail3D;
	sampler2D _weatherMap;
	sampler2D _maskNoise;
	sampler2D _BlueNoise;
	float4 _boundsMin;
	float4 _boundsMax;
	float3 _CameraDir;
	float _densityOffset;
	float _densityMultiplier;
	float4 _shapeNoiseWeights;
	float _detailWeights;
	float _detailNoiseWeight;

	TEXTURE2D(_CameraDepthTexture);
	SAMPLER(sampler_CameraDepthTexture);
	TEXTURE2D(_CameraColorTexture);
	SAMPLER(sampler_CameraColorTexture);
	TEXTURE2D(_LowDepthTexture);
	SAMPLER(sampler_LowDepthTexture);
	TEXTURE2D(_DownsampleColor);
	SAMPLER(sampler_DownsampleColor);
	TEXTURE2D(_MainTex);
	SAMPLER(sampler_MainTex);
	float4 _MainTex_ST;

	float4 _CameraDepthTexture_TexelSize;


	float4 _BlueNoiseCoords;
	float _lightAbsorptionTowardSun;
	float _lightAbsorptionThroughCloud;
	int _numStepsLight;
	float3 _WorldSpaceLightPos0;
	float4 _LightColor0;
	float _darknessThreshold;
	float4 _colA;
	float4 _colB;
	float _colorOffset1;
	float _colorOffset2;
	float4 _phaseParams; //(光方向的偏心率, 光方向的偏心率， HG基础值, hg结果的影响强度)
	float _heightWeights;
	float4x4 _TRSMatrix;
	float4 _xy_Speed_zw_Warp;


	//计算世界空间坐标
	float4 GetWorldSpacePosition(float depth, float2 uv)
	{
		// 屏幕空间 --> 视锥空间
		float4 view_vector = mul(_InverseProjectionMatrix, float4(2.0 * uv - 1.0, depth, 1.0));
		view_vector.xyz /= view_vector.w;
		//视锥空间 --> 世界空间
		float4x4 l_matViewInv = _InverseViewMatrix;
		float4 world_vector = mul(l_matViewInv, float4(view_vector.xyz, 1));
		return world_vector;
	}

	// Linear falloff.
	float CalcAttenuation(float d, float falloffStart, float falloffEnd)
	{
		return saturate((falloffEnd - d) / (falloffEnd - falloffStart));
	}
    // 重映射
	float remap(float original_value, float original_min, float original_max, float new_min, float new_max)
	{
		return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
	}

	// Henyey-Greenstein
	float hg(float a, float g) {
		float g2 = g * g;
		return (1 - g2) / (4 * 3.1415 * pow(1 + g2 - 2 * g * (a), 1.5));
	}

	float phase(float a) {
		float blend = .5;
		float hgBlend = hg(a, _phaseParams.x) * (1 - blend) + hg(a, -_phaseParams.y) * blend;
		return _phaseParams.z + hgBlend * _phaseParams.w;
	}

	float sampleDensity(float3 rayPos)
	{
		float4 boundsCentre = (_boundsMax + _boundsMin) * 0.5;
		float3 size = _boundsMax - _boundsMin;
		float speedShape = _Time.y * _xy_Speed_zw_Warp.x;
		float speedDetail = _Time.y * _xy_Speed_zw_Warp.y;

		float3 uvwShape = rayPos * _shapeTiling + float3(speedShape, speedShape * 0.2, 0);
		float3 uvwDetail = rayPos * _detailTiling + float3(speedDetail, speedDetail * 0.2, 0);

		float2 uv = (size.xz * 0.5f + (rayPos.xz - boundsCentre.xz)) / max(size.x, size.z);

		float4 maskNoise = tex2Dlod(_maskNoise, float4(uv + float2(speedShape * 0.5, 0), 0, 0));
		float4 weatherMap = tex2Dlod(_weatherMap, float4(uv + float2(speedShape * 0.4, 0), 0, 0));

		float4 shapeNoise = tex3Dlod(_noiseTex, float4(uvwShape + (maskNoise.r * _xy_Speed_zw_Warp.z * 0.1), 0));
		float4 detailNoise = tex3Dlod(_noiseDetail3D, float4(uvwDetail + (shapeNoise.r * _xy_Speed_zw_Warp.w * 0.1), 0));

		//边缘衰减
		const float containerEdgeFadeDst = 10;
		float dstFromEdgeX = min(containerEdgeFadeDst, min(rayPos.x - _boundsMin.x, _boundsMax.x - rayPos.x));
		float dstFromEdgeZ = min(containerEdgeFadeDst, min(rayPos.z - _boundsMin.z, _boundsMax.z - rayPos.z));
		float edgeWeight = min(dstFromEdgeZ, dstFromEdgeX) / containerEdgeFadeDst;

		float gMin = remap(weatherMap.x, 0, 1, 0.1, 0.6);
		float gMax = remap(weatherMap.x, 0, 1, gMin, 0.9);
		float heightPercent = (rayPos.y - _boundsMin.y) / size.y;
		float heightGradient = saturate(remap(heightPercent, 0.0, gMin, 0, 1)) * saturate(remap(heightPercent, 1, gMax, 0, 1));
		float heightGradient2 = saturate(remap(heightPercent, 0.0, weatherMap.r, 1, 0)) * saturate(remap(heightPercent, 0.0, gMin, 0, 1));
		heightGradient = saturate(lerp(heightGradient, heightGradient2, _heightWeights));

		heightGradient *= edgeWeight;

		float4 normalizedShapeWeights = _shapeNoiseWeights / dot(_shapeNoiseWeights, 1);
		float shapeFBM = dot(shapeNoise, normalizedShapeWeights) * heightGradient;
		float baseShapeDensity = shapeFBM + _densityOffset * 0.01;


		if (baseShapeDensity > 0)
		{
			float detailFBM = pow(detailNoise.r, _detailWeights);
			float oneMinusShape = 1 - baseShapeDensity;
			float detailErodeWeight = oneMinusShape * oneMinusShape * oneMinusShape;
			float cloudDensity = baseShapeDensity - detailFBM * detailErodeWeight * _detailNoiseWeight;

			return saturate(cloudDensity * _densityMultiplier);
		}
		return 0;
	}

					  //边界框最小值       边界框最大值     //世界相机位置      反向世界空间光线方向  
	float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRaydir)
	{
		float3 t0 = (boundsMin - rayOrigin) * invRaydir;
		float3 t1 = (boundsMax - rayOrigin) * invRaydir;
		float3 tmin = min(t0, t1);
		float3 tmax = max(t0, t1);

		float dstA = max(max(tmin.x, tmin.y), tmin.z); //进入点
		float dstB = min(tmax.x, min(tmax.y, tmax.z)); //出去点

		float dstToBox = max(0, dstA);
		float dstInsideBox = max(0, dstB - dstToBox);
		return float2(dstToBox, dstInsideBox);
	}

	// case 1: 射线从外部相交 (0 <= dstA <= dstB)
	// dstA是dst到最近的交叉点，dstB dst到远交点
	// case 2: 射线从内部相交 (dstA < 0 < dstB)
	// dstA是dst在射线后相交的, dstB是dst到正向交集
	// case 3: 射线没有相交 (dstA > dstB)

	//计算当前光线步进到的点从光源方向投射过来的亮度部分，应该是In-Scattering Probability Function PSE，内散射部分
					//当前步进到的位置       累计步进距离          光源方向
	float3 lightmarch(float3 position, float dstTravelled, float3 lightDir)
	{
		float3 dirToLight = lightDir;//_WorldSpaceLightPos0.xyz;

		//灯光方向与边界框求交，超出部分不计算
		float dstInsideBox = rayBoxDst(_boundsMin, _boundsMax, position, 1 / dirToLight).y;
		float stepSize = dstInsideBox / 8;
		float totalDensity = 0;
		for (int step = 0; step < 8; step++) { //灯光步进次数
			position += dirToLight * stepSize; //从步进到的位置向灯光步进
			//totalDensity += max(0, sampleDensity(position) * stepSize);                     totalDensity += max(0, sampleDensity(position) * stepSize);
			totalDensity += max(0, sampleDensity(position)); //采样新位置的density

		}
		float transmittance = exp(-totalDensity * _lightAbsorptionTowardSun); //计算透射率

		//将重亮到暗映射为 3段颜色 ,亮->灯光颜色 中->ColorA 暗->ColorB
		float3 cloudColor = lerp(_colA, _LightColor0, saturate(transmittance * _colorOffset1)); //透射率越大则光照越占主要影响，_colorOffset1越大则越偏向太阳光
		cloudColor = lerp(_colB, cloudColor, saturate(pow(transmittance * _colorOffset2, 3))); //pow(透射率,3)来强调暗色部分，
		//			最暗颜色      +    透射率 * (1-最暗颜色) * 云颜色     ，  就是做了个打底色，外部忘记设置接口指定了 
		return _darknessThreshold + transmittance * (1 - _darknessThreshold) * cloudColor;
	}

	struct AttributesDefault
	{
		float3 vertex : POSITION;
		float2 uv : TEXCOORD0;
	};

	struct VaryingsDefault
	{
		float4 vertex : SV_POSITION;
		float2 texcoord : TEXCOORD0;
	};

	VaryingsDefault VertDefault(AttributesDefault v)
	{
		VaryingsDefault o;
		o.vertex = TransformObjectToHClip(v.vertex.xyz);
		o.texcoord = v.uv;
        //#if UNITY_UV_STARTS_AT_TOP
        //		o.texcoord = o.texcoord * float2(1.0, -1.0) + float2(0.0, 1.0);
        //#endif
		return o;
	}

	float4 Frag(VaryingsDefault i) : SV_Target
	{
		//float depth = SAMPLE_DEPTH_TEXTURE(_LowDepthTexture, sampler_LowDepthTexture, i.texcoord);
		//相机深度缓冲
		float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.texcoord);
		//相机位置
		float3 rayPos = _WorldSpaceCameraPos;
		
		//世界空间坐标
		float3 worldPos = ComputeWorldSpacePosition(i.texcoord, depth, UNITY_MATRIX_I_VP);
		//世界空间相机方向
		float3 worldViewDir = normalize(worldPos - rayPos.xyz);
		//相机到片元的距离
		float depthEyeLinear = length(worldPos - _WorldSpaceCameraPos);

		float2 rayToContainerInfo = rayBoxDst(_boundsMin, _boundsMax, rayPos, (1 / worldViewDir));
		float dstToBox = rayToContainerInfo.x; //相机到容器的距离
		float dstInsideBox = rayToContainerInfo.y; //返回光线是否在容器中

		// 与云云容器的交汇点
		float3 entryPoint = rayPos + worldViewDir * dstToBox;

		//相机到物体的距离 - 相机到容器的距离
		float dstLimit = min(depthEyeLinear - dstToBox, dstInsideBox);
		
		//添加抖动
		float blueNoise = tex2D(_BlueNoise, i.texcoord * _BlueNoiseCoords.xy + _BlueNoiseCoords.zw).r;

		//向灯光方向的散射更强一些
		Light mainLight = GetMainLight(TransformWorldToShadowCoord(worldPos));
		float cosAngle = dot(worldViewDir, mainLight.direction);
		float3 phaseVal = phase(cosAngle); //当前视角方向和灯光方向而得出的米氏散射近似结果(云的白色)
		
		float dstTravelled = blueNoise.r * _rayOffsetStrength;
		float sumDensity = 1;
		float3 lightEnergy = 0;
		const float sizeLoop = 512;
		float stepSize = exp(_step)*_rayStep;

		for (int j = 0; j < sizeLoop; j++)
		{
			if (dstTravelled < dstLimit)
			{
				rayPos = entryPoint + (worldViewDir * dstTravelled); //当前步进到的位置
				float density = sampleDensity(rayPos); //采样噪声贴图
				if (density > 0)
				{
					//从光源到当前点为止的颜色积累
					float3 lightTransmittance = lightmarch(rayPos, dstTravelled, mainLight.direction); //当前光线步进到的点从光源方向投射过来的亮度部分(瑞利散射)
					lightEnergy += density * stepSize * sumDensity * lightTransmittance * phaseVal; //当前采样系数 * 步长 * 总系数 * 光源透射亮度 * 米氏散射代替公式(米氏散射)
					sumDensity *= exp(-density * stepSize * _lightAbsorptionThroughCloud); //计算累计步长结果的透射率

					//透过率太小说明变成黑色了，
					if (sumDensity < 0.01)
						break;
				}
			}
			dstTravelled += stepSize;
		}
		float4 color = SAMPLE_TEXTURE2D(_CameraColorTexture, sampler_CameraColorTexture, i.texcoord); //当前点原本的颜色
		float4 cloudColor = float4(lightEnergy, sumDensity); //(光照的颜色, 原色保持程度)

		color.rgb *= cloudColor.a; //透过率越大则原本颜色越能维持
		color.rgb += cloudColor.rgb; //然后加上光照颜色
		return color;
	}

	ENDHLSL


	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			HLSLPROGRAM

			#pragma vertex VertDefault
			#pragma fragment Frag

			ENDHLSL
		}
	}
}