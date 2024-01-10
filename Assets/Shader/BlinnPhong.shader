Shader "ShengFu/URP_Blinn-Phong_ShengFu"
{
    Properties
    {
        [Header(Specular)][Space(0)]
        [KeywordEnum(Phong,Blinn_phong)] _SPMODE ("镜面反射模式",float) = 0.0
        _SpecularPower ("高光强度", Range(1, 30)) = 1

        [Header(Texture)][Space(0)]
        [NoScaleOffset] _MainTex ("基础贴图", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}

        Pass
        {
            Name "MyForwardPass"
            Tags{"LightMode" = "UniversalForward"}
            
            ZTest Off
            ZWrite On

            HLSLPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                #pragma shader_feature _SPMODE_PHONG _SPMODE_BLINN_PHONG
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 这个变量不用在properties声明，只要在properties里面声明有纹理贴图，系统会自动给这种格式的变量赋值
            // 赋值是四个浮点数 前两个是缩放，对应inspector面板的tiling 后两个是位移，对应inspector面板的offfset
            // 变量的名字格式是固定的前面是纹理贴图的变量名 后面固定加上_ST
            float4 _MainTex_ST;
            UNITY_INSTANCING_BUFFER_START( Props )
                UNITY_DEFINE_INSTANCED_PROP( float, _SpecularPower)
            UNITY_INSTANCING_BUFFER_END( Props )

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            struct VertexInput
            {
                float4 vertex : POSITION; // 顶点信息 
                float4 normal : NORMAL;   // 法线信息 
                float2 uv0    : TEXCOORD0;
            };

            struct VertexOutput
            {
                float4 pos    : SV_POSITION; // 屏幕顶点位置
                float3 nDirWS : TEXCOORD0;   // 世界空间法线方向
                float4 posWS  : TEXCOORD1;   // 世界空间顶点位置
                float2 uv0    : TEXCOORD2;
            };
            
            VertexOutput vert(VertexInput v) 
            {
                VertexOutput o = (VertexOutput)0; 
                o.pos = TransformObjectToHClip(v.vertex);           // 顶点位置 OS>CS
                o.nDirWS = TransformObjectToWorldNormal(v.normal);  // 法线方向 OS>WS
                o.posWS = mul(unity_ObjectToWorld, v.vertex);       // 顶点位置 OS>WS
                o.uv0 = v.uv0 * _MainTex_ST.xy + _MainTex_ST.zw;
                return o; 
            }

            float4 frag(VertexOutput i) : COLOR
            {
                float3 ndir = i.nDirWS;
                float3 ldir = _MainLightPosition.xyz;
                float3 rdir = normalize(reflect(-ldir,ndir));
                float3 vdir = normalize(_WorldSpaceCameraPos.xyz - i.posWS.xyz);
                float3 hdir = normalize(ldir + vdir);

                float rdotv = dot(rdir, vdir);
                float ndoth = dot(ndir,hdir);
                float4 var_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv0);
                float3 baseCol = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.uv0);
                float _SpecularPower_var = UNITY_ACCESS_INSTANCED_PROP( Props, _SpecularPower );
                float phong = pow(max(0.0, rdotv), _SpecularPower );
                float blinn_phong = pow(max(0.0,ndoth),_SpecularPower );
                // half3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
                #if defined(_SPMODE_PHONG)
                    float3 finalRGB = baseCol + phong;
                #elif defined(_SPMODE_BLINN_PHONG)
                    float3 finalRGB = baseCol + blinn_phong;
                #endif
                return float4(finalRGB, 1.0);
            }
            ENDHLSL
        }
    }
}
