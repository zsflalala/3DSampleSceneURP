Shader "AtmosphericScattering/RuntimeSkybox"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "RenderPipeline" = "UniversalPipeline" "PreviewType" = "Skybox" }
        ZWrite Off Cull Off
        
        Pass
        {
            HLSLPROGRAM
            
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            
            #define _RENDERSUN 1
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "InScattering.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            #define SAMPLECOUNT_KSYBOX 64

            TEXTURE2D(_MainTex); 
            SAMPLER(sampler_MainTex);
            
            struct appdata
            {
                float3 vertex: POSITION;
                float3 uv : TEXCOORD0;
            };
            
            struct v2f
            {
                float4 positionCS: SV_POSITION;
                float3 positionOS: TEXCOORD0;
                float3 uv : TEXCOORD1;
                float3 viewVec : TEXCOORD2;
            };
            
            v2f vert(appdata v)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(v.vertex);
                o.positionOS = v.vertex;
                o.uv = v.uv;
                float3 ndcPos = float3(v.uv.xy * 2.0 - 1.0, 1); //直接把uv映射到ndc坐标
                float far = _ProjectionParams.z; //获取投影信息的z值，代表远平面距离
                float3 clipVec = float3(ndcPos.x, ndcPos.y, ndcPos.z * -1) * far; //裁切空间下的视锥顶点坐标
                o.viewVec = mul(unity_CameraInvProjection, clipVec.xyzz).xyz; //观察空间下的视锥向量
                return o;
            }

            float3 GetWorldPosition(float2 uv, float3 viewVec, out float depth, out float linearDepth)
            {
                depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,sampler_CameraDepthTexture,uv).r;//采样深度图
                depth = Linear01Depth(depth, _ZBufferParams); //转换为线性深度
                linearDepth = LinearEyeDepth(depth,_ZBufferParams);
                float3 viewPos = viewVec * depth; //获取实际的观察空间坐标（插值后）
                float3 worldPos = mul(unity_CameraToWorld, float4(viewPos,1)).xyz; //观察空间-->世界空间坐标
                return worldPos;
            }
                        
            half4 frag(v2f i): SV_Target
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                float deviceZ = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.uv);
                float linearDepth = 0;
                float3 positionWorldSpace = GetWorldPosition(i.uv, i.viewVec, deviceZ, linearDepth);
                // float3 rayDir = positionWorldSpace - _WorldSpaceCameraPos;
                float3 rayDir = normalize(TransformObjectToWorld(i.positionOS));

                float3 rayStart = _WorldSpaceCameraPos.xyz;
                float3 planetCenter = float3(0, -_PlanetRadius, 0);
                float3 lightDir = _MainLightPosition.xyz;
                float rayLength = length(rayDir);

                float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
                
                rayLength = intersection.y;
                intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius);
                if (intersection.x >= 0)
                    rayLength = min(rayLength, intersection.x);

                float3 extinction;
                float3 inscattering = IntegrateInscattering(rayStart, rayDir, rayLength, planetCenter, 1, lightDir, SAMPLECOUNT_KSYBOX, extinction);
                return float4(inscattering, 1);

                // if (deviceZ < 0.000001){
                //     float3 inscattering = IntegrateInscattering(rayStart, rayDir, rayLength, planetCenter, 1, lightDir, SAMPLECOUNT_KSYBOX, extinction);
                //     return float4(inscattering, 1);
                // }
                // else{
                //     float4 baseColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                //     float3 inscattering = IntegrateInscattering(rayStart, rayDir, rayLength, planetCenter, 1, lightDir, SAMPLECOUNT_KSYBOX, extinction);
                //     return float4(extinction *  baseColor + inscattering, 1);
                // }
                
            }
            ENDHLSL
        }
    }
}
